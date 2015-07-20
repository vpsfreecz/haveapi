module HaveAPI::Authentication::Token
  module Resources
    class Token < HaveAPI::Resource
      auth false
      version :all

      class << self
        attr_accessor :token_instance
      end

      class Request < HaveAPI::Action
        route ''
        http_method :post

        input(:hash) do
          string :login, label: 'Login', required: true
          string :password, label: 'Password', required: true
          string :lifetime, label: 'Lifetime', required: true,
                  choices: %i(fixed renewable_manual renewable_auto permanent),
                  desc: <<END
fixed - the token has a fixed validity period, it cannot be renewed
renewable_manual - the token can be renewed, but it must be done manually via renew action
renewable_auto - the token is renewed automatically to now+interval every time it is used
permanent - the token will be valid forever, unless deleted
END
          integer :interval, label: 'Interval',
                  desc: 'How long will requested token be valid, in seconds.',
                  default: 60*5, fill: true
        end

        output(:hash) do
          string :token
          datetime :valid_to
        end

        authorize do
          allow
        end

        def exec
          klass = self.class.resource.token_instance[@version]

          user = klass.send(
              :find_user_by_credentials,
              request,
              input[:login],
              input[:password]
          )
          error('bad login or password') unless user

          token = expiration = nil

          loop do
            begin
              token = klass.send(:generate_token)
              expiration = klass.send(:save_token,
                                      @request,
                                      user,
                                      token,
                                      params[:token][:lifetime],
                                      params[:token][:interval])
              break

            rescue TokenExists
              next
            end
          end

          {token: token, valid_to: expiration}
        end
      end

      class Revoke < HaveAPI::Action
        # route ''
        http_method :post
        auth true

        authorize do
          allow
        end

        def exec
          klass = self.class.resource.token_instance[@version]
          klass.send(:revoke_token, request, current_user, klass.token(request))
        end
      end

      class Renew < HaveAPI::Action
        http_method :post
        auth true

        output(:hash) do
          datetime :valid_to
        end

        authorize do
          allow
        end

        def exec
          klass = self.class.resource.token_instance[@version]
          klass.send(:renew_token, request, current_user, klass.token(request))
        end
      end
    end
  end
end

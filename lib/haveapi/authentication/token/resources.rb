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

        input do
          string :login, label: 'Login', required: true
          string :password, label: 'Password', required: true
          integer :validity, label: 'Validity',
                  desc: 'How long will requested token be valid, in seconds. 0 is permanent.',
                  default: 60*5
        end

        output do
          string :token
          datetime :valid_until
        end

        authorize do
          allow
        end

        def exec
          klass = self.class.resource.token_instance[@version]

          user = klass.send(:find_user_by_credentials, params[:token][:login], params[:token][:password])
          error('bad login or password') unless user

          token = nil

          loop do
            begin
              token = klass.send(:generate_token)
              klass.send(:save_token, user, token, params[:token][:validity])
              break

            rescue TokenExists
              next
            end
          end

          {token: token}
        end
      end

      class Revoke < HaveAPI::Action
        # route ''
        http_method :post
        auth true
      end
    end
  end
end

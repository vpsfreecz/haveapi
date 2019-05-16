require 'securerandom'

module API::Authentication
  class Token < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        user = ::User.authenticate(
          req.request,
          req.input[:user],
          req.input[:password],
        )

        if !user
          res.error = 'invalid user or password'
          next res
        end

        token = SecureRandom.hex(50)
        valid_to =
          if req.input[:lifetime] == 'permanent'
            nil
          else
            Time.now + req.input[:interval]
          end

        ::AuthToken.create!(
          user: user,
          token: token,
          valid_to: valid_to,
          lifetime: req.input[:lifetime],
          interval: req.input[:interval],
          label: req.request.user_agent,
        )

        res.token = token
        res.valid_to = valid_to
        res.complete = true
        res.ok
      end
    end

    renew do
      handle do |req, res|
        t = ::AuthToken.find_by!(user: req.user, token: req.token)

        if t.lifetime.start_with?('renewable')
          t.renew
          t.save!
          res.valid_to = t.valid_to
          res.ok
        else
          res.error = 'unable to renew token'
          res
        end
      end
    end

    revoke do
      handle do |req, res|
        ::AuthToken.find_by!(user: req.user, token: req.token).destroy!
        res.ok
      end
    end

    def find_user_by_token(request, token)
      t = ::AuthToken.where(
        'token = ? AND ((lifetime = 3 AND valid_to IS NULL) OR valid_to >= ?)',
        token, Time.now
      ).take

      return unless t

      ::AuthToken.increment_counter(:use_count, t.id)

      if t.lifetime == 'renewable_auto'
        t.renew
        t.save!
      end

      t.user
    end
  end
end

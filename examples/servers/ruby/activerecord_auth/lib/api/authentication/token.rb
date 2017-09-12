module API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def generate_token
      ::AuthToken.generate
    end

    def save_token(request, user, token, lifetime, interval)
      t = ::AuthToken.create!(
          user: user,
          token: token,
          valid_to: (lifetime != 'permanent' ? Time.now + interval : nil),
          lifetime: lifetime,
          interval: interval,
          label: request.user_agent
      )

      t.valid_to && t.valid_to.strftime('%FT%T%z')
    end

    def revoke_token(request, user, token)
      ::AuthToken.find_by!(user: user, token: token).destroy!
    end

    def renew_token(request, user, token)
      t = ::AuthToken.find_by!(user: user, token: token)

      if t.lifetime.start_with?('renewable')
        t.renew
        t.save!
        t.valid_to
      end
    end

    def find_user_by_credentials(request, username, password)
      ::User.authenticate(request, username, password)
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

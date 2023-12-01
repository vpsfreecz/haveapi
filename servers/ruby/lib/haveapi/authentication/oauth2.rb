module HaveAPI::Authentication
  module OAuth2
    # Configure the oauth2 provider
    # @param cfg [Config]
    def self.with_config(cfg)
      Provider.with_config(cfg)
    end
  end
end

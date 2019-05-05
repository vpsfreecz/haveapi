module HaveAPI::Authentication
  module Token
    # Configure the token provider
    # @param cfg [Config]
    def self.with_config(cfg)
      Provider.with_config(cfg)
    end
  end
end

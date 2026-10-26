module HaveAPI::Schema
  module Capture
    def self.fetch(url:, api_version:, profile:, basic_user: nil, basic_password: nil, token: nil, diagnostics: [])
      mount = validate_options(url: url, api_version: api_version, profile: profile,
                               basic_user: basic_user, basic_password: basic_password, token: token)
      begin
        require 'rest-client'
      rescue LoadError
        raise Error, 'capture dependencies are unavailable; prepare the haveapi-client bundle', cause: nil
      end

      headers = { accept: :json }
      if token
        discovery = snapshot(request(url, headers), url, api_version, profile, mount, [])
        provider = discovery.fetch('description').fetch('authentication')['token']
        raise Error, 'API does not advertise HaveAPI token authentication' unless provider.is_a?(Hash)

        headers = headers.merge(token_headers(provider, token))
      end
      snapshot(request(url, headers, basic_user, basic_password), url, api_version, profile, mount, diagnostics)
    end

    def self.validate_options(url:, api_version:, profile:, basic_user: nil, basic_password: nil, token: nil)
      Snapshot.version!(api_version)
      endpoint = Snapshot.endpoint!(url)
      suffix = "v#{api_version}/"
      unless endpoint.path.end_with?("/#{suffix}")
        raise Error, 'fetch URL must select the exact requested version'
      end
      raise Error, 'profile must be a nonempty label' unless profile.is_a?(String) && !profile.strip.empty?
      if !token.nil? && (!basic_user.nil? || !basic_password.nil?)
        raise Error, 'Basic and token authentication are mutually exclusive'
      end

      if (!basic_user.nil? || !basic_password.nil?) && !(credential?(basic_user) && !basic_user.include?(':') && credential?(basic_password))
        raise Error, 'Basic authentication requires a valid user and password'
      end
      raise Error, 'existing token must be a nonempty header value' if !token.nil? && !credential?(token)

      endpoint.path.delete_suffix(suffix)
    end

    def self.credential?(value)
      value.is_a?(String) && !value.empty? && !value.match?(/[\x00-\x1f\x7f]/)
    end

    def self.request(url, headers, basic_user = nil, basic_password = nil)
      options = {
        method: :options, url: url, headers: headers, verify_ssl: true,
        max_redirects: 0, open_timeout: 10, read_timeout: 30
      }
      options.update(user: basic_user, password: basic_password) if basic_user
      response = RestClient::Request.execute(options)
      unless response.code >= 200 && response.code < 300
        raise Error, 'metadata acquisition failed (HTTP or redirect error)'
      end

      JSON.parse(response.to_s)
    rescue StandardError
      raise Error, 'metadata acquisition failed (HTTP, redirect or response error)', cause: nil
    end

    def self.snapshot(envelope, url, version, profile, mount, diagnostics)
      Snapshot.from_envelope(envelope, api_version: version, source_url: url,
                                       profile: profile, mount_path: mount, diagnostics: diagnostics)
    rescue Error, ArgumentError, TypeError, NoMethodError
      raise Error, 'metadata response is not a valid successful protocol 2 description for the requested version', cause: nil
    end

    def self.token_headers(provider, token)
      # Supplying a token prevents this existing provider from acquiring or renewing one.
      require 'haveapi/client'
      HaveAPI::Client::Authentication::Token.new(nil, { http_header: provider['http_header'] }, token: token).request_headers
    rescue LoadError
      raise Error, 'capture dependencies are unavailable; prepare the haveapi-client bundle', cause: nil
    rescue StandardError
      raise Error, 'API advertises an invalid HaveAPI token HTTP header', cause: nil
    end
    private_class_method :credential?, :request, :snapshot, :token_headers
  end
end

require 'active_support/key_generator'
require 'active_support/message_encryptor'
require 'active_support/security_utils'
require 'base64'
require 'cgi'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'uri'

module HaveAPI
  # Optional confidential OAuth client used only by the HTML documentation.
  class DocumentationOAuth
    class Invalid < ArgumentError; end
    class Failure < StandardError; end

    COOKIE_LIMIT = 3800
    RESPONSE_LIMIT = 16_384
    PENDING_LIFETIME = 600
    FIELDS = %i[client_id client_secret redirect_uri session_secret scope session_lifetime switch_user].freeze

    class Transport
      def post(uri, parameters)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(parameters)
        body = +''
        status = nil
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                                verify_mode: OpenSSL::SSL::VERIFY_PEER,
                                                open_timeout: 5, read_timeout: 10, write_timeout: 10) do |http|
          http.max_retries = 0
          http.request(request) do |response|
            status = response.code.to_i
            response.read_body do |chunk|
              raise Failure, 'Documentation OAuth request failed' if body.bytesize + chunk.bytesize > RESPONSE_LIMIT

              body << chunk
            end
          end
        end
        raise Failure, 'Documentation OAuth request failed' unless status&.between?(200, 299)

        body
      rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPError, Net::HTTPBadResponse
        raise Failure, 'Documentation OAuth request failed'
      end
    end

    module Helpers
      def documentation_oauth_controls
        client = settings.api_server.documentation_oauth
        return unless client

        client.controls(self, @v || settings.api_server.default_version)
      end

      private

      def documentation_authenticate(version)
        client = settings.api_server.documentation_oauth
        client ? client.authenticate(self, version) : super
      end
    end

    def initialize(**options)
      raise Invalid, 'Unknown documentation OAuth configuration' unless (options.keys - FIELDS).empty?

      @client_id = scalar(options[:client_id], 256)
      @client_secret = scalar(options[:client_secret], 2048)
      @redirect_uri = endpoint(options[:redirect_uri], query: false)
      secret = options[:session_secret]
      unless secret.is_a?(String) && secret.bytesize.between?(64, 4096)
        raise Invalid, 'Documentation OAuth requires a session secret of at least 64 bytes'
      end

      @scope = options.fetch(:scope, [])
      unless @scope.is_a?(Array) && @scope.length <= 32 && @scope.all? do |value|
               value.is_a?(String) && value.bytesize.between?(1, 256) && value.match?(/\A[\x21\x23-\x5b\x5d-\x7e]+\z/)
             end
        raise Invalid, 'Invalid documentation OAuth scope'
      end

      @scope = @scope.map { |value| value.dup.freeze }.freeze
      @lifetime = options.fetch(:session_lifetime, 3600)
      unless @lifetime.is_a?(Integer) && @lifetime.between?(1, 86_400)
        raise Invalid, 'Invalid documentation OAuth session lifetime'
      end

      @switch_user = options.fetch(:switch_user, false)
      unless @switch_user.equal?(true) || @switch_user.equal?(false)
        raise Invalid, 'Invalid documentation OAuth switch-user capability'
      end

      @origin = "#{@redirect_uri.scheme}://#{@redirect_uri.host}"
      @origin += ":#{@redirect_uri.port}" unless @redirect_uri.port == 443
      key = ActiveSupport::KeyGenerator.new(secret, iterations: 65_536)
                                       .generate_key('haveapi.documentation-oauth.v1', 32)
      @encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
      @transport = Transport.new
    end

    def inspect
      '#<HaveAPI::DocumentationOAuth configured>'
    end

    def mount(server, sinatra)
      raise Invalid, 'Documentation OAuth is already mounted' if @server

      @server = server
      @path = server.root.end_with?('/') ? server.root : "#{server.root}/"
      @routes = %w[login callback logout].to_h { |name| [name, "#{@path}_documentation/oauth/#{name}"] }.freeze
      unless @redirect_uri.path == @routes.fetch('callback')
        raise Invalid, 'Documentation OAuth callback does not match the API mount'
      end

      metadata = server.auth_chain.provider_descriptions(server.default_version)[:oauth2]
      raise Invalid, 'Documentation OAuth requires an OAuth provider' unless metadata.is_a?(Hash)

      @endpoints = %i[authorize token revoke].to_h do |name|
        [name, endpoint(metadata[:"#{name}_url"])]
      end.freeze
      binding = Digest::SHA256.hexdigest([@client_id, @redirect_uri.to_s, @path].join("\0"))
      @purposes = %w[pending session].to_h { |kind| [kind, "haveapi.docs.#{binding}.#{kind}"] }.freeze
      @names = %w[pending session].to_h { |kind| [kind, "haveapi_docs_#{Digest::SHA256.hexdigest(@path)[0, 12]}_#{kind}"] }.freeze
      that = self
      sinatra.get(@routes.fetch('login')) { that.login(self) }
      sinatra.get(@routes.fetch('callback')) { that.callback(self) }
      sinatra.post(@routes.fetch('logout')) { that.logout(self) }
    end

    def authenticate(handler, version)
      handler.instance_variable_set(:@documentation_oauth_csrf, nil)
      protect_response(handler, referrer_policy: 'strict-origin')
      return unless documentation_origin?(handler) && (handler.request.get? || handler.request.head?)

      session = read_cookie(handler, 'session')
      return unless session

      user = @server.auth_chain.authenticate_oauth2_token(version, handler.request, session.fetch('token'))
      if user
        handler.instance_variable_set(:@documentation_oauth_csrf, session.fetch('csrf'))
      else
        clear_cookie(handler, 'session')
        handler.instance_variable_set(:@documentation_oauth_message, 'Your documentation session ended. Sign in again.')
      end
      user
    end

    def controls(handler, version)
      selection = handler.documentation_selection
      destination = return_location('version' => version.to_s, **selection)
      csrf = handler.instance_variable_get(:@documentation_oauth_csrf)
      controls = {
        signed_in: !csrf.nil?, csrf_token: csrf,
        login_url: "#{@origin}#{@routes.fetch('login')}?#{URI.encode_www_form(destination)}",
        logout_url: "#{@origin}#{@routes.fetch('logout')}",
        message: handler.instance_variable_get(:@documentation_oauth_message)
      }
      controls[:switch_user] = true if @switch_user && csrf
      controls
    end

    def login(handler)
      protect_response(handler)
      require_origin(handler)
      destination = return_location(strict_query(handler, %w[version page resource fragment]))
      expiry = Time.now.to_f + PENDING_LIFETIME
      state = SecureRandom.urlsafe_base64(32)
      verifier = SecureRandom.urlsafe_base64(48)
      write_cookie(handler, 'pending', { 'state' => state, 'verifier' => verifier, 'return' => destination, 'expires' => expiry })
      query = URI.decode_www_form(@endpoints.fetch(:authorize).query.to_s)
      query += { client_id: @client_id, response_type: 'code', redirect_uri: @redirect_uri.to_s,
                 scope: @scope.join(' '), state:, code_challenge_method: 'S256',
                 code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }.to_a
      target = @endpoints.fetch(:authorize).dup
      target.query = URI.encode_www_form(query)
      handler.redirect(target.to_s, 302)
    rescue Failure, Invalid
      failure_page(handler)
    end

    def callback(handler)
      protect_response(handler)
      require_origin(handler)
      pending = read_cookie(handler, 'pending')
      clear_cookie(handler, 'pending')
      values = strict_query(handler, %w[code state error error_description error_uri])
      unless pending && !values.has_key?('error') && nonce?(values['state']) &&
             secure_equal?(values['state'], pending['state']) && token?(values['code'])
        raise Failure, 'Documentation sign-in failed'
      end

      data = JSON.parse(@transport.post(@endpoints.fetch(:token), credentials.merge(
                                                                    'grant_type' => 'authorization_code', 'code' => values.fetch('code'),
                                                                    'redirect_uri' => @redirect_uri.to_s, 'code_verifier' => pending.fetch('verifier')
                                                                  )))
      unless data.is_a?(Hash) && token?(data['access_token']) && data['token_type'].to_s.downcase == 'bearer'
        raise Failure, 'Documentation sign-in failed'
      end

      duration = Float(data['expires_in'])
      raise Failure, 'Documentation sign-in failed' unless duration.finite? && duration > 0

      expiry = Time.now.to_f + [duration, @lifetime].min
      write_cookie(handler, 'session', { 'token' => data.fetch('access_token'), 'expires' => expiry,
                                         'csrf' => SecureRandom.urlsafe_base64(32) })
      handler.redirect(destination_url(return_location(pending.fetch('return'))), 303)
    rescue Failure, Invalid, JSON::ParserError, ArgumentError, TypeError
      failure_page(handler)
    end

    def logout(handler)
      protect_response(handler)
      require_origin(handler)
      switch_user = switch_user_request?(handler)
      session = read_cookie(handler, 'session')
      csrf = handler.params['csrf']
      unless handler.request.env['HTTP_ORIGIN'] == @origin && session && nonce?(csrf) && secure_equal?(csrf, session['csrf'])
        handler.halt(403, 'Invalid documentation sign-out request')
      end
      clear_cookie(handler, 'session')
      clear_cookie(handler, 'pending')
      begin
        @transport.post(@endpoints.fetch(:revoke), credentials.merge('token' => session.fetch('token'), 'token_type_hint' => 'access_token'))
      rescue Failure
        handler.halt(502, { 'content-type' => 'text/html; charset=utf-8' },
                     '<p>Local sign-out succeeded, but the server session may remain until it expires.</p>' \
                     "<p><a href=\"#{CGI.escapeHTML(destination_url('version' => @server.default_version.to_s))}\">Return to documentation</a></p>")
      end
      if switch_user
        handler.redirect("#{@origin}#{@routes.fetch('login')}?#{URI.encode_www_form(version: @server.default_version.to_s)}", 303)
      end
      handler.redirect(destination_url('version' => @server.default_version.to_s), 303)
    end

    private

    def scalar(value, limit)
      unless value.is_a?(String) && value.bytesize.between?(1, limit) && value.valid_encoding? && !value.match?(/[\x00-\x1f\x7f]/)
        raise Invalid, 'Invalid documentation OAuth configuration'
      end

      value.dup.freeze
    end

    def endpoint(value, query: true)
      uri = URI.parse(scalar(value, 2048))
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.fragment && (query || !uri.query) &&
             uri.path.start_with?('/') && !uri.path.match?(/[\\\s]/)
        raise Invalid, 'Documentation OAuth requires fixed HTTPS URLs'
      end

      uri.freeze
    rescue URI::InvalidURIError
      raise Invalid, 'Documentation OAuth requires fixed HTTPS URLs'
    end

    def documentation_origin?(handler)
      handler.request.scheme == 'https' && handler.request.base_url == @origin
    end

    def require_origin(handler)
      handler.halt(400, 'Documentation sign-in requires its configured HTTPS origin') unless documentation_origin?(handler)
    end

    def protect_response(handler, referrer_policy: 'no-referrer')
      handler.headers('Cache-Control' => 'private, no-store', 'Referrer-Policy' => referrer_policy)
    end

    def strict_query(handler, fields)
      query = handler.request.query_string
      raise Failure, 'Invalid documentation OAuth request' if query.bytesize > 8192 || query.match?(/%(?![0-9a-f]{2})/i)

      pairs = URI.decode_www_form(query)
      unless pairs.all? { |key, value| fields.include?(key) && value.bytesize <= 2048 && value.valid_encoding? } &&
             pairs.map(&:first).uniq.length == pairs.length
        raise Failure, 'Invalid documentation OAuth request'
      end

      pairs.to_h
    rescue ArgumentError
      raise Failure, 'Invalid documentation OAuth request'
    end

    def return_location(fields)
      unless fields.is_a?(Hash) && (fields.keys - %w[version page resource fragment]).empty? &&
             fields.values.all? { |value| value.is_a?(String) && value.bytesize <= 256 }
        raise Failure, 'Invalid documentation return location'
      end

      selected = { 'version' => fields.fetch('version', @server.default_version.to_s) }.merge(fields)
      unless @server.versions.map(&:to_s).include?(selected['version']) &&
             (!selected['page'] || %w[overview authentication resources].include?(selected['page'])) &&
             (!selected['resource'] || selected['resource'].match?(/\A[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*\z/)) &&
             !(selected['resource'] && selected['page']) &&
             (!selected['fragment'] || selected['fragment'].match?(/\A[A-Za-z0-9_.-]{1,256}\z/))
        raise Failure, 'Invalid documentation return location'
      end

      selected
    end

    def destination_url(destination)
      version = @server.versions.find { |value| value.to_s == destination.fetch('version') }
      path = @server.version_prefix(version)
      query = destination.slice('page', 'resource')
      result = "#{@origin}#{path}"
      result += "?#{URI.encode_www_form(query)}" unless query.empty?
      result += "##{destination['fragment']}" if destination['fragment']
      result
    end

    def credentials
      { 'client_id' => @client_id, 'client_secret' => @client_secret }
    end

    def switch_user_request?(handler)
      request = handler.request
      parameters = handler.params
      pairs = URI.decode_www_form(request.query_string)
      form = request.get_header('rack.request.form_vars')
      pairs.concat(URI.decode_www_form(form)) if form
      selected = pairs.select { |name, _| name.match?(/\Aswitch_user(?:\[|\z)/) }
      return false if selected.empty? && !parameters.has_key?('switch_user')

      unless @switch_user && selected == [%w[switch_user 1]] && parameters['switch_user'] == '1' &&
             [nil, 'application/x-www-form-urlencoded'].include?(request.media_type)
        handler.halt(403, 'Invalid documentation switch request')
      end

      true
    rescue ArgumentError
      handler.halt(403, 'Invalid documentation switch request')
    end

    def nonce?(value)
      value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{32,128}\z/)
    end

    def token?(value)
      value.is_a?(String) && value.bytesize.between?(1, 4096) && value.match?(/\A[\x21-\x7e]+\z/)
    end

    def secure_equal?(left, right)
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def write_cookie(handler, kind, payload)
      expiry = Time.at(payload.fetch('expires'))
      encrypted = @encryptor.encrypt_and_sign(payload, purpose: @purposes.fetch(kind), expires_at: expiry)
      attributes = { value: encrypted, path: @path, secure: true, httponly: true, same_site: :lax, expires: expiry }
      if Rack::Utils.set_cookie_header(@names.fetch(kind), attributes).bytesize > COOKIE_LIMIT
        raise Failure, 'Documentation sign-in failed'
      end

      handler.response.set_cookie(@names.fetch(kind), attributes)
    end

    def read_cookie(handler, kind)
      raw = handler.request.cookies[@names.fetch(kind)]
      return unless raw
      raise Failure, 'Invalid documentation session' unless raw.bytesize <= COOKIE_LIMIT

      payload = @encryptor.decrypt_and_verify(raw, purpose: @purposes.fetch(kind))
      expected = kind == 'pending' ? %w[state verifier return expires] : %w[token expires csrf]
      unless payload.is_a?(Hash) && payload.keys.sort == expected.sort &&
             payload['expires'].is_a?(Numeric) && payload['expires'].finite? && payload['expires'] > Time.now.to_f
        raise Failure, 'Invalid documentation session'
      end

      valid = if kind == 'pending'
                nonce?(payload['state']) && nonce?(payload['verifier']) && return_location(payload['return'])
              else
                token?(payload['token']) && nonce?(payload['csrf'])
              end
      raise Failure, 'Invalid documentation session' unless valid

      payload
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, Failure, ArgumentError, TypeError
      clear_cookie(handler, kind)
      handler.instance_variable_set(:@documentation_oauth_message, 'Your documentation session ended. Sign in again.') if kind == 'session'
      nil
    end

    def clear_cookie(handler, kind)
      handler.response.set_cookie(@names.fetch(kind), value: '', path: @path, secure: true,
                                                      httponly: true, same_site: :lax, expires: Time.at(0), max_age: 0)
    end

    def failure_page(handler)
      protect_response(handler)
      link = "#{@origin}#{@routes.fetch('login')}"
      handler.halt(400, { 'content-type' => 'text/html; charset=utf-8' },
                   "<p>Documentation sign-in failed. <a href=\"#{CGI.escapeHTML(link)}\">Try again</a>.</p>")
    end
  end
end

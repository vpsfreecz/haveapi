require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'time'
require 'timeout'
require 'uri'
require_relative 'artifacts'

module HaveAPI
  module Release
    # Read-only registry observation. Package validation stays with Publisher.
    class RegistryQuery
      Response = Struct.new(:status, :data, :headers)
      TRANSIENT_STATUSES = [408, 429, 500, 502, 503, 504].freeze
      HEADER_NAMES = %w[Age Date Cache-Control X-Cache Retry-After].freeze
      BACKOFF = [2, 4, 8, 15, 30].freeze
      ENDPOINTS = {
        'rubygems.org' => %r{\A/api/v2/rubygems/(?:haveapi|haveapi-client|haveapi-go-client|haveapi-rust-client)/versions/\d+\.\d+\.\d+[A-Za-z0-9._-]*\.json\z},
        'pypi.org' => %r{\A/pypi/haveapi-client/\d+\.\d+\.\d+[A-Za-z0-9._-]*/json\z},
        'registry.npmjs.org' => %r{\A/haveapi-client/\d+\.\d+\.\d+[A-Za-z0-9._-]*\z}
      }.freeze

      class Transient < StandardError
        attr_reader :response

        def initialize(response = nil)
          @response = response
          super('temporary registry read failure')
        end
      end

      class ReadError < Error
        attr_reader :response

        def initialize(message, response = nil)
          @response = response
          super(message)
        end
      end

      class Unconfirmed < Error; end

      def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     wall_clock: -> { Time.now }, sleeper: ->(seconds) { sleep(seconds) },
                     transport: nil, logger: ->(line) { warn(line) })
        @clock = clock
        @wall_clock = wall_clock
        @sleeper = sleeper
        @transport = transport || method(:http_get)
        @logger = logger
      end

      def deadline(seconds)
        @clock.call + seconds
      end

      # A preflight returns validated missing/partial metadata after one pair.
      # Confirmation repeats only GETs; callers never put uploads in this block.
      def observe(url, phase:, package:, version:, complete:, missing: ->(_value) { [] },
                  wait: false, deadline: nil, uploaded: false, later: [], &validate)
        validate_url(url)
        started = @clock.call
        expires = deadline || self.deadline(wait ? 600 : 60)
        attempt = 0
        round = 0
        loop do
          retry_response = nil
          begin
            [url, nil].each do |endpoint|
              endpoint ||= "#{url}?haveapi_confirmation=#{SecureRandom.hex(16)}"
              unconfirmed!(phase, package, version, started, uploaded, later) if @clock.call >= expires
              attempt += 1
              response = read(endpoint, deadline: expires)
              begin
                value = validate.call(response.data)
              rescue Error, KeyError, TypeError, NoMethodError
                log(phase, package, version, attempt, started, response, [])
                raise
              end
              log(phase, package, version, attempt, started, response, missing.call(value))
              return value if complete.call(value)
              next if endpoint == url

              return value unless wait
            end
          rescue Transient => e
            retry_response = e.response
            log(phase, package, version, attempt, started, retry_response, [], temporary: true)
          rescue ReadError => e
            log(phase, package, version, attempt, started, e.response, [])
            raise Error, "Registry #{phase}: #{package} #{version}: #{e.message}"
          end
          delay = [BACKOFF.fetch([round, BACKOFF.length - 1].min), retry_after(retry_response) || 0].max
          remaining = expires - @clock.call
          if remaining <= 0 || delay >= remaining
            unconfirmed!(phase, package, version, started, uploaded, later)
          end
          @sleeper.call(delay)
          round += 1
        end
      end

      def read(url, deadline:)
        uri = validate_url(url, fresh: true)
        remaining = deadline - @clock.call
        raise Transient if remaining <= 0

        status, body, headers = @transport.call(uri, remaining)
        raise Transient if @clock.call >= deadline

        headers = diagnostic_headers(headers)
        response = Response.new(status: Integer(status), data: nil, headers:)
        raise Transient, response if TRANSIENT_STATUSES.include?(response.status)
        return response if response.status == 404

        unless response.status == 200
          raise ReadError.new("Registry metadata request failed (HTTP #{response.status}); redirects are not followed", response)
        end

        response.data = JSON.parse(body)
        raise ReadError.new('Registry returned malformed successful metadata', response) unless response.data.is_a?(Hash)

        response
      rescue JSON::ParserError, TypeError, ArgumentError
        raise ReadError.new('Registry returned malformed successful metadata', response)
      rescue OpenSSL::SSL::SSLError
        raise ReadError, 'Registry HTTPS validation failed'
      rescue Timeout::Error, EOFError, Errno::ECONNRESET, Errno::ECONNABORTED,
             Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
        raise Transient
      rescue SocketError => e
        raise Transient if e.message.match?(/temporary failure|try again|EAI_AGAIN/i)

        raise ReadError, 'Registry hostname lookup failed'
      end

      private

      def validate_url(url, fresh: false)
        uri = URI(url)
        pattern = ENDPOINTS[uri.host]
        query_allowed = uri.query.nil? || (fresh && uri.query.match?(/\Ahaveapi_confirmation=[0-9a-f]{32}\z/))
        unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil? &&
               pattern && pattern.match?(uri.path) && query_allowed
          raise Error, 'Refusing an unsupported registry metadata URL'
        end

        uri
      rescue URI::InvalidURIError, TypeError
        raise Error, 'Refusing an unsupported registry metadata URL'
      end

      def http_get(uri, remaining)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = [15, remaining].min
        http.read_timeout = [30, remaining].min
        http.write_timeout = [30, remaining].min
        Timeout.timeout(remaining) do
          http.start do
            request = Net::HTTP::Get.new(uri.request_uri)
            request['Accept'] = 'application/json'
            request['Cache-Control'] = 'no-cache'
            response = http.request(request)
            [response.code.to_i, response.body, response.to_hash.transform_values(&:first)]
          end
        end
      end

      def diagnostic_headers(headers)
        HEADER_NAMES.each_with_object({}) do |name, result|
          pair = headers.find { |key, _value| key.to_s.casecmp?(name) }
          next unless pair

          result[name] = pair.last.to_s.gsub(/[^\x20-\x7e]/, '?')
                             .gsub(%r{https?://\S+}, '[URL omitted]').slice(0, 200)
        end
      end

      def retry_after(response)
        return unless response && [429, 503].include?(response.status)

        value = response.headers['Retry-After']
        return unless value
        return value.to_i if value.match?(/\A\d+\z/)

        [Time.httpdate(value) - @wall_clock.call, 0].max
      rescue ArgumentError
        nil
      end

      def log(phase, package, version, attempt, started, response, missing, temporary: false)
        outcome = response ? "HTTP #{response.status}" : 'temporary transport failure'
        details = response ? response.headers.map { |key, value| "#{key}=#{value.inspect}" }.join(' ') : ''
        @logger.call("Registry #{phase}: #{package} #{version} attempt=#{attempt} " \
                     "elapsed=#{format('%.2f', @clock.call - started)}s #{outcome} " \
                     "temporary=#{temporary} missing=#{missing.join(',')} #{details}".rstrip)
      end

      def unconfirmed!(phase, package, version, started, uploaded, later)
        state = uploaded ? 'upload succeeded but public confirmation is pending' : 'public metadata remains unconfirmed'
        raise Unconfirmed, "Registry #{phase} timed out for #{package} #{version} after #{format('%.2f', @clock.call - started)}s; " \
                           "#{state}; later destinations not attempted: #{later.join(', ')}. " \
                           'Retain the tag/run and original manifest; verify accepted uploads before an explicit recovery run.'
      end
    end
  end
end

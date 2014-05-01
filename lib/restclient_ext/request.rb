module RestClient
  class Request
    def self.execute_options(args, &block)
      new(args).execute_options(&block)
    end

    def execute_options(&block)
      uri = parse_url_with_auth(url)
      http_request = Net::HTTPGenericRequest.new(method.to_s.upcase, false, true, uri.request_uri, processed_headers)

      transmit uri, http_request, payload, & block
    ensure
      payload.close if payload
    end
  end
end

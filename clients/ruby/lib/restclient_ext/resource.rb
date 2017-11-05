module RestClient
  class Resource
    def get_options(additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
        :method => :options,
        :url => url,
        :headers => headers
      ), &(block || @block))
    end
  end
end

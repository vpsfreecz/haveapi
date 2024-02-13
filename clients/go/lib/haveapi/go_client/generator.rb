require 'fileutils'
require 'haveapi/client'

module HaveAPI::GoClient
  class Generator
    # Destination directory
    # @return [String]
    attr_reader :dst

    # Go module name
    # @return [String]
    attr_reader :module

    # Go package name
    # @return [String]
    attr_reader :package

    # @param url [String] API URL
    # @param dst [String] destination directory
    # @param opts [Hash]
    # @option opts [String] :version
    # @option opts [String] :module
    # @option opts [String] :package
    def initialize(url, dst, opts)
      @dst = dst
      @module = opts[:module]
      @package = opts[:package]

      conn = HaveAPI::Client::Communicator.new(url)
      @api = ApiVersion.new(conn.describe_api(opts[:version]))
    end

    def generate
      FileUtils.mkpath(dst)

      if self.module
        ErbTemplate.render_to_if_changed(
          'go.mod',
          { mod: self.module },
          File.join(dst, 'go.mod')
        )

        @dst = File.join(dst, package)
        FileUtils.mkpath(dst)
      end

      %w[client authentication request response types].each do |v|
        ErbTemplate.render_to_if_changed(
          "#{v}.go",
          {
            package:,
            api:
          },
          File.join(dst, "#{v}.go")
        )
      end

      api.resources.each { |r| r.generate(self) }
      api.auth_methods.each { |v| v.generate(self) }
    end

    def go_fmt
      return if system('go', 'fmt', chdir: dst)

      raise 'go fmt failed'
    end

    protected

    attr_reader :api
  end
end

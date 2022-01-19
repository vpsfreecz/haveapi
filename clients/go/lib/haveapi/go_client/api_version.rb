module HaveAPI::GoClient
  class ApiVersion
    # @return [Array<Authentication::Base>]
    attr_reader :auth_methods

    # @return [String]
    attr_reader :metadata_namespace

    # @return [Array<Resource>]
    attr_reader :resources

    def initialize(desc)
      @resources = desc[:resources].map do |k, v|
        Resource.new(self, k, v)
      end.sort!

      @resources.each { |r| r.resolve_associations }

      @auth_methods = desc[:authentication].map do |k, v|
        AuthenticationMethods.new(self, k, v)
      end

      @metadata_namespace = desc[:meta][:namespace]
    end
  end
end

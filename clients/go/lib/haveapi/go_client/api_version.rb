module HaveAPI::GoClient
  class ApiVersion
    attr_reader :auth_methods, :resources

    def initialize(desc)
      @resources = desc[:resources].map { |k, v| Resource.new(self, k, v) }
      @resources.each { |r| r.resolve_associations }
      @auth_methods = desc[:authentication].map do |k, v|
        AuthenticationMethods.new(k, v)
      end
    end
  end
end

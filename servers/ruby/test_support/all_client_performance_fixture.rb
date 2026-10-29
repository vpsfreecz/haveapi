require_relative 'documentation_performance_fixture'

module HaveAPI
  # Scalar samples deliberately stay inside every generator's supported subset.
  # The historical timing fixture and its calibrated workloads stay separate.
  module AllClientPerformanceFixture
    class TokenConfig < Authentication::Token::Config
      # Keep the saved JSON SDK description and live provider value identical.
      query_parameter '_auth_token'
    end

    def self.build(resources:, actions: 2)
      definitions = Module.new
      resources.times do |index|
        resource = Class.new(HaveAPI::Resource)
        definitions.const_set("Resource#{index}", resource)
        resource.resource_name = "Resource#{index}"
        resource.version 1
        resource.route "resources#{index}"
        names = %w[Public Protected] + (2...actions).map { |i| "Action#{i}" }
        names.each { |name| add_action(resource, name) }
        DocumentationPerformanceFixture.send(:add_admin_action, resource) if index == 0
      end
      server = HaveAPI::Server.new(definitions)
      server.use_version(1)
      server.default_version = 1
      server.auth_chain << DocumentationPerformanceFixture::BasicProvider
      server.auth_chain << Authentication::Token.with_config(TokenConfig)
      fixture = DocumentationPerformanceFixture.configure_documentation_oauth(server)
      server.documentation_clients(1,
                                   go: { import_path: 'example.test/performance/client' },
                                   rust: { crate_name: 'performance_client' },
                                   typescript: { package_name: 'performance-client' })
      server.mount('/benchmark/api/')
      DocumentationPerformanceFixture.attach_documentation_headers(server, fixture)
      server
    end

    def self.add_action(resource, name)
      resource.define_action(name) do
        route name.downcase
        http_method :post
        auth name != 'Public'
        input(:hash) do
          string :value
          bool :enabled
          integer :count
          string :admin_field, default: 'ADMIN_ONLY_DEFAULT'
        end
        output(:hash) do
          string :marker
          string :admin_field
        end
        authorize do |user|
          if user && user.login != 'admin'
            input blacklist: [:admin_field]
            output blacklist: [:admin_field]
          end
          allow
        end
        example 'Success' do
          request(value: '', enabled: false, count: 0)
          response(marker: 'PUBLIC_SAMPLE')
        end
        example 'Failure' do
          request(value: '', enabled: false, count: 0)
          status false
          message 'Expected failure'
          errors(value: ['fixture error'])
        end
        example 'Admin' do
          authorize { |user| user.login == 'admin' }
          request(admin_field: 'ADMIN_ONLY_REQUEST')
          response(admin_field: 'ADMIN_ONLY_RESPONSE')
        end
      end
    end
    private_class_method :add_action
  end
end

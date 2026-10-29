require 'haveapi'

module HaveAPI
  # Shared by deterministic specs and the opt-in documentation benchmark.
  module DocumentationPerformanceFixture
    User = Struct.new(:login)

    class BasicProvider < HaveAPI::Authentication::Basic::Provider
      protected

      def find_user(_request, username, password)
        User.new(username) if %w[admin member].include?(username) && password == 'fixture-only'
      end
    end

    def self.build(resource_count: 4, actions_per_resource: 2, samples_per_action: 1,
                   parameters_per_action: 2, rust: false, documentation_oauth: false)
      dimensions = [resource_count, actions_per_resource, samples_per_action, parameters_per_action]
      unless dimensions.all? { |value| value.is_a?(Integer) && value > 0 }
        raise ArgumentError, 'Fixture dimensions must be positive integers'
      end

      resources = Module.new
      resource_count.times do |index|
        resource = Class.new(HaveAPI::Resource)
        resources.const_set("Resource#{index}", resource)
        resource.resource_name = "Resource#{index}"
        resource.version 1
        resource.route "resources#{index}"
        resource.desc "Synthetic resource #{index}"
        actions_per_resource.times do |action_index|
          add_action(resource, action_index, samples_per_action, parameters_per_action)
        end
        add_admin_action(resource) if index == 0
      end

      server = HaveAPI::Server.new(resources)
      server.use_version(1)
      server.default_version = 1
      server.auth_chain << BasicProvider
      if rust
        server.documentation_clients(1, rust: { crate_name: 'documentation_performance_client' })
      end
      fixture = configure_documentation_oauth(server) if documentation_oauth
      server.mount('/benchmark/api/')
      attach_documentation_headers(server, fixture) if fixture
      server
    end

    def self.configure_documentation_oauth(server)
      require_relative 'documentation_oauth_fixture'
      users = %w[admin member].to_h { |role| ["documentation-#{role}", User.new(role)] }
      DocumentationOAuthFixture.configure(server, users: { 1 => users }, origin: 'https://example.test', mount_path: '/benchmark/api/')
    end

    def self.attach_documentation_headers(server, fixture)
      # Mint once during setup. Each page still decrypts and validates the real
      # token; deterministic per-role CSRF preserves repeated HTML body proof.
      cookies = %w[admin member].to_h do |role|
        [role, fixture.header_for(server, version: 1, token: "documentation-#{role}")]
      end
      server.define_singleton_method(:fixture_documentation_oauth) { fixture }
      server.define_singleton_method(:fixture_documentation_cookie) { |role| cookies.fetch(role) }
    end

    def self.add_action(resource, index, samples, parameters)
      resource.define_action("Action#{index}") do
        route "actions#{index}"
        http_method :post
        auth true
        desc "Synthetic action #{index}"
        input(:hash) do
          parameters.times { |i| string :"value#{i}" }
          custom :payload
          bool :enabled
          integer :count
          string :nullable, nullable: true
          string :admin_field, default: 'ADMIN_ONLY_DEFAULT'
        end
        output(:hash) do
          string :marker
          custom :payload
          string :admin_field
        end
        authorize do |user|
          if user && user.login != 'admin'
            input blacklist: [:admin_field]
            output blacklist: [:admin_field]
          end
          allow
        end

        samples.times do |sample_index|
          example "Public sample #{sample_index}" do
            request({ value0: '', enabled: false, count: 0, nullable: nil,
                      payload: { 'nested' => [{ 'values' => [0, false, '', nil] }] } })
            response({ marker: "PUBLIC_SAMPLE_#{sample_index}", payload: { 'items' => [false, 0, nil, ''] } })
          end
        end
        example 'Admin sample' do
          authorize { |user| user.login == 'admin' }
          request({ admin_field: 'ADMIN_ONLY_REQUEST' })
          response({ admin_field: 'ADMIN_ONLY_RESPONSE' })
        end
      end
    end
    private_class_method :add_action

    def self.add_admin_action(resource)
      resource.define_action(:AdminOnly) do
        route 'admin-only'
        http_method :get
        auth true
        desc 'ADMIN_ONLY_ACTION'
        output(:hash) { string :admin_result }
        authorize { |user| user && user.login == 'admin' ? allow : deny }
        example 'Admin action sample' do
          response({ admin_result: 'ADMIN_ONLY_ACTION_SAMPLE' })
        end
      end
    end
    private_class_method :add_admin_action
  end
end

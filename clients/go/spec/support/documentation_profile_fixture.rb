# Real mounted DSL for the pure documentation-profile check; no action is run.
module GoDocumentationProfileFixture
  HOSTILE = "quote\"\\\n雪</script>".freeze

  module Resources
    class Owner < HaveAPI::Resource
      version '7'
      auth false

      define_action(:Index) do
        authorize { allow }
        output(:hash_list) do
          integer :id
          string :label
        end
      end

      define_action(:Show) do
        route '{owner_id}'
        authorize { allow }
        output(:hash) do
          integer :id
          string :label
        end
      end
    end

    class SetTimeout < HaveAPI::Resource
      version '7'
      auth false

      define_action(:Secret) do
        authorize { |user| user == :privileged ? allow : deny }
        output(:hash) { string :private_value }
      end
    end

    class SetTimeoutResource < HaveAPI::Resource
      version '7'
      route 'parents'
      auth false

      define_resource(:Child) do
        route '{parent_id}/children'
        auth false
        define_action(:Client) do
          route '{child_id}'
          http_method :post
          aliases ['perform']
          authorize do |user|
            input blacklist: [:private_value] unless user == :privileged
            output blacklist: [:private_value] unless user == :privileged
            allow
          end

          input(:hash) do
            string :name, nullable: true
            bool :enabled
            integer :count
            string :private_value, default: 'private default'
            string :unused
          end
          output(:hash) do
            integer :id
            string :private_value
            resource Owner, name: :owner, nullable: true
          end
          meta(:global) do
            input { custom :includes }
          end

          example 'filtered sample' do # rubocop:disable RSpec/NoExpectationExample -- HaveAPI sample DSL.
            path_params 'parent/with space', 0
            request name: HOSTILE, enabled: false, count: 0, private_value: 'private sample'
            response id: 0, private_value: 'private result', owner: { id: 9 }
          end

          def exec
            raise 'Documentation must not execute an action'
          end
        end
      end

      define_action(:Update) do
        self.action_name = 'child'
        route 'update'
        aliases ['perform']
        authorize { allow }
        input(:hash) { string :name, nullable: true }
        output(:hash) { integer :id }

        example 'nullable sample' do # rubocop:disable RSpec/NoExpectationExample -- HaveAPI sample DSL.
          request name: nil
          response id: 0
        end
      end
    end
  end

  def self.server(**go)
    server = HaveAPI::Server.new(Resources)
    server.use_version('7')
    server.default_version = '7'
    server.documentation_clients('7', go: { import_path: 'example.test/current-sdk/client', **go })
    server.mount('/mounted/')
    server
  end

  def self.description(server, user: nil)
    server.describe_version(HaveAPI::Context.new(server, version: '7', user:, endpoint: false, doc: true))
  end

  def self.context(description, path: %w[set_timeout_resource child], action_name: 'client', sample: nil)
    resource = path.inject(description) { |parent, name| parent.fetch(:resources).fetch(name) }
    action = resource.fetch(:actions).fetch(action_name)
    HaveAPI::ClientExample::Context.new(
      version: '7', host: 'api.example.test', base_url: 'https://api.example.test/mounted/',
      version_url: 'https://api.example.test/mounted/v7/', description:, resource_path: path,
      resource:, action_name:, action:, sample: sample || action.fetch(:examples).first
    )
  end
end

require 'haveapi'
require 'active_record'
require 'sqlite3'
require 'haveapi/model_adapters/active_record'
require 'rack/mock'
require 'base64'
require 'digest'
require 'json'
require_relative '../benchmarks/performance_compare'

module HaveAPI
  module PerformanceFixtures
    # Neutral Rack scenarios; database setup and validation stay outside timing.
    module SQLite
      User = Struct.new(:login)

      class BasicProvider < HaveAPI::Authentication::Basic::Provider
        protected

        def find_user(_request, username, password)
          User.new(username) if %w[admin member].include?(username) && password == 'fixture-only'
        end
      end

      def self.cases(profile: 'quick')
        case profile
        when 'quick'
          [{ id: 'sqlite.page', dimensions: { rows: 128, page_size: 32 } },
           { id: 'sqlite.includes', dimensions: { rows: 32, include_depth: 2 } }]
        when 'weekly'
          cases + [{ id: 'sqlite.page', dimensions: { rows: 10_000, page_size: 32 } }] +
            [32, 128, 1024].product(%w[admin member]).map do |rows, user|
              { id: 'sqlite.includes', dimensions: { rows:, include_depth: 2, user: } }
            end
        else raise ArgumentError, 'Unknown SQLite performance profile'
        end
      end

      def self.build(case_spec)
        Scenario.new(case_spec)
      end

      def self.database_namespace
        @database_sequence = (@database_sequence || 0) + 1
        const_set("Database#{@database_sequence}", Module.new)
      end

      class Scenario
        attr_reader :case_spec

        def initialize(case_spec)
          @case_spec = case_spec.transform_keys(&:to_sym)
          @dimensions = @case_spec.fetch(:dimensions).transform_keys(&:to_sym)
          @rows = @dimensions.fetch(:rows)
          @user = @dimensions.fetch(:user, 'admin')
          @depth = @dimensions.fetch(:include_depth, 0)
          validate_case!
          @namespace = SQLite.database_namespace
          build_database
          build_api
          @request = Rack::MockRequest.new(@server.app)
          @path = request_path
          @headers = { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT' => 'application/json',
                       'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@user}:fixture-only")}" }
          @subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
            record_query(args.last)
          end
          reset!(iterations: 1)
        rescue StandardError
          close
          raise
        end

        def reset!(iterations:)
          raise ArgumentError, 'Iterations must be positive' unless iterations.is_a?(Integer) && iterations > 0
          raise 'SQLite scenario is closed' if @closed

          @operations = Array.new(iterations) { { queries: 0, authorizations: 0, executions: 0 } }
          @index = 0
          @active_operation = nil
          self
        end

        def call
          raise 'SQLite scenario is closed' if @closed
          raise 'SQLite scenario called beyond reset iterations' if @index >= @operations.length

          @active_operation = @operations.fetch(@index)
          @index += 1
          @base.uncached { @request.get(@path, @headers) }
        ensure
          @active_operation = nil
        end

        def validate!(response, index:)
          unless index.is_a?(Integer) && index >= 0 && index < @index
            raise ArgumentError, 'Invalid or uncalled SQLite operation index'
          end

          identity = HaveAPI::Performance::Identity.json(response)
          body = identity.fetch(:canonical_body)
          unless response.status == 200 && body['status'] == true && body['message'].nil? && body['errors'].nil? &&
                 body.keys.sort == %w[errors message response status] && response['content-type']&.start_with?('application/json')
            raise 'Unexpected SQLite HTTP/envelope status'
          end
          raise 'Unexpected SQLite response rows or values' unless body['response'] == expected_response
          raise 'Unexpected SQLite operation counters' unless @operations.fetch(index) == expected_counters

          identity
        end

        def counters
          raise 'SQLite operation records are incomplete' unless @index == @operations.length

          unless @operations.all? { |operation| operation == expected_counters }
            raise 'Unexpected SQLite operation counters'
          end

          { operations: @operations.map(&:dup) }
        end

        def close
          return if @closed

          ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
          @base.remove_connection if @base
          if @namespace
            name = @namespace.name.split('::').last
            SQLite.send(:remove_const, name) if SQLite.const_defined?(name, false) && SQLite.const_get(name).equal?(@namespace)
          end
          @closed = true
        end

        def authorize_record
          @active_operation[:authorizations] += 1 if @active_operation
        end

        def execute_record
          @active_operation[:executions] += 1 if @active_operation
        end

        private

        def validate_case!
          unless %w[sqlite.page sqlite.includes].include?(@case_spec.fetch(:id)) &&
                 @rows.is_a?(Integer) && @rows > 0 && %w[admin member].include?(@user)
            raise ArgumentError, 'Invalid SQLite case'
          end

          allowed = @case_spec[:id] == 'sqlite.page' ? %i[rows page_size user] : %i[rows include_depth user]
          raise ArgumentError, 'Unknown SQLite dimensions' unless (@dimensions.keys - allowed).empty?

          if @case_spec[:id] == 'sqlite.page'
            unless @dimensions.fetch(:page_size) == 32 && @rows >= 32
              raise ArgumentError, 'SQLite pagination requires a fixed page of 32'
            end
          elsif ![1, 2].include?(@depth)
            raise ArgumentError, 'SQLite include depth must be 1 or 2'
          end
        end

        def build_database
          @base = @namespace.const_set(:Base, Class.new(ActiveRecord::Base))
          @base.abstract_class = true
          @base.establish_connection(adapter: 'sqlite3', database: ':memory:')
          connection = @base.connection
          connection.create_table(:performance_accounts) do |table|
            table.string :label
            table.string :secret
          end
          connection.create_table(:performance_groups) do |table|
            table.string :label
            table.string :secret
            table.integer :account_id
          end
          connection.create_table(:performance_items) do |table|
            table.string :label
            table.boolean :enabled
            table.integer :count
            table.string :note
            table.integer :group_id
          end
          @account = model(:Account, 'performance_accounts')
          @group = model(:Group, 'performance_groups')
          @item = model(:Item, 'performance_items')
          @group.belongs_to(:account, class_name: @account.name)
          @item.belongs_to(:group, class_name: @group.name)
          @account.insert_all!((1..@rows).map { |id| { id:, label: "account#{id}", secret: "ACCOUNT_SECRET_#{id}" } })
          @group.insert_all!((1..@rows).map { |id| { id:, label: "group#{id}", secret: "GROUP_SECRET_#{id}", account_id: id } })
          @item.insert_all!((1..@rows).map { |id| { id:, label: '', enabled: false, count: 0, note: nil, group_id: id } })
        end

        def model(name, table)
          klass = @namespace.const_set(name, Class.new(@base))
          klass.table_name = table
          klass.columns
          klass
        end

        def build_api
          scenario = self
          depth = @depth
          resources = @namespace.const_set(:API, Module.new)
          account_resource = resource(resources, :Account, @account)
          account_resource.define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
            authorize do |user, params|
              scenario.authorize_record
              deny if user.login == 'member' && (params['account_id'].to_i % 3) == 0
              output blacklist: [:secret] if user.login == 'member'
              allow
            end
            output(:object) do
              integer :id
              string :label
              string :secret
            end
            define_method(:exec) do
              scenario.execute_record
              raise 'Associated Show must not execute'
            end
          end
          group_resource = resource(resources, :Group, @group)
          group_resource.define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
            authorize do |user, params|
              scenario.authorize_record
              deny if user.login == 'member' && params['group_id'].to_i.even?
              output blacklist: [:secret] if user.login == 'member'
              allow
            end
            output(:object) do
              integer :id
              string :label
              string :secret
              # The direct lane's selected output is scalar; it does not rely on
              # the adapter's known missing default preload for nested resources.
              resource account_resource if depth == 2
            end
            define_method(:exec) do
              scenario.execute_record
              raise 'Associated Show must not execute'
            end
          end
          item_resource = resource(resources, :Item, @item)
          add_index(item_resource, scenario)
          add_includes(item_resource, group_resource, scenario)
          @server = HaveAPI::Server.new(resources)
          @server.use_version(1)
          @server.default_version = 1
          @server.auth_chain << BasicProvider
          @server.mount('/performance/api/')
        end

        def resource(resources, name, model)
          klass = resources.const_set(name, Class.new(HaveAPI::Resource))
          klass.resource_name = name.to_s
          klass.version(1)
          klass.auth(true)
          klass.model(model)
          unless name == :Item
            klass.define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
              authorize { deny }
              output(:object_list) do
                integer :id
                string :label
              end
            end
          end
          klass
        end

        def add_index(resource, scenario)
          resource.define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
            authorize do
              scenario.authorize_record
              allow
            end
            output(:object_list) do
              integer :id
              string :label
              bool :enabled
              integer :count
              string :note, nullable: true
            end
            define_method(:exec) do
              scenario.execute_record
              with_pagination(self.class.model.order(id: :asc)).to_a
            end
          end
        end

        def add_includes(resource, group_resource, scenario)
          resource.define_action(:Included, superclass: HaveAPI::Actions::Default::Index) do
            route 'included'
            authorize do
              scenario.authorize_record
              allow
            end
            output(:object_list) do
              integer :id
              string :label
              resource group_resource
            end
            define_method(:exec) do
              scenario.execute_record
              with_includes(self.class.model.order(id: :asc)).to_a
            end
          end
        end

        def request_path
          query = if @case_spec[:id] == 'sqlite.page'
                    { item: { from_id: 0, limit: 32 } }
                  else
                    { _meta: { includes: @depth == 1 ? 'group' : 'group__account' } }
                  end
          route = @case_spec[:id] == 'sqlite.page' ? 'items' : 'items/included'
          "/performance/api/v1/#{route}?#{Rack::Utils.build_nested_query(query)}"
        end

        def record_query(payload)
          return unless @active_operation && payload[:connection]&.pool.equal?(@base.connection_pool)
          return if %w[SCHEMA TRANSACTION].include?(payload[:name])
          return unless payload[:sql].match?(/\A\s*(?:SELECT|INSERT|UPDATE|DELETE)\b/i)
          raise 'SQLite request unexpectedly used query cache' if payload[:cached]

          @active_operation[:queries] += 1
        end

        def expected_counters
          return { queries: 1, authorizations: 1, executions: 1 } if @case_spec[:id] == 'sqlite.page'

          nested = if @depth == 2
                     @user == 'admin' ? @rows : (@rows + 1) / 2
                   else
                     0
                   end
          { queries: @depth + 1, authorizations: 1 + @rows + nested, executions: 1 }
        end

        def expected_response
          length = @case_spec[:id] == 'sqlite.page' ? 32 : @rows
          items = (1..length).map do |id|
            value = if @case_spec[:id] == 'sqlite.page'
                      { 'id' => id, 'label' => '', 'enabled' => false, 'count' => 0, 'note' => nil }
                    else
                      { 'id' => id, 'label' => '', 'group' => expected_group(id) }
                    end
            value['_meta'] = { 'path_params' => [id], 'resolved' => true }
            value
          end
          { 'items' => items, '_meta' => {} }
        end

        def expected_group(id)
          denied = { '_meta' => { 'resolved' => false, 'authorized' => false } }
          return denied if @user == 'member' && id.even?

          result = { 'id' => id, 'label' => "group#{id}", '_meta' => { 'path_params' => [id], 'resolved' => true } }
          result['secret'] = "GROUP_SECRET_#{id}" if @user == 'admin'
          return result if @depth == 1

          result['account'] = if @user == 'member' && (id % 3) == 0
                                denied
                              else
                                account = { 'id' => id, 'label' => "account#{id}",
                                            '_meta' => { 'path_params' => [id], 'resolved' => @depth == 2 } }
                                account['secret'] = "ACCOUNT_SECRET_#{id}" if @user == 'admin' && @depth == 2
                                account
                              end
          result
        end
      end
    end
  end
end

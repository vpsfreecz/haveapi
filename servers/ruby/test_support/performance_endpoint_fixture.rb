require 'haveapi'
require 'rack/mock'
require 'json'
require_relative '../benchmarks/performance_compare'

module HaveAPI
  module PerformanceFixtures
    # This file must use the caller-selected HaveAPI, including in baseline workers.
    module Endpoints
      User = Struct.new(:login)
      PASSWORD = 'performance-fixture-only'.freeze
      CASE_IDS = %w[api.public_get api.basic_get api.token_get api.typed_post api.invalid_post api.nested_get api.list].freeze

      def self.cases(profile: 'quick')
        raise ArgumentError, "Unknown profile: #{profile}" unless %w[quick weekly].include?(profile)

        quick = CASE_IDS.map { |id| { id:, dimensions: id == 'api.list' ? { rows: 32 } : {} } }
        return quick if profile == 'quick'

        quick + [
          { id: 'api.list', dimensions: { rows: 1024, user: 'member' } },
          { id: 'api.list', dimensions: { rows: 1024, user: 'admin' } },
          { id: 'api.basic_get', dimensions: { user: 'admin' } }
        ]
      end

      def self.build(case_spec)
        Scenario.new(case_spec)
      end

      class State
        attr_reader :items, :operations
        attr_accessor :operation

        def reset!(rows:, iterations:)
          @items = Array.new(rows) { |index| record(index + 1) }
          @operations = Array.new(iterations) { { queries: 0, authorizations: 0, executions: 0 } }
          @operation = nil
        end

        def record(id)
          { id:, label: "item-#{id}", enabled: false, count: 0, nullable: nil,
            payload: { 'nested' => [0, false, '', nil] }, secret: 'ADMIN_ONLY_VALUE' }
        end

        def increment(kind)
          @operations.fetch(@operation)[kind] += 1 unless @operation.nil?
        end
      end

      class Scenario
        attr_reader :app

        def initialize(case_spec)
          @id = case_spec.fetch(:id)
          @dimensions = case_spec.fetch(:dimensions)
          raise ArgumentError, "Unknown endpoint case: #{@id}" unless CASE_IDS.include?(@id)
          raise ArgumentError, 'Unknown endpoint dimension' unless (@dimensions.keys - %i[rows user]).empty?

          @rows = @dimensions.fetch(:rows, 1)
          @user = @dimensions.fetch(:user, 'member')
          raise ArgumentError, 'rows must be a positive integer' unless @rows.is_a?(Integer) && @rows > 0
          raise ArgumentError, 'Unknown user' unless %w[member admin].include?(@user)

          @state = State.new
          @state.reset!(rows: @rows, iterations: 0)
          @app = build_server.app
          @request = Rack::MockRequest.new(@app)
          @method, @path, @options = request_arguments
          @closed = false
        end

        def reset!(iterations:)
          raise 'Scenario is closed' if @closed
          unless iterations.is_a?(Integer) && iterations > 0
            raise ArgumentError, 'iterations must be a positive integer'
          end

          @state.reset!(rows: @rows, iterations:)
          @next_operation = 0
          self
        end

        def call
          raise 'Scenario is closed' if @closed
          raise 'reset! must precede call' if @next_operation.nil?
          raise 'More calls than reset iterations' if @next_operation >= @state.operations.length

          @state.operation = @next_operation
          @next_operation += 1
          @request.request(@method, @path, @options)
        ensure
          @state.operation = nil
        end

        def validate!(response, index:)
          raise ArgumentError, 'Invalid operation index' unless index.is_a?(Integer) && index >= 0
          raise 'Operation was not called' if @next_operation.nil? || index >= @next_operation
          raise 'Unexpected HTTP status' unless response.status == 200
          raise 'Unexpected content type' unless response['content-type']&.start_with?('application/json')

          validate_counts!(@state.operations.fetch(index))
          # Only the owning measurement may reuse body-only work. Index,
          # response metadata and execution/authorization checks always run.
          return yield(-> { validate_body!(response) }) if block_given?

          validate_body!(response)
        end

        def validate_body!(response)
          identity = HaveAPI::Performance::Identity.json(response)
          body = identity.fetch(:canonical_body)
          unless body.keys.sort == %w[errors message response status]
            raise 'Unexpected envelope shape'
          end

          valid = @id != 'api.invalid_post'
          raise 'Unexpected envelope status' unless body.fetch('status') == valid

          if valid
            expected = expected_response
            raise "Unexpected output for #{@id}: #{body.inspect}" unless body.fetch('response') == expected
            raise 'Unexpected success errors' unless body['errors'].nil? && body['message'].nil?
          else
            raise 'Invalid request unexpectedly returned data' unless body.fetch('response').nil?
            unless body.fetch('errors').keys == ['count'] && body.fetch('errors').fetch('count').any? &&
                   body.fetch('message').is_a?(String) && !body.fetch('message').empty?
              raise 'Missing typed validation errors'
            end
          end

          identity
        end

        def counters
          unless @next_operation && @next_operation == @state.operations.length
            raise 'Missing operation counter records'
          end

          @state.operations.each { |operation| validate_counts!(operation) }
          { operations: @state.operations }
        end

        def close
          @closed = true
          @state.operation = nil
        end

        private

        def validate_counts!(counts)
          expected = { queries: 0, authorizations: 1, executions: @id == 'api.invalid_post' ? 0 : 1 }
          raise "Unexpected operation counts: #{counts.inspect}" unless counts == expected
        end

        def request_arguments
          headers = { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT' => 'application/json' }
          unless @id == 'api.public_get'
            headers['HTTP_AUTHORIZATION'] = "Basic #{["#{@user}:#{PASSWORD}"].pack('m0')}"
          end
          case @id
          when 'api.public_get' then ['GET', '/performance/v1/probes/public', headers]
          when 'api.basic_get' then ['GET', '/performance/v1/probes/secure', headers]
          when 'api.token_get'
            headers.delete('HTTP_AUTHORIZATION')
            headers['HTTP_X_HAVEAPI_AUTH_TOKEN'] = "fixture-token-#{@user}"
            ['GET', '/performance/v1/probes/secure', headers]
          when 'api.typed_post', 'api.invalid_post'
            value = @id == 'api.invalid_post' ? 'not-an-integer' : '0'
            body = { probe: { count: value, ratio: '1.25', enabled: false, label: '', nullable: nil,
                              at: '2020-01-01T00:00:00Z', payload: { 'nested' => [0, false, '', nil] } } }
            ['POST', '/performance/v1/probes/typed', headers.merge('CONTENT_TYPE' => 'application/json',
                                                                   input: JSON.generate(body))]
          when 'api.nested_get' then ['GET', '/performance/v1/parents/7/children/9', headers]
          when 'api.list' then ['GET', '/performance/v1/items', headers]
          end
        end

        def expected_response
          value = case @id
                  when 'api.typed_post'
                    { 'count' => 0, 'ratio' => 1.25, 'enabled' => false, 'label' => '', 'nullable' => nil,
                      'at' => '2020-01-01T00:00:00+00:00', 'payload' => { 'nested' => [0, false, '', nil] } }
                  when 'api.nested_get' then { 'parent_id' => 7, 'child_id' => 9 }
                  when 'api.list' then Array.new(@rows) { |index| visible_record(index + 1) }
                  else visible_record(1)
                  end
          { 'probe' => value, '_meta' => {} }
        end

        def visible_record(id)
          value = @state.record(id).transform_keys(&:to_s)
          value.delete('secret') unless @user == 'admin' && @id != 'api.public_get'
          value
        end

        def build_server
          state = @state
          resources = Module.new
          probe = resources.const_set(:Probe, Class.new(HaveAPI::Resource))
          probe.resource_name = 'Probe'
          probe.version 1
          %i[Public Secure].each do |name|
            define_action(probe, name, state:, route: name == :Public ? 'public' : 'secure', auth: name != :Public) do
              output(:hash, namespace: :probe) { Endpoints.record_parameters(self) }
              define_method(:exec) do
                state.increment(:executions)
                state.record(1)
              end
            end
          end
          define_action(probe, :AdminOnly, state:, route: 'admin') do
            authorize do |user|
              state.increment(:authorizations)
              user && user.login == 'admin' ? allow : deny
            end
            output(:hash, namespace: :probe) { Endpoints.record_parameters(self) }
            define_method(:exec) do
              state.increment(:executions)
              state.record(1)
            end
          end
          define_action(probe, :Typed, state:, route: 'typed', method: :post) do
            input(:hash, namespace: :probe) { Endpoints.typed_parameters(self, required: true) }
            output(:hash, namespace: :probe) { Endpoints.typed_parameters(self) }
            define_method(:exec) do
              state.increment(:executions)
              input
            end
          end
          add_items(resources, state)
          parent = resources.const_set(:Parent, Class.new(HaveAPI::Resource))
          parent.resource_name = 'Parent'
          parent.version 1
          child = parent.define_resource(:Child) { route '{parent_id}/children' }
          define_action(child, :Show, state:, route: '{child_id}') do
            output(:hash, namespace: :probe) do
              integer :parent_id
              integer :child_id
            end
            define_method(:exec) do
              state.increment(:executions)
              { parent_id: Integer(path_params.fetch('parent_id')), child_id: Integer(path_params.fetch('child_id')) }
            end
          end
          server = HaveAPI::Server.new(resources)
          server.use_version(1)
          server.default_version = 1
          add_authentication(server)
          server.mount('/performance/')
          server
        end

        def define_action(resource, name, state:, route:, method: :get, auth: true, &block)
          resource.define_action(name) do
            route(route)
            http_method method
            auth(auth)
            authorize do |user|
              state.increment(:authorizations)
              output blacklist: [:secret] unless user && user.login == 'admin'
              allow
            end
            class_exec(&block)
          end
        end

        def add_items(resources, state)
          resource = resources.const_set(:Item, Class.new(HaveAPI::Resource))
          resource.resource_name = 'Item'
          resource.version 1
          define_action(resource, :Index, state:, route: '') do
            output(:hash_list, namespace: :probe) { Endpoints.record_parameters(self) }
            define_method(:exec) do
              state.increment(:executions)
              state.items
            end
          end
          define_action(resource, :Create, state:, route: '', method: :post) do
            input(:hash, namespace: :probe) { string :label, required: true }
            output(:hash, namespace: :probe) { Endpoints.record_parameters(self) }
            define_method(:exec) do
              state.increment(:executions)
              item = state.record((state.items.map { |row| row[:id] }.max || 0) + 1).merge(label: input[:label])
              state.items << item
              item
            end
          end
          %i[Show Update Delete].each do |name|
            method = { Show: :get, Update: :put, Delete: :delete }.fetch(name)
            define_action(resource, name, state:, route: '{item_id}', method:) do
              input(:hash, namespace: :probe) { string :label, required: true } if name == :Update
              output(:hash, namespace: :probe) { Endpoints.record_parameters(self) }
              define_method(:exec) do
                state.increment(:executions)
                item = state.items.find { |row| row[:id] == Integer(path_params.fetch('item_id')) }
                error!('Item not found', {}, http_status: 404) unless item
                item[:label] = input[:label] if name == :Update
                state.items.delete(item) if name == :Delete
                item
              end
            end
          end
        end

        def add_authentication(server)
          users = %w[member admin].to_h { |name| [name, User.new(name).freeze] }
          basic = Class.new(HaveAPI::Authentication::Basic::Provider) do
            define_method(:find_user) do |_request, username, password|
              users[username] if password == PASSWORD
            end
            protected :find_user
          end
          token = Class.new(HaveAPI::Authentication::Token::Config) do
            define_method(:find_user_by_token) do |_request, value|
              users.find { |name, _user| value == "fixture-token-#{name}" }&.last
            end
          end
          server.auth_chain << basic
          server.auth_chain << HaveAPI::Authentication::Token.with_config(token)
        end
      end

      def self.record_parameters(params)
        params.instance_eval do
          integer :id
          string :label
          bool :enabled
          integer :count
          string :nullable, nullable: true
          custom :payload
          string :secret
        end
      end

      def self.typed_parameters(params, required: false)
        params.instance_eval do
          integer :count, required: required
          float :ratio, required: required
          bool :enabled, required: required
          string :label
          string :nullable, nullable: true
          datetime :at, required: required
          custom :payload, required: required
          string :omitted
        end
      end
    end
  end
end

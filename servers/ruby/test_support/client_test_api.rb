# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../lib/haveapi'

module HaveAPI
  module ClientTestAPI
    FIXED_TIME = Time.utc(2020, 1, 1, 0, 0, 0)

    User = Struct.new(:id, :login, :role)

    USERS = {
      'user' => User.new(1, 'user', 'user'),
      'admin' => User.new(2, 'admin', 'admin')
    }.freeze

    class Model
      def self.marker?
        true
      end
    end

    module ::HaveAPI::ModelAdapters
      class ClientTestHash < ::HaveAPI::ModelAdapter
        register

        def self.handle?(_layout, klass)
          klass == HaveAPI::ClientTestAPI::Model
        end

        class Input < ::HaveAPI::ModelAdapter::Input
          def self.clean(_model, raw, _extra)
            raw
          end
        end

        class Output < ::HaveAPI::ModelAdapter::Output
          def self.used_by(action)
            action.meta(:object) do
              output do
                custom :path_params, label: 'URL parameters',
                                     desc: 'An array of parameters needed to resolve URL to this object'
                bool :resolved, label: 'Resolved', desc: 'True if the association is resolved'
              end
            end
          end

          def has_param?(name)
            @object.has_key?(name) || @object.has_key?(name.to_s)
          end

          def [](name)
            return @object[name] if @object.has_key?(name)

            @object[name.to_s]
          end

          def meta
            action = @context.action
            resource = action.resource

            params = if action.name.demodulize == 'Index' && !action.resolve && resource.const_defined?(:Show)
                       resource::Show.resolve_path_params(@object)
                     else
                       action.resolve_path_params(@object)
                     end

            {
              path_params: Array(params).compact,
              resolved: true
            }
          end
        end
      end
    end

    module Store
      class << self
        attr_reader :projects, :tasks

        def reset!
          @time_offset = 0
          @projects = [
            { id: 1, name: 'Alpha', created_at: FIXED_TIME },
            { id: 2, name: 'Beta', created_at: FIXED_TIME }
          ]
          @tasks = {
            1 => [
              { id: 1, project_id: 1, label: 'Initial task', done: false },
              { id: 2, project_id: 1, label: 'Second task', done: true }
            ],
            2 => []
          }
          @next_project_id = 3
          @next_task_id = 3
        end

        def list_projects
          @projects
        end

        def count_projects
          @projects.size
        end

        def find_project(id)
          @projects.find { |p| p[:id] == id.to_i }
        end

        def create_project(name)
          project = { id: @next_project_id, name: name, created_at: next_time }
          @next_project_id += 1
          @projects << project
          @tasks[project[:id]] ||= []
          project
        end

        def list_tasks(project_id)
          @tasks[project_id.to_i] || []
        end

        def find_task(project_id, task_id)
          list_tasks(project_id).find { |t| t[:id] == task_id.to_i }
        end

        def create_task(project_id, label, done)
          task = { id: @next_task_id, project_id: project_id.to_i, label: label, done: done }
          @next_task_id += 1
          (@tasks[project_id.to_i] ||= []) << task
          task
        end

        def update_task(project_id, task_id, done)
          task = find_task(project_id, task_id)
          return nil unless task

          task[:done] = done unless done.nil?
          task
        end

        private

        def next_time
          @time_offset += 1
          FIXED_TIME + @time_offset
        end
      end
    end

    module ActionStateBackend
      class State
        attr_reader :id, :label, :created_at, :updated_at, :status, :progress

        def initialize(id:, label:, total:, status: true, can_cancel: true, valid: true)
          @id = id
          @label = label
          @status = status
          @can_cancel = can_cancel
          @valid = valid
          @progress = { current: 0, total: total, unit: 'step' }
          @created_at = FIXED_TIME
          @updated_at = FIXED_TIME
          @finished = false
        end

        def valid?
          @valid
        end

        def finished?
          @finished
        end

        def can_cancel?
          @can_cancel
        end

        def poll(_input)
          return self if @finished

          @progress[:current] += 1
          if @progress[:current] >= @progress[:total]
            @progress[:current] = @progress[:total]
            @finished = true
          end

          @updated_at = Time.now.utc
          self
        end

        def cancel
          return false unless @can_cancel

          @finished = true
          @status = false
          @progress[:current] = @progress[:total]
          @updated_at = Time.now.utc
          true
        end
      end

      class << self
        def reset!
          @states = {}
          @next_id = 1
        end

        def create_state(label:, total: 3, can_cancel: true)
          id = @next_id
          @next_id += 1
          @states[id] = State.new(id: id, label: label, total: total, can_cancel: can_cancel)
          id
        end

        def list_pending(_user, _from_id, _limit, _order)
          (@states || {}).values.reject(&:finished?)
        end

        def new(_user, id:)
          state = (@states || {})[id.to_i]
          state || State.new(id: id.to_i, label: 'missing', total: 0, valid: false)
        end
      end
    end

    module DocFilter
      def describe(context)
        return false if auth && context.doc && context.current_user.nil?

        super
      end
    end

    class AuthFilteredResource < HaveAPI::Resource
      def self.define_resource(name, superclass: AuthFilteredResource, &block)
        super
      end

      def self.describe(hash, context)
        ret = super
        ret[:resources].delete_if do |_name, desc|
          desc[:actions].empty? && desc[:resources].empty?
        end
        ret
      end
    end

    module Resources
      def self.define_resource(name, superclass: AuthFilteredResource, &block)
        return false if const_defined?(name)

        cls = Class.new(superclass)
        const_set(name, cls)
        cls.resource_name = name
        cls.class_exec(&block) if block
        cls
      end

      define_resource(:Project) do
        desc 'Project resource'
        auth true
        model HaveAPI::ClientTestAPI::Model

        params(:all) do
          integer :id
          string :name
          datetime :created_at
        end

        define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
          extend DocFilter
          resolve { |obj| obj[:id] }
          output(:object_list) { use :all }
          authorize { allow }

          def exec
            HaveAPI::ClientTestAPI::Store.list_projects
          end

          def count
            HaveAPI::ClientTestAPI::Store.count_projects
          end
        end

        define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
          extend DocFilter
          resolve { |obj| obj[:id] }
          output(:object) { use :all }
          authorize { allow }

          def exec
            project = HaveAPI::ClientTestAPI::Store.find_project(params[:project_id])
            error!('project not found', {}, http_status: 404) unless project
            project
          end
        end

        define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
          extend DocFilter
          resolve { |obj| obj[:id] }
          input(:hash) do
            string :name, required: true
          end
          output(:object) { use :all }
          authorize { allow }

          def exec
            HaveAPI::ClientTestAPI::Store.create_project(input[:name])
          end
        end

        define_resource(:Task) do
          desc 'Task resource'
          auth true
          route '{project_id}/tasks'
          model HaveAPI::ClientTestAPI::Model

          params(:all) do
            integer :id
            string :label
            bool :done
          end

          define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
            extend DocFilter
            resolve { |obj| [obj[:project_id], obj[:id]] }
            output(:object_list) { use :all }
            authorize { allow }

            def exec
              HaveAPI::ClientTestAPI::Store.list_tasks(params[:project_id])
            end

            def count
              HaveAPI::ClientTestAPI::Store.list_tasks(params[:project_id]).size
            end
          end

          define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
            extend DocFilter
            resolve { |obj| [obj[:project_id], obj[:id]] }
            output(:object) { use :all }
            authorize { allow }

            def exec
              task = HaveAPI::ClientTestAPI::Store.find_task(params[:project_id], params[:task_id])
              error!('task not found', {}, http_status: 404) unless task
              task
            end
          end

          define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
            extend DocFilter
            resolve { |obj| [obj[:project_id], obj[:id]] }
            input(:hash) do
              string :label, required: true
              bool :done, default: false, fill: true
            end
            output(:object) { use :all }
            authorize { allow }

            def exec
              HaveAPI::ClientTestAPI::Store.create_task(
                params[:project_id],
                input[:label],
                input[:done]
              )
            end
          end

          define_action(:Update, superclass: HaveAPI::Actions::Default::Update) do
            extend DocFilter
            resolve { |obj| [obj[:project_id], obj[:id]] }
            input(:hash) do
              bool :done
            end
            output(:object) { use :all }
            authorize { allow }

            def exec
              task = HaveAPI::ClientTestAPI::Store.update_task(
                params[:project_id],
                params[:task_id],
                input[:done]
              )
              error!('task not found', {}, http_status: 404) unless task
              task
            end
          end

          define_action(:Run) do
            extend DocFilter
            route '{task_id}/run'
            http_method :post
            blocking true
            output(:hash) {}
            authorize { allow }

            def exec
              task = HaveAPI::ClientTestAPI::Store.find_task(params[:project_id], params[:task_id])
              error!('task not found', {}, http_status: 404) unless task

              @state_id = HaveAPI::ClientTestAPI::ActionStateBackend.create_state(
                label: 'task-run',
                total: 3,
                can_cancel: true
              )
              {}
            end

            attr_reader :state_id
          end
        end
      end

      define_resource(:Test) do
        desc 'Error testing resource'
        auth false

        define_action(:Fail) do
          extend DocFilter
          route 'fail'
          http_method :get
          output(:hash) {}
          authorize { allow }

          def exec
            error!('forced failure', { base: ['forced failure'] }, http_status: 400)
          end
        end

        define_action(:Echo) do
          extend DocFilter
          route 'echo'
          http_method :post
          input(:hash) do
            integer :i, required: true
            float :f, required: true
            bool :b, required: true
            datetime :dt, required: true
            string :s, required: true
            text :t, required: true
          end
          output(:hash) do
            integer :i
            float :f
            bool :b
            datetime :dt
            string :s
            text :t
          end
          authorize { allow }

          def exec
            input
          end
        end

        define_action(:EchoOptional) do
          extend DocFilter
          route 'echo_optional'
          http_method :post
          input(:hash) do
            datetime :dt, required: false
          end
          output(:hash) do
            bool :dt_provided, required: true
            bool :dt_nil, required: true
            datetime :dt
          end
          authorize { allow }

          def exec
            ret = {
              dt_provided: input.has_key?(:dt),
              dt_nil: input[:dt].nil?
            }
            ret[:dt] = input[:dt] unless input[:dt].nil?
            ret
          end
        end

        define_action(:EchoOptionalGet) do
          extend DocFilter
          route 'echo_optional_get'
          http_method :get
          input(:hash) do
            datetime :dt, required: false
          end
          output(:hash) do
            bool :dt_provided, required: true
            bool :dt_nil, required: true
            datetime :dt
          end
          authorize { allow }

          def exec
            ret = {
              dt_provided: input.has_key?(:dt),
              dt_nil: input[:dt].nil?
            }
            ret[:dt] = input[:dt] unless input[:dt].nil?
            ret
          end
        end

        define_action(:EchoResource) do
          extend DocFilter
          route 'echo_resource'
          http_method :post
          input(:hash) do
            resource HaveAPI::ClientTestAPI::Resources::Project, required: true
          end
          output(:hash) do
            integer :project, required: true
          end
          authorize { allow }

          def exec
            { project: input[:project] }
          end
        end

        define_action(:EchoResourceOptional) do
          extend DocFilter
          route 'echo_resource_optional'
          http_method :get
          input(:hash) do
            resource HaveAPI::ClientTestAPI::Resources::Project, required: false
          end
          output(:hash) do
            bool :project_provided, required: true
            bool :project_nil, required: true
            integer :project
          end
          authorize { allow }

          def exec
            ret = {
              project_provided: input.has_key?(:project),
              project_nil: input[:project].nil?
            }
            ret[:project] = input[:project] unless input[:project].nil?
            ret
          end
        end
      end
    end

    class BasicProvider < HaveAPI::Authentication::Basic::Provider
      protected

      def find_user(_request, username, password)
        user = USERS[username]
        return nil unless user
        return nil unless password == 'pass'

        user
      end
    end

    class TokenConfig < HaveAPI::Authentication::Token::Config
      class << self
        def reset!
          @tokens = {}
        end

        def tokens
          @tokens ||= {}
        end
      end

      request do
        handle do |req, res|
          input = req.input
          user = USERS[input[:user]]

          if user && input[:password] == 'pass'
            token = "token-#{user.login}"
            HaveAPI::ClientTestAPI::TokenConfig.tokens[token] = user
            res.token = token
            res.valid_to = Time.now + input[:interval].to_i
            res.complete = true
            res.ok
          else
            res.error = 'invalid credentials'
            res
          end
        end
      end

      renew do
        handle do |req, res|
          if HaveAPI::ClientTestAPI::TokenConfig.tokens[req.token]
            res.valid_to = Time.now + 3600
            res.ok
          else
            res.error = 'unknown token'
            res
          end
        end
      end

      revoke do
        handle do |req, res|
          HaveAPI::ClientTestAPI::TokenConfig.tokens.delete(req.token)
          res.ok
        end
      end

      def find_user_by_token(_request, token)
        HaveAPI::ClientTestAPI::TokenConfig.tokens[token]
      end
    end

    TokenProvider = HaveAPI::Authentication::Token.with_config(TokenConfig)

    def self.reset!
      Store.reset!
      ActionStateBackend.reset!
      TokenConfig.reset!
    end

    def self.build_server(base_url:)
      HaveAPI.implicit_version = '1.0'

      reset!

      api = HaveAPI::Server.new(Resources)
      api.use_version(:all)
      api.default_version = '1.0'
      api.auth_chain << BasicProvider
      api.auth_chain << TokenProvider
      api.action_state = ActionStateBackend

      api.connect_hook(:pre_mount) do |ret, _server, sinatra|
        sinatra.get '/__health' do
          'ok'
        end

        sinatra.post '/__reset' do
          HaveAPI::ClientTestAPI.reset!
          content_type 'application/json'
          JSON.dump(ok: true)
        end

        ret
      end

      api.mount('/')
      api
    end
  end
end

module HaveAPI::Spec
  # Contains methods for specification of API to be used in `description` block.
  module ApiBuilder
    # Uses an empty module as the source for the API. It will have no resources,
    # no actions. Version default to `1`.
    def empty_api
      api(Module.new)
      default_version(1)
    end

    # Set an API module or create the API using DSL.
    # @param mod [Module] module name or nil
    # @yield block is executed in a dynamically created module
    def api(mod = nil, &block)
      unless mod
        mod = Module.new do
          def self.define_resource(name, superclass: HaveAPI::Resource, &block)
            return false if const_defined?(name)

            cls = Class.new(superclass)
            const_set(name, cls)
            cls.class_exec(&block) if block
            cls
          end

          module_eval(&block)
        end

        const_set(:ApiModule, mod)
      end

      opt(:api_module, mod)
    end

    # Set authentication chain.
    def auth_chain(chain)
      opt(:auth_chain, chain)
    end

    # Select API versions to be used.
    def use_version(v)
      before(:each) do
        self.class.opt(:versions, v)
      end
    end

    # Set default API version.
    def default_version(v)
      opt(:default_version, v)
    end

    # Set action state backend to mount HaveAPI::Resources::ActionState
    def action_state(backend)
      opt(:action_state, backend)
    end

    # Set a custom mount path.
    def mount_to(path)
      opt(:mount, path)
    end

    # Login using HTTP basic.
    def login(*credentials)
      before(:each) do
        basic_authorize(*credentials)
      end
    end

    # @private
    def opts
      @opts
    end

    # @private
    def opt(name, v)
      @opts ||= {}
      @opts[name] = v
    end
  end
end

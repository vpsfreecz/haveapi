module HaveAPI::Client
  # Instance of an object from the API.
  # An instance of this class may be in three states:
  # - resolved/persistent - the instance was created by an action that retrieved
  #   it from the API.
  # - unresolved - this instance is an attribute of another instance that was resolved
  #   and will be resolved when first accessed.
  # - not persistent - created by Resource.new, the object was not yet sent to the API.
  class ResourceInstance < Resource
    def initialize(client, api, resource, action: nil, response: nil,
                   resolved: false, meta: nil, persistent: true)
      super(client, api, resource._name)

      @action = action
      @resource = resource
      @resolved = resolved
      @meta = meta
      @persistent = persistent
      @resource_instances = {}

      if response
        if response.is_a?(Hash)
          @params = response
          @prepared_args = response[:_meta][:url_params]

        else
          @response = response
          @params = response.response
          @prepared_args = response.meta[:url_params]
        end

        setup_from_clone(resource)
        define_attributes
      end

      unless @persistent
        setup_from_clone(resource)
        define_implicit_attributes
        define_attributes(@action.input_params)
      end
    end

    def new
      raise NoMethodError.new
    end

    # Invoke +create+ action if the object is not persistent,
    # +update+ action if it is.
    def save
      if @persistent
        method(:update).call

      else
        @action.provide_args
        @response = Response.new(@action, @action.execute(attributes_for_api(@action)))

        if @response.ok?
          @params = @response.response
          define_attributes

        else
          return nil
        end

        @persistent = true
        self
      end
    end

    # Call #save and raise ActionFailed if it fails.
    def save!
      raise ActionFailed.new(@response) if save.nil?
      self
    end

    # Resolve the object (fetch it from the API) if it is not resolved yet.
    def resolve
      return self if @resolved

      @action.provide_args(*@meta[:url_params])
      @response = Response.new(@action, @action.execute({}))
      @params = @response.response

      setup_from_clone(@resource)
      define_attributes

      @resolved = true
      self
    end

    # Return Response object which created this instance.
    def api_response
      @response
    end

    # Return a hash of all object attributes retrieved from the API.
    def attributes
      @params
    end

    def to_s
      "<#{self.class.to_s}:#{object_id}:#{@resource._name}>"
    end

    protected
    # Define access/writer methods for object attributes.
    def define_attributes(params = nil)
      (params || @action.params).each do |name, param|
        case param[:type]
          when 'Resource'
            @resource_instances[name] = find_association(param, @params[name])

            # id reader
            ensure_method(:"#{name}_id") { @params[name][ param[:value_id].to_sym ] }

            # id writer
            ensure_method(:"#{name}_id=") { |id| @params[name][ param[:value_id].to_sym ] = id }

            # value reader
            ensure_method(name) do
              @resource_instances[name] && @resource_instances[name].resolve
            end

            # value writer
            ensure_method(:"#{name}=") do |obj|
              @params[name][ param[:value_id].to_sym ] = obj.method(param[:value_id]).call
              @params[name][ param[:value_label].to_sym ] = obj.method(param[:value_label]).call

              @resource_instances[name] = obj
            end

          else
            # reader
            ensure_method(name) { @params[name] }

            # writer
            ensure_method(:"#{name}=") { |new_val| @params[name] = new_val }
        end
      end
    end

    # Define method +name+ with +block+ if it isn't defined yet.
    def ensure_method(name, &block)
      define_singleton_method(name, &block) unless respond_to?(name)
    end

    # Define nil references to resource attributes.
    # Used only for not-persistent objects.
    def define_implicit_attributes
      @params = {}

      @action.input_params.each do |name, param|
        @params[name] = {} if param[:type] == 'Resource'
      end
    end

    # Return a hash of all attributes suitable to be sent to the API +action+.
    def attributes_for_api(action)
      ret = {}

      return ret if action.input_layout != :object

      action.input_params.each do |name, param|
        case param[:type]
          when 'Resource'
            ret[name] = @params[name][ param[:value_id].to_sym ]

          else
            ret[name] = @params[name]
        end
      end

      ret
    end

    # Find associated resource and create its unresolved instance.
    def find_association(res_desc, res_val)
      return nil unless res_val

      tmp = @client

      res_desc[:resource].each do |r|
        tmp = tmp.method(r).call
      end

      # FIXME: read _meta namespace from description
      ResourceInstance.new(
          @client,
          @api,
          tmp,
          action: tmp.actions[:show],
          resolved: res_val[:_meta][:resolved],
          response: res_val[:_meta][:resolved] ? res_val : nil,
          meta: res_val[:_meta]
      )
    end

    # Override Resource.default_action_input_params.
    def default_action_input_params(action)
      attributes_for_api(action)
    end
  end
end

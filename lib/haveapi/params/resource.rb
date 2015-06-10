module HaveAPI::Parameters
  class Resource
    attr_reader :name, :resource, :label, :desc, :type, :value_id, :value_label,
                :choices, :value_params

    def initialize(resource, name: nil, label: nil, desc: nil,
        choices: nil, value_id: :id, value_label: :label, required: nil,
        db_name: nil)
      @resource = resource
      @resource_path = build_resource_path(resource)
      @name = name || resource.to_s.demodulize.underscore.to_sym
      @label = label || (name && name.to_s.capitalize) || resource.to_s.demodulize
      @desc = desc
      @choices = choices || @resource::Index
      @value_id = value_id
      @value_label = value_label
      @required = required
      @db_name = db_name
    end

    def db_name
      @db_name || @name
    end

    def required?
      @required
    end

    def optional?
      !@required
    end

    def show_action
      @resource::Show
    end

    def describe(context)
      val_url = context.url_for(
          @resource::Show,
          context.endpoint && context.action_prepare && context.layout == :object && context.call_url_params(context.action, context.action_prepare)
      )
      val_method = @resource::Index.http_method.to_s.upcase

      choices_url = context.url_for(
          @choices,
          context.endpoint && context.layout == :object && context.call_url_params(context.action, context.action_prepare)
      )
      choices_method = @choices.http_method.to_s.upcase

      {
          required: required?,
          label: @label,
          description: @desc,
          type: 'Resource',
          resource: @resource_path,
          value_id: @value_id,
          value_label: @value_label,
          value: context.action_prepare && {
              url: val_url,
              method: val_method,
              help: "#{val_url}?method=#{val_method}",
          },
          choices: {
              url: choices_url,
              method: choices_method,
              help: "#{choices_url}?method=#{choices_method}"
          }
      }
    end

    def patch(attrs)
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def clean(raw)
      ::HaveAPI::ModelAdapter.for(show_action.input.layout, @resource.model).input_clean(@resource.model, raw)
    end

    def format_output(v)
      v
    end

    private
    def build_resource_path(r)
      path = []
      top_module = Kernel

      r.to_s.split('::').each do |name|
        top_module = top_module.const_get(name)

        begin
          top_module.obj_type

        rescue NoMethodError
          next
        end

        path << name.underscore
      end

      path
    end
  end
end

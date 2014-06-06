module HaveAPI::Parameters
  class Resource
    attr_reader :name, :label, :desc, :type, :value_id, :value_label

    def initialize(resource, name: nil, label: nil, desc: nil,
        choices: nil, value_id: :id, value_label: :label, required: nil)
      @resource = resource
      @resource_path = build_resource_path(resource)
      @name = name || resource.to_s.demodulize.underscore.to_sym
      @label = label || (name && name.to_s.capitalize) || resource.to_s.demodulize
      @desc = desc
      @choices = choices || @resource::Index
      @value_id = value_id
      @value_label = value_label
      @required = required
    end

    def db_name
      @name
    end

    def required?
      @required
    end

    def optional?
      !@required
    end

    def describe(context)
      val_url = context.url_for(@resource::Show)
      val_method = @resource::Index.http_method.to_s.upcase

      choices_url = context.url_for(@choices)
      choices_method = @choices.http_method.to_s.upcase

      {
          required: required?,
          label: @label,
          description: @desc,
          type: 'Resource',
          resource: @resource_path,
          value_id: @value_id,
          value_label: @value_label,
          value: {
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

    def clean(raw)
      @resource.model.find(raw)
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

module HaveAPI::ModelAdapters
  # Adapter for ActiveRecord models.
  class ActiveRecord < ::HaveAPI::ModelAdapter
    register

    def self.handle?(layout, klass)
      klass < ::ActiveRecord::Base && %i(object object_list).include?(layout)
    end

    def self.load_validators(model, params)
      tr = ValidatorTranslator.new(params.params)

      model.validators.each do |validator|
        tr.translate(validator)
      end
    end

    class Input < ::HaveAPI::ModelAdapter::Input
      def self.clean(model, raw)
        model.find(raw) if (raw.is_a?(String) && !raw.empty?) || (!raw.is_a?(String) && raw)
      end
    end

    class Output < ::HaveAPI::ModelAdapter::Output
      def self.used_by(action)
        action.meta(:object) do
          output do
            custom :url_params, label: 'URL parameters',
                   desc: 'An array of parameters needed to resolve URL to this object'
          end
        end
      end

      def has_param?(name)
        param = @context.action.output[name]
        param && @object.respond_to?(param.db_name)
      end

      def [](name)
        param = @context.action.output[name]
        v = @object.send(param.db_name)

        if v.is_a?(::ActiveRecord::Base)
          resourcify(param, v)
        else
          v
        end
      end

      def meta
        params = @context.action.resolve.call(@object)

        {
            url_params: params.is_a?(Array) ? params : [params]
        }
      end

      protected
      def resourcify(param, val)
        res_show = param.show_action
        res_output = res_show.output

        {
            param.value_id => val.send(res_output[param.value_id].db_name),
            param.value_label => val.send(res_output[param.value_label].db_name),
            _meta: {
              :url_params => res_show.resolve.call(val)
            }
        }
      end
    end

    class ValidatorTranslator
      class << self
        attr_reader :handlers

        def handle(validator, &block)
          @handlers ||= {}
          @handlers[validator] = block
        end
      end

      handle ::ActiveRecord::Validations::PresenceValidator do |v|
        validator({present: true})
      end

      handle ::ActiveModel::Validations::AbsenceValidator do |v|
        validator({absent: true})
      end

      handle ::ActiveModel::Validations::ExclusionValidator do |v|
        validator(v.options)
      end

      handle ::ActiveModel::Validations::FormatValidator do |v|
        validator({format: {with_source: v.options[:with].source}.update(v.options)})
      end

      handle ::ActiveModel::Validations::InclusionValidator do |v|
        validator(v.options)
      end

      handle ::ActiveModel::Validations::LengthValidator do |v|
        validator(v.options)
      end

      handle ::ActiveModel::Validations::NumericalityValidator do |v|
        validator(v.options)
      end

      handle ::ActiveRecord::Validations::UniquenessValidator do |v|
        validator(v.options)
      end

      def initialize(params)
        @params = params
      end

      def validator_for(param, v)
        @params.each do |p|
          next unless p.is_a?(::HaveAPI::Parameters::Param)

          if p.db_name == param
            p.add_validator(v)
            break
          end
        end
      end

      def validator(v)
        validator_for(@attr, v)
      end

      def translate(v)
        self.class.handlers.each do |klass, translator|
          if v.is_a?(klass)
            v.attributes.each do |attr|
              @attr = attr
              instance_exec(v, &translator)
            end
            break
          end
        end
      end
    end
  end
end

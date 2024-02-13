require 'haveapi/model_adapter'

module HaveAPI::ModelAdapters
  # Adapter for ActiveRecord models.
  class ActiveRecord < ::HaveAPI::ModelAdapter
    register

    def self.handle?(layout, klass)
      klass < ::ActiveRecord::Base && %i[object object_list].include?(layout)
    end

    def self.load_validators(model, params)
      tr = ValidatorTranslator.new(params.params)

      model.validators.each do |validator|
        tr.translate(validator)
      end
    end

    module Action
      module InstanceMethods
        # Helper method that sets correct ActiveRecord includes
        # according to the meta includes sent by the user.
        # `q` is the model or partial AR query. If not set,
        # action's model class is used instead.
        def with_includes(q = nil)
          q ||= self.class.model
          includes = meta && meta[:includes]
          args = includes.nil? ? [] : ar_parse_includes(includes)

          # Resulting includes may still contain duplicities in form of nested
          # includes. ar_default_includes returns a flat array where as
          # ar_parse_includes may contain hashes. But since ActiveRecord is taking
          # it well, it is not necessary to fix.
          args.concat(ar_default_includes).uniq

          if args.empty?
            q
          else
            q.includes(*args)
          end
        end

        # Parse includes sent by the user and return them
        # in an array of symbols and hashes.
        def ar_parse_includes(raw)
          return @ar_parsed_includes if @ar_parsed_includes

          @ar_parsed_includes = ar_inner_includes(raw).select do |inc|
            # Drop associations that are not registered in the AR:
            #   The API resource may have associations that are not based on
            #   associations in AR.
            if inc.is_a?(::Hash)
              inc.each_key do |k|
                next(false) unless self.class.model.reflections.has_key?(k.to_s)
              end

            else
              next(false) unless self.class.model.reflections.has_key?(inc.to_s)
            end

            true
          end
        end

        # Called by ar_parse_includes for recursion purposes.
        def ar_inner_includes(includes)
          args = []

          includes.each do |assoc|
            if assoc.index('__')
              tmp = {}
              parts = assoc.split('__')
              tmp[parts.first.to_sym] = ar_inner_includes([parts[1..].join('__')])

              args << tmp
            else
              args << assoc.to_sym
            end
          end

          args
        end

        # Default includes contain all associated resources specified
        # inaction  output parameters. They are fetched from the database
        # anyway, to return the label for even unresolved association.
        def ar_default_includes
          ret = []

          self.class.output.params.each do |p|
            if p.is_a?(HaveAPI::Parameters::Resource) && self.class.model.reflections[p.name.to_sym]
              ret << p.name.to_sym
            end
          end

          ret
        end
      end
    end

    class Input < ::HaveAPI::ModelAdapter::Input
      def self.clean(model, raw, extra)
        return if (raw.is_a?(String) && raw.empty?) || (!raw.is_a?(String) && !raw)

        if extra[:fetch]
          model.instance_exec(raw, &extra[:fetch])
        else
          model.find(raw)
        end
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

        return unless %i[object object_list].include?(action.input.layout)

        clean = proc do |raw|
          if raw.is_a?(String)
            raw.strip.split(',')
          elsif raw.is_a?(Array)
            raw
          end
        end

        desc = <<~END
          A list of names of associated resources separated by a comma.
          Nested associations are declared with '__' between resource names.
          For example, 'user,node' will resolve the two associations.
          To resolve further associations of node, use e.g. 'user,node__location',
          to go even deeper, use e.g. 'user,node__location__environment'.
        END

        action.meta(:global) do
          input do
            custom :includes, label: 'Included associations',
                              desc:, &clean
          end
        end

        action.send(:include, Action::InstanceMethods)
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
        res = @context.action.resource

        params = if @context.action.name.demodulize == 'Index' \
           && !@context.action.resolve \
           && res.const_defined?(:Show)
                   res::Show.resolve_path_params(@object)

                 else
                   @context.action.resolve_path_params(@object)
                 end

        {
          path_params: params.is_a?(Array) ? params : [params],
          resolved: true
        }
      end

      protected

      # Return representation of an associated resource `param`
      # with its instance in `val`.
      #
      # By default, it returns an unresolved resource, which contains
      # only object id and label. Resource will be resolved
      # if it is set in meta includes field.
      def resourcify(param, val)
        res_show = param.show_action
        res_output = res_show.output

        args = res_show.resolve_path_params(val)

        if includes_include?(param.name)
          push_cls = @context.action
          push_ins = @context.action_instance

          pass_includes = includes_pass_on_to(param.name)

          show = res_show.new(
            push_ins.request,
            push_ins.version,
            {},
            nil,
            @context
          )
          show.meta[:includes] = pass_includes

          # This flag is used to tell the action that it is being used
          # as a nested association, that it wasn't called directly by the user.
          show.flags[:inner_assoc] = true

          show.authorized?(push_ins.current_user) # FIXME: handle false

          ret = show.safe_output(val)

          @context.action_instance = push_ins
          @context.action = push_cls

          raise "#{res_show} resolve failed" unless ret[0]

          ret[1][res_show.output.namespace].update({
              _meta: ret[1][:_meta].update(resolved: true)
          })

        else
          {
            param.value_id => val.send(res_output[param.value_id].db_name),
            param.value_label => val.send(res_output[param.value_label].db_name),
            _meta: {
              path_params: args.is_a?(Array) ? args : [args],
              resolved: false
            }
          }
        end
      end

      # Should an association with `name` be resolved?
      def includes_include?(name)
        includes = @context.action_instance.meta[:includes]
        return unless includes

        name = name.to_sym

        if @context.action_instance.flags[:inner_assoc]
          # This action is called as an association of parent resource.
          # Meta includes are already parsed and can be accessed directly.
          includes.each do |v|
            if v.is_a?(::Hash)
              return true if v.has_key?(name)
            elsif v == name
              return true
            end
          end

          false

        else
          # This action is the one that was called by the user.
          # Meta includes contains an array of strings as was sent
          # by the user. The parsed includes must be fetched from
          # the action itself.
          includes = @context.action_instance.ar_parse_includes([])

          includes.each do |v|
            if v.is_a?(::Hash)
              return true if v.has_key?(name)
            elsif v == name
              return true
            end
          end

          false
        end
      end

      # Create an array of includes that is passed to child association.
      def includes_pass_on_to(assoc)
        parsed = if @context.action_instance.flags[:inner_assoc]
                   @context.action_instance.meta[:includes]
                 else
                   @context.action_instance.ar_parse_includes([])
                 end

        ret = []

        parsed.each do |v|
          if v.is_a?(::Hash)
            v.each { |k, v| ret << v if k == assoc }
          end
        end

        ret.flatten(1)
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

      # Presence validator may have different meaning for model and controller.
      # The attribute may be filled by other means than by controller and it is
      # wrong to assume that the parameter must ALWAYS be sent by the client.
      # Usually it would be needed only for Create and perhaps Update actions.
      #
      # handle ::ActiveRecord::Validations::PresenceValidator do |v|
      #   opts = { empty: false }
      #   opts[:message] = v.options[:message] if v.options[:message]
      #
      #   validator(HaveAPI::Validators::Presence, :present, opts)
      # end

      handle ::ActiveModel::Validations::ExclusionValidator do |v|
        opts = {
          values: v.options[:in].map { |v| v }
        }
        opts[:message] = v.options[:message] if v.options[:message]

        validator(:exclude, opts)
      end

      handle ::ActiveModel::Validations::FormatValidator do |v|
        opts = {
          rx: v.options[:with]
        }
        opts[:message] = v.options[:message] if v.options[:message]

        validator(:format, opts)
      end

      handle ::ActiveModel::Validations::InclusionValidator do |v|
        opts = {
          values: v.options[:in].map { |v| v }
        }
        opts[:message] = v.options[:message] if v.options[:message]

        validator(:include, opts)
      end

      handle ::ActiveModel::Validations::LengthValidator do |v|
        opts = {}
        opts[:min] = v.options[:minimum] if v.options[:minimum]
        opts[:max] = v.options[:maximum] if v.options[:maximum]
        opts[:equals] = v.options[:is] if v.options[:is]
        opts[:message] = v.options[:message] if v.options[:message]

        validator(:length, opts) unless opts.empty?
      end

      handle ::ActiveModel::Validations::NumericalityValidator do |v|
        opts = {}

        opts[:min] = v.options[:greater_than] + 1 if v.options[:greater_than]
        opts[:min] = v.options[:greater_than_or_equal_to] if v.options[:greater_than_or_equal_to]

        if v.options[:equal_to]
          validator(accept: v.options[:equal_to])
          next
        end

        opts[:max] = v.options[:less_than] - 1 if v.options[:less_than]
        opts[:max] = v.options[:less_than_or_equal_to] if v.options[:less_than_or_equal_to]

        opts[:odd] = true if v.options[:odd]
        opts[:even] = true if v.options[:even]

        opts[:message] = v.options[:message] if v.options[:message]

        validator(:number, opts) unless opts.empty?
      end

      def initialize(params)
        @params = params
      end

      def validator_for(param, key, opts)
        @params.each do |p|
          next unless p.is_a?(::HaveAPI::Parameters::Typed)

          if p.db_name == param
            p.add_validator(key, opts) if p.load_validators?
            break
          end
        end
      end

      def validator(key, opts)
        validator_for(@attr, key, opts)
      end

      def translate(v)
        self.class.handlers.each do |klass, translator|
          next unless v.is_a?(klass)

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

module HaveAPI::Parameters
  module MetadataI18n
    def metadata_i18n_catalog_items(context, i18n_path)
      %i[label description].filter_map do |kind|
        fallback = metadata_i18n_fallback(kind)
        keys = metadata_i18n_keys(context, i18n_path, kind, fallback)
        value = HaveAPI.localize(fallback).to_s.strip

        next if keys.empty? || value.empty?

        {
          param: HaveAPI::Params.i18n_segment(@name),
          kind: metadata_i18n_key_suffix(kind),
          keys:,
          value:
        }
      end + choice_i18n_catalog_items(context, i18n_path)
    end

    private

    def localized_label(context, i18n_path)
      localized_metadata(context, i18n_path, :label, @label)
    end

    def localized_description(context, i18n_path)
      localized_metadata(context, i18n_path, :description, @desc)
    end

    def localized_validators(context, i18n_path, validators)
      include_validator = validators[:include]
      return validators unless include_validator && include_validator.has_key?(:values)

      values = include_validator.fetch(:values)
      localized_values = localized_choice_values(context, i18n_path, values)
      return validators if localized_values.equal?(values)

      validators.merge(include: include_validator.merge(values: localized_values))
    end

    def localized_metadata(context, i18n_path, kind, fallback)
      keys = metadata_i18n_keys(context, i18n_path, kind, fallback)
      default = HaveAPI.localize(fallback)

      return default if keys.empty?

      keys.each do |key|
        value = ::I18n.t(key, default: nil)
        return value unless value.nil?
      end

      default
    end

    def metadata_i18n_keys(context, i18n_path, kind, fallback)
      explicit_key = explicit_metadata_i18n_key(kind)

      return [normalize_metadata_i18n_key(context, explicit_key)] if explicit_key
      return [] if fallback.is_a?(HaveAPI::LocalizedMessage)
      return [] unless i18n_path

      scope = parameter_i18n_scope(context)
      return [] unless scope

      exact_key = [
        scope,
        i18n_path,
        HaveAPI::Params.i18n_segment(@name),
        metadata_i18n_key_suffix(kind)
      ].join('.')

      [exact_key, *metadata_i18n_default_keys(context, i18n_path, kind, scope)].uniq
    end

    def localized_choice_values(context, i18n_path, values)
      case values
      when ::Hash
        values.to_h do |value, label|
          [
            value,
            localized_metadata(context, i18n_path, choice_i18n_kind(value), label)
          ]
        end
      when ::Array
        localized = values.to_h do |value|
          label = localized_metadata(
            context,
            i18n_path,
            choice_i18n_kind(value),
            value.to_s
          )
          [value, label]
        end

        localized.any? { |value, label| label.to_s != value.to_s } ? localized : values
      else
        values
      end
    end

    def choice_i18n_catalog_items(context, i18n_path)
      values = choice_i18n_values
      return [] unless values

      choice_i18n_fallbacks(values).filter_map do |value, fallback|
        keys = metadata_i18n_keys(context, i18n_path, choice_i18n_kind(value), fallback)
        label = HaveAPI.localize(fallback).to_s.strip

        next if keys.empty? || label.empty?

        {
          param: HaveAPI::Params.i18n_segment(@name),
          kind: metadata_i18n_key_suffix(choice_i18n_kind(value)),
          keys:,
          value: label
        }
      end
    end

    def choice_i18n_values
      metadata_i18n_choice_values
    end

    def metadata_i18n_choice_values
      nil
    end

    def choice_i18n_fallbacks(values)
      case values
      when ::Hash
        values
      when ::Array
        values.to_h { |value| [value, value.to_s] }
      else
        {}
      end
    end

    def choice_i18n_kind(value)
      "choices.#{HaveAPI::Params.i18n_segment(value)}.label"
    end

    def metadata_i18n_fallback(kind)
      case kind
      when :label
        @label
      when :description
        @desc
      else
        raise ArgumentError, "unsupported parameter metadata kind #{kind.inspect}"
      end
    end

    def explicit_metadata_i18n_key(kind)
      case kind
      when :label
        @label_key
      when :description
        @desc_key
      end
    end

    def normalize_metadata_i18n_key(context, key)
      str = key.to_s
      return str if str.include?('.')

      scope = parameter_i18n_scope(context)
      scope ? "#{scope}.#{str}" : str
    end

    def parameter_i18n_scope(context)
      return unless context.respond_to?(:server)
      return unless context.server.respond_to?(:parameter_i18n_scope)

      scope = context.server.parameter_i18n_scope
      return if scope.nil? || scope == false

      Array(scope).flat_map { |segment| segment.to_s.split('.') }
                  .map { |segment| HaveAPI::Params.i18n_segment(segment) }
                  .join('.')
    end

    def metadata_i18n_key_suffix(kind)
      kind == :description ? 'description' : kind.to_s
    end

    def metadata_i18n_default_keys(context, i18n_path, kind, scope)
      param = HaveAPI::Params.i18n_segment(@name)
      suffix = metadata_i18n_key_suffix(kind)
      resource_prefix = metadata_i18n_resource_prefix(context)
      path = metadata_i18n_path_parts(i18n_path)
      keys = []

      if path[:meta_type]
        if resource_prefix
          keys << [
            scope,
            resource_prefix,
            'meta',
            path.fetch(:meta_type),
            path.fetch(:direction),
            param,
            suffix
          ].join('.')
        end

        keys << [
          scope,
          'meta',
          path.fetch(:meta_type),
          path.fetch(:direction),
          param,
          suffix
        ].join('.')
      elsif resource_prefix
        keys << [
          scope,
          resource_prefix,
          path.fetch(:direction),
          param,
          suffix
        ].join('.')
        keys << [
          scope,
          resource_prefix,
          'attributes',
          param,
          suffix
        ].join('.')
      end

      keys << [scope, 'attributes', param, suffix].join('.') unless path[:meta_type]
      keys
    end

    def metadata_i18n_resource_prefix(context)
      return unless context.respond_to?(:resource_path) && context.resource_path

      [
        'resources',
        *context.resource_path.map { |segment| HaveAPI::Params.i18n_segment(segment) }
      ].join('.')
    end

    def metadata_i18n_path_parts(i18n_path)
      parts = i18n_path.to_s.split('.')

      return { direction: parts.last } unless parts[-3] == 'meta'

      {
        meta_type: parts[-2],
        direction: parts[-1]
      }
    end
  end
end

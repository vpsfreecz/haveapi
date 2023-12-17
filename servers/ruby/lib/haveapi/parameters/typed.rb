require 'date'

module HaveAPI::Parameters
  class Typed
    ATTRIBUTES = %i(label desc type db_name default fill clean protected load_validators)

    attr_reader :name, :label, :desc, :type, :default

    def initialize(name, args = {})
      # The hash values are deleted and it shouldn't affect the received hash
      myargs = args.clone

      @name = name
      @label = myargs.delete(:label) || name.to_s.capitalize
      @layout = :custom

      (ATTRIBUTES - %i(label)).each do |attr|
        instance_variable_set("@#{attr}", myargs.delete(attr))
      end

      @type ||= String

      @validators = HaveAPI::ValidatorChain.new(myargs) unless myargs.empty?
      fail "unused arguments #{myargs}" unless myargs.empty?
    end

    def db_name
      @db_name || @name
    end

    def required?
      @validators ? @validators.required? : false
    end

    def optional?
      !@required
    end

    def fill?
      @fill
    end

    def load_validators?
      @load_validators.nil? || @load_validators
    end

    def describe(context)
      {
        required: required?,
        label: @label,
        description: @desc,
        type: @type ? @type.to_s : String.to_s,
        validators: @validators ? @validators.describe : {},
        default: @default,
        protected: @protected || false,
      }
    end

    def add_validator(k, v)
      @validators ||= HaveAPI::ValidatorChain.new({})
      @validators.add_or_replace(k, v)
    end

    def patch(attrs)
      attrs.each do |k, v|
        if ATTRIBUTES.include?(k)
          instance_variable_set("@#{k}", v)

        else
          add_validator(k, v)
        end
      end
    end

    def clean(raw)
      return instance_exec(raw, &@clean) if @clean

      val = if raw.nil?
        @default

      elsif @type.nil?
        nil

      elsif @type == Integer
        raw.to_i

      elsif @type == Float
        raw.to_f

      elsif @type == Boolean
        Boolean.to_b(raw)

      elsif @type == ::Datetime
        begin
          DateTime.iso8601(raw).to_time

        rescue ArgumentError
          raise HaveAPI::ValidationError.new("not in ISO 8601 format '#{raw}'")
        end

      else
        raw
      end

      val
    end

    def validate(v, params)
      @validators ? @validators.validate(v, params) : true
    end

    def format_output(v)
      if v.nil?
        nil

      elsif @type == ::Datetime && v.is_a?(Time)
        v.iso8601

      elsif @type == Boolean
        v ? true : false

      elsif @type == Integer
        v.to_i

      elsif @type == Float
        v.to_f

      elsif @type == String
        v.to_s

      else
        v
      end
    end
  end
end

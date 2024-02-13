module HaveAPI
  # Validators are stored in this module.
  module Validators; end

  # Base class for all validators.
  #
  # All validators can have a short and a full form. The short form is used
  # when default configuration is sufficient. Custom settings can be set using
  # the full form.
  #
  # The short form means the validator is configured as `<option> => <single value>`.
  # The full form is `<option> => { hash with configuration options }`.
  #
  # It is up to each validator what exactly the short form means and what options
  # can be set. Specify only those options that you wish to override. The only
  # common option is `message` - the error message sent to the client if the provided
  # value did not pass the validator.
  #
  # The `message` can contain `%{value}`, which is replaced by the actual value
  # that did not pass the validator.
  class Validator
    class << self
      # Set validator name used in API documentation.
      def name(v = nil)
        if v
          @name = v

        else
          @name
        end
      end

      # Specify options this validator takes from the parameter definition.
      def takes(*opts)
        @takes = opts
      end

      # True if this validator uses any of options in hash `opts`.
      def use?(opts)
        opts.keys.intersect?(@takes)
      end

      # Use the validator on given set of options in hash `opts`. Used
      # options are removed from `opts`.
      def use(opts)
        keys = opts.keys & @takes

        raise 'too many keys' if keys.size > 1

        new(keys.first, opts.delete(keys.first))
      end
    end

    attr_accessor :message, :params

    def initialize(key, opts)
      reconfigure(key, opts)
    end

    def reconfigure(key, opts)
      @key = key
      @opts = opts
      setup
    end

    def useful?
      @useful.nil? ? true : @useful
    end

    # Validators should be configured by the given options. This method may be
    # called multiple times, if the validator is reconfigured after it was
    # created.
    def setup
      raise NotImplementedError
    end

    # Return a hash documenting this validator.
    def describe
      raise NotImplementedError
    end

    # Return true if the value is valid.
    def valid?(v)
      raise NotImplementedError
    end

    # Calls method valid?, but before calling it sets instance variable
    # `@params`. It contains of hash of all other parameters. The validator
    # may use this information as it will.
    def validate(v, params)
      @params = params
      ret = valid?(v)
      @params = nil
      ret
    end

    protected

    # This method has three modes of function.
    #
    # 1. If `v` is nil, it returns `@opts`. It is used if `@opts` is not a hash
    #    but a single value - abbreviation if we're ok with default settings
    #    for given validator.
    # 2. If `v` is not nil and `@opts` is not a hash, it returns `default`
    # 3. If `v` is not nil and `@opts` is a hash and `@opts[v]` is not nil, it is
    #    returned. Otherwise the `default` is returned.
    def take(v = nil, default = nil)
      if v.nil?
        @opts

      else
        return default unless @opts.is_a?(::Hash)
        return @opts[v] unless @opts[v].nil?

        default
      end
    end

    # Declare validator as useless. Such validator does not do anything and can
    # be removed from validator chain. Validator can become useless when it's configuration
    # makes it so.
    def useless
      @useful = false
    end

    # Returns true if `@opts` is not a hash.
    def simple?
      !@opts.is_a?(::Hash)
    end

    # Returns the name of the option given to this validator. It may bear some
    # meaning to the validator.
    def opt
      @key
    end
  end
end

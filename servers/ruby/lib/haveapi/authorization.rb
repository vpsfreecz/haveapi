module HaveAPI
  class Authorization
    def initialize(&block)
      @blocks = [block]
    end

    def initialize_clone(other)
      super
      @blocks = other.instance_variable_get('@blocks').clone
    end

    # Returns true if user is authorized.
    # Block must call allow to authorize user, default rule is deny.
    def authorized?(user, path_params)
      @restrict = []

      catch(:rule) do
        @blocks.each do |block|
          instance_exec(user, path_params, &block)
        end

        deny # will not be called if some block throws allow
      end
    end

    def prepend_block(block)
      @blocks.insert(0, block)
    end

    # Apply restrictions on query which selects objects from database.
    # Most common usage is restrict user to access only objects he owns.
    def restrict(**kwargs)
      normalized = normalize_hash_keys(kwargs)

      normalized.each do |key, value|
        @restrict.each do |restriction|
          deny if restriction.has_key?(key) && restriction[key] != value
        end
      end

      @restrict << normalized
    end

    # Restrict parameters client can set/change.
    # @param whitelist [Array<Symbol>] allow only listed parameters
    # @param blacklist [Array<Symbol>] allow all parameters except listed ones
    def input(whitelist: nil, blacklist: nil)
      @input = {
        whitelist:,
        blacklist:
      }
    end

    # Restrict parameters client can retrieve.
    # @param whitelist [Array<Symbol>] allow only listed parameters
    # @param blacklist [Array<Symbol>] allow all parameters except listed ones
    def output(whitelist: nil, blacklist: nil)
      @output = {
        whitelist:,
        blacklist:
      }
    end

    def allow
      throw(:rule, true)
    end

    def deny
      throw(:rule, false)
    end

    def restrictions
      ret = {}

      @restrict.each do |r|
        r.each do |key, value|
          deny if ret.has_key?(key) && ret[key] != value

          ret[key] = value
        end
      end

      ret
    end

    def filter_input(input, params)
      filter_inner(input, @input, params, false)
    end

    def filter_output(output, params, format = false)
      filter_inner(output, @output, params, format)
    end

    def permitted_input_names(params)
      permitted_params(params, @input).map(&:name)
    end

    private

    def filter_inner(allowed_params, direction, params, format)
      allowed = {}

      permitted_params(allowed_params, direction).each do |p|
        if params.has_param?(p.name)
          allowed[p.name] = format ? p.format_output(params[p.name]) : params[p.name]

        elsif params.has_param?(p.name.to_s) # FIXME: remove double checking
          allowed[p.name] = format ? p.format_output(params[p.name.to_s]) : params[p.name.to_s]
        end
      end

      allowed
    end

    def permitted_params(params, direction)
      return params unless direction

      if direction[:whitelist]
        whitelist = normalize_names(direction[:whitelist])

        params.select { |p| whitelist.include?(p.name) }
      elsif direction[:blacklist]
        blacklist = normalize_names(direction[:blacklist])

        params.reject { |p| blacklist.include?(p.name) }
      else
        params
      end
    end

    def normalize_names(names)
      names.map { |name| normalize_key(name) }
    end

    def normalize_hash_keys(hash)
      hash.each_with_object({}) do |(key, value), ret|
        ret[normalize_key(key)] = value
      end
    end

    def normalize_key(key)
      key.is_a?(String) ? key.to_sym : key
    end
  end
end

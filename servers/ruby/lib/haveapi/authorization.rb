module HaveAPI
  class Authorization
    def initialize(&block)
      @blocks = [block]
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
      @restrict << kwargs
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
        ret.update(r)
      end

      ret
    end

    def filter_input(input, params)
      filter_inner(input, @input, params, false)
    end

    def filter_output(output, params, format = false)
      filter_inner(output, @output, params, format)
    end

    private

    def filter_inner(allowed_params, direction, params, format)
      allowed = {}

      allowed_params.each do |p|
        if params.has_param?(p.name)
          allowed[p.name] = format ? p.format_output(params[p.name]) : params[p.name]

        elsif params.has_param?(p.name.to_s) # FIXME: remove double checking
          allowed[p.name] = format ? p.format_output(params[p.name.to_s]) : params[p.name.to_s]
        end
      end

      return allowed unless direction

      if direction[:whitelist]
        ret = {}

        direction[:whitelist].each do |p|
          ret[p] = allowed[p] if allowed.has_key?(p)
        end

        ret

      elsif direction[:blacklist]
        ret = allowed.dup

        direction[:blacklist].each do |p|
          ret.delete(p)
        end

        ret

      else
        allowed
      end
    end
  end
end

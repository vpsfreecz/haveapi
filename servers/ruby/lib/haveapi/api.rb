module HaveAPI
  # Return a list of all resources or yield them if block is given.
  def self.resources(module_name) # yields: resource
    ret = []

    module_name.constants.select do |c|
      obj = module_name.const_get(c)

      if obj.obj_type == :resource
        if block_given?
          yield obj
        else
          ret << obj
        end
      end
    end

    ret
  end

  # Iterate through all resources and return those for which yielded block
  # returned true.
  def self.filter_resources(module_name)
    ret = []

    resources(module_name) do |r|
      ret << r if yield(r)
    end

    ret
  end

  # Return list of resources for version +v+.
  def self.get_version_resources(module_name, v)
    filter_resources(module_name) do |r|
      r_v = r.version || implicit_version

      if r_v.is_a?(Array)
        r_v.include?(v)

      else
        r_v == v || r_v == :all
      end
    end
  end

  # Return a list of all API versions.
  def self.versions(module_name)
    ret = []

    resources(module_name) do |r|
      ret << r.version unless ret.include?(r.version)
    end

    ret.compact!
    ret << implicit_version if ret.empty? && implicit_version
    ret
  end

  def self.module_name=(name)
    @module_name = name
  end

  def self.module_name
    @module_name
  end

  def self.implicit_version=(v)
    @implicit_version = v
  end

  def self.implicit_version
    @implicit_version
  end

  def self.default_authenticate=(chain)
    @default_auth = chain
  end

  def self.default_authenticate
    @default_auth || []
  end
end

require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Parameters::Base
    include Utils

    # Register the parameter handler
    #
    # The block is called whenever a new parameter is to be instantiated. If
    # this class supports the parameter, the block returns true, else false.
    # The first class to return true is used.
    #
    # @yieldparam role [Symbol]
    # @yieldparam direction [Symbol]
    # @yieldparam name [String]
    # @yieldparam desc [Hash]
    # @yiledreturn [Boolean, nil]
    def self.handle(&block)
      Parameter.register(self, block)
    end

    # @return [InputOutput]
    attr_reader :io

    # Parameter name in the API
    # @return [String]
    attr_reader :name

    # HaveAPI data type
    # @return [String]
    attr_reader :type

    # Parameter name in Go
    # @return [String]
    attr_reader :go_name

    # Go type for action input
    # @return [String]
    attr_reader :go_in_type

    # Go type for action output
    # @return [String]
    attr_reader :go_out_type

    def initialize(io, name, desc)
      @io = io
      @name = name
      @type = desc[:type]
      @desc = desc
      @go_name = camelize(name)
    end

    def resolve
      do_resolve
      @desc = nil
    end

    def <=>(other)
      go_name <=> other
    end

    protected
    # @return [Hash]
    attr_reader :desc

    def do_resolve

    end
  end
end

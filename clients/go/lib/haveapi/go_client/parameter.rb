module HaveAPI::GoClient
  module Parameters; end

  module Parameter
    # @param klass [Class]
    # @param block [Proc]
    def self.register(klass, block)
      @handlers ||= []
      @handlers << [klass, block]
    end

    # @param role [Symbol]
    # @param direction [Symbol]
    # @param io [InputOutput]
    # @param name [String]
    # @param desc [Hash]
    # @return [Parameters::Base, nil]
    def self.new(role, direction, io, name, desc)
      klass, =
        @handlers.select do |_klass, block|
          block.call(role, direction, name, desc)
        end.first

      klass ? klass.new(io, name, desc) : nil
    end
  end
end

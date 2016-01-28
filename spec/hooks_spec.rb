describe HaveAPI::Hooks do
  class ClassLevel
    include HaveAPI::Hookable

    has_hook :simple_hook
    has_hook :arg_hook
    has_hook :ret_hook
    has_hook :context_hook
  end
  
  class InstanceLevel
    include HaveAPI::Hookable

    has_hook :simple_hook
    has_hook :arg_hook
    has_hook :ret_hook
    has_hook :context_hook
  end

  def connect_hook(name, &block)
    @obj.connect_hook(name, &block)
  end

  def call_hooks(*args)
    case @level
    when :class
      @obj.call_hooks(*args)

    when :instance
      if @method
        @obj.method(@method).call(*args)

      else
        @obj.call_hooks_for(*args)
      end

    else
      fail "unknown level '#{@level}'"
    end
  end
  
  shared_examples(:common) do
    it 'calls hooks' do
      called = false

      connect_hook(:simple_hook) do |ret|
        called = true
        ret
      end

      call_hooks(:simple_hook)
      expect(called).to be true
    end
    
    it 'passes arguments' do
      called = false
      
      connect_hook(:arg_hook) do |ret, a, b, c|
        called = true
        expect([a, b, c]).to eq([1, 2, 3])
        ret
      end

      call_hooks(:arg_hook, args: [1, 2, 3])
      expect(called).to be true
    end

    it 'chains hooks' do
      arr = []

      5.times do |i|
        connect_hook(:simple_hook) do |ret|
          arr << i
          ret
        end
      end

      call_hooks(:simple_hook)
      expect(arr).to eq([0, 1, 2, 3, 4])
    end

    it 'chains return value' do
      5.times do
        connect_hook(:ret_hook) do |ret|
          ret[:counter] += 1
          ret
        end
      end

      sum = call_hooks(:ret_hook, initial: {counter: 0})
      expect(sum[:counter]).to eq(5)
    end

    it 'executes block in given context' do
      class CustomEnv
        def foo
          'bar'
        end
      end

      connect_hook(:context_hook) do |ret|
        ret[:val] = foo
        ret
      end

      res = call_hooks(:context_hook, CustomEnv.new)
      expect(res[:val]).to eq('bar')
    end
  end

  context 'on class level' do
    before(:each) do
      @obj = ClassLevel
      @level = :class
    end
    
    include_examples :common
  end

  context 'on instance level' do
    context 'all hooks' do
      before(:each) do
        @obj = InstanceLevel.new
        @level = :instance
      end
      
      include_examples :common
    end
    
    context 'only class hooks' do
      # FIXME: class hooks fail (that is correct, no class hooks are defined)
      #        must find a way to test failure
      #include_examples :common
    end
    
    context 'only instance hooks' do
      before(:each) do
        @obj = InstanceLevel.new
        @level = :instance
        @method = :call_instance_hooks_for
      end
      
      include_examples :common
    end
  end
end

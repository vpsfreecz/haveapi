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

  let(:hook_target) { nil }
  let(:hook_level) { nil }
  let(:hook_method) { nil }

  def connect_hook(name, &block)
    hook_target.connect_hook(name, &block)
  end

  def call_hooks(*args, **kwargs)
    case hook_level
    when :class
      hook_target.call_hooks(*args, **kwargs)

    when :instance
      if hook_method
        hook_target.method(hook_method).call(*args, **kwargs)

      else
        hook_target.call_hooks_for(*args, **kwargs)
      end

    else
      raise "unknown level '#{hook_level}'"
    end
  end

  shared_examples('common') do
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

      sum = call_hooks(:ret_hook, initial: { counter: 0 })
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

  context 'when on class level' do
    let(:hook_target) { ClassLevel }
    let(:hook_level) { :class }

    it_behaves_like 'common'
  end

  context 'when on instance level' do
    context 'with all hooks' do
      let(:hook_target) { InstanceLevel.new }
      let(:hook_level) { :instance }

      it_behaves_like 'common'
    end

    context 'with only instance hooks' do
      let(:hook_target) { InstanceLevel.new }
      let(:hook_level) { :instance }
      let(:hook_method) { :call_instance_hooks_for }

      it_behaves_like 'common'
    end
  end
end

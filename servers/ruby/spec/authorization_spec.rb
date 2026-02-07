describe HaveAPI::Authorization do
  let(:resource_class) { Class.new(HaveAPI::Resource) }
  let(:index_action_class) { Class.new(HaveAPI::Actions::Default::Index) }

  before do
    stub_const('Resource', resource_class)
    stub_const('Resource::Index', index_action_class)
    index_action_class.superclass.delayed_inherited(index_action_class)
    index_action_class.class_exec do
      input do
        string :param1
        string :param2
      end

      output do
        string :param1
        string :param2
      end
    end
    Resource.routes
  end

  it 'defaults to deny' do
    auth = described_class.new {}
    expect(auth.authorized?(nil, {})).to be false
  end

  it 'can authorize' do
    auth = described_class.new { allow }
    expect(auth.authorized?(nil, {})).to be true
  end

  it 'applies restrictions' do
    auth = described_class.new do
      restrict filter: true
      allow
    end

    expect(auth.authorized?(nil, {})).to be true
    expect(auth.restrictions[:filter]).to be true
  end

  it 'whitelists input' do
    auth = described_class.new do
      input whitelist: %i[param1]
      allow
    end

    expect(auth.authorized?(nil, {})).to be true

    action = Resource::Index

    expect(auth.filter_input(
      action.input.params,
      action.model_adapter(action.input.layout).input({
        param1: '123',
        param2: '456'
      })
    ).keys).to contain_exactly(:param1)
  end

  it 'blacklists input' do
    auth = described_class.new do
      input blacklist: %i[param1]
      allow
    end

    expect(auth.authorized?(nil, {})).to be true

    action = Resource::Index

    expect(auth.filter_input(
      action.input.params,
      action.model_adapter(action.input.layout).input({
        param1: '123',
        param2: '456'
      })
    ).keys).to contain_exactly(:param2)
  end

  it 'whitelists output' do
    auth = described_class.new do
      output whitelist: %i[param1]
      allow
    end

    expect(auth.authorized?(nil, {})).to be true

    action = Resource::Index

    expect(auth.filter_output(
      action.output.params,
      action.model_adapter(action.output.layout).output(nil, {
        param1: '123',
        param2: '456'
      })
    ).keys).to contain_exactly(:param1)
  end

  it 'blacklists output' do
    auth = described_class.new do
      output blacklist: %i[param1]
      allow
    end

    expect(auth.authorized?(nil, {})).to be true

    action = Resource::Index

    expect(auth.filter_output(
      action.output.params,
      action.model_adapter(action.output.layout).output(nil, {
        param1: '123',
        param2: '456'
      })
    ).keys).to contain_exactly(:param2)
  end
end

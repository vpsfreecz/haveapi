require 'time'

describe 'Parameters::Typed' do
  def p_type(type)
    HaveAPI::Parameters::Typed.new(:param1, type:)
  end

  def p_arg(arg = {})
    HaveAPI::Parameters::Typed.new(:param1, arg)
  end

  it 'does not change provided arguments' do
    kwargs = {
      label: 'Param 1',
      desc: 'Desc',
      required: true
    }
    p_arg(kwargs)
    expect(kwargs.keys).to contain_exactly(*%i[label desc required])
  end

  it 'automatically sets label' do
    p = p_arg
    expect(p.label).to eq('Param1')
  end

  it 'accepts custom label' do
    p = p_arg(label: 'Custom')
    expect(p.label).to eq('Custom')
  end

  it 'rejects unknown parameters' do
    expect do
      p_arg(shiny: true)
    end.to raise_error(RuntimeError)
  end

  it 'can be required' do
    p = p_arg(required: true)
    expect(p.required?).to be true
  end

  it 'can be optional' do
    p = p_arg
    expect(p.optional?).to be true

    p = p_arg(required: false)
    expect(p.optional?).to be true

    p = p_arg(required: nil)
    expect(p.optional?).to be true
  end

  it 'cleans input value' do
    # Integer
    p = p_type(Integer)
    expect(p.clean('42')).to eq(42)

    # Float
    p = p_type(Float)
    expect(p.clean('3.1456')).to eq(3.1456)

    # Boolean
    p = p_type(Boolean)

    %w[true t yes y 1].each do |v|
      expect(p.clean(v)).to be true
    end

    %w[false f no n 0].each do |v|
      expect(p.clean(v)).to be false
    end

    # Datetime
    p = p_type(Datetime)
    t = Time.now
    t2 = Time.iso8601(t.iso8601)

    expect(p.clean(t.iso8601)).to eq(t2)
    expect { p.clean('bzz') }.to raise_error(HaveAPI::ValidationError)

    # String, Text
    p = p_type(String)
    expect(p.clean('bzz')).to eq('bzz')

    # Defaults
    p = p_type(String)
    expect(p.clean(nil)).to be_nil

    p.patch(default: 'bazinga')
    expect(p.clean(nil)).to eq('bazinga')
  end

  it 'can be protected' do
    p = p_arg(protected: true)
    expect(p.describe(nil)[:protected]).to be true

    p = p_arg(protected: false)
    expect(p.describe(nil)[:protected]).to be false
  end

  it 'is unprotected by default' do
    p = p_arg
    expect(p.describe(nil)[:protected]).to be false
  end
end

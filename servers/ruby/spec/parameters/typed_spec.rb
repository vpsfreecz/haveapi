require 'time'
require 'open3'
require 'rbconfig'

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
    expect(kwargs.keys).to match_array(%i[label desc required])
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
    expect(p.optional?).to be false
  end

  it 'can be optional' do
    p = p_arg
    expect(p.required?).to be false
    expect(p.optional?).to be true

    p = p_arg(required: false)
    expect(p.required?).to be false
    expect(p.optional?).to be true

    p = p_arg(required: nil)
    expect(p.required?).to be false
    expect(p.optional?).to be true
  end

  it 'updates optional? when required is patched' do
    p = p_arg(required: false)
    expect(p.required?).to be false
    expect(p.optional?).to be true

    p.patch(required: true)
    expect(p.required?).to be true
    expect(p.optional?).to be false

    p.patch(required: nil)
    expect(p.required?).to be false
    expect(p.optional?).to be true
  end

  it 'cleans input value' do
    # Integer
    p = p_type(Integer)
    expect(p.clean('42')).to eq(42)
    expect(p.clean('  -7  ')).to eq(-7)
    expect(p.clean(12)).to eq(12)
    expect(p.clean(12.0)).to eq(12)
    expect { p.clean('abc') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('12abc') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(nil) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('12.0') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(12.3) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(true) }.to raise_error(HaveAPI::ValidationError)

    p = p_arg(type: Integer, required: true)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)

    # Float
    p = p_type(Float)
    expect(p.clean('3.1456')).to eq(3.1456)
    expect(p.clean('1e3')).to eq(1000.0)
    expect(p.clean(3)).to eq(3.0)
    expect { p.clean('abc') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(nil) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('NaN') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(Float::NAN) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(Float::INFINITY) }.to raise_error(HaveAPI::ValidationError)

    p = p_arg(type: Float, required: true)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)

    # Boolean
    p = p_type(Boolean)

    %w[true t yes y 1].each do |v|
      expect(p.clean(v)).to be true
    end

    %w[false f no n 0].each do |v|
      expect(p.clean(v)).to be false
    end

    expect(p.clean(0)).to be false
    expect(p.clean(1)).to be true
    expect(p.clean('  YES ')).to be true
    expect { p.clean('maybe') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(nil) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(2) }.to raise_error(HaveAPI::ValidationError)

    p = p_arg(type: Boolean, required: true)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)

    # Datetime
    p = p_type(Datetime)
    t = Time.now
    t2 = Time.iso8601(t.iso8601)

    expect(p.clean(t.iso8601)).to eq(t2)
    expect { p.clean('bzz') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean(nil) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean([]) }.to raise_error(HaveAPI::ValidationError)

    p = p_arg(type: Datetime, required: true)
    expect { p.clean('') }.to raise_error(HaveAPI::ValidationError)

    # String, Text
    p = p_type(String)
    expect(p.clean('bzz')).to eq('bzz')
    expect(p.clean('')).to eq('')
    expect(p.clean(123)).to eq('123')
    expect(p.clean(true)).to eq('true')
    expect { p.clean([]) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean({}) }.to raise_error(HaveAPI::ValidationError)

    p = p_type(Text)
    expect(p.clean('bzz')).to eq('bzz')
    expect(p.clean('')).to eq('')
    expect(p.clean(123)).to eq('123')
    expect(p.clean(true)).to eq('true')
    expect { p.clean([]) }.to raise_error(HaveAPI::ValidationError)
    expect { p.clean({}) }.to raise_error(HaveAPI::ValidationError)

    # Nullable
    p = p_arg(type: Integer, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil

    p = p_arg(type: Float, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil

    p = p_arg(type: Boolean, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil

    p = p_arg(type: Datetime, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil

    p = p_arg(type: String, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil
    p.patch(default: 'bazinga')
    expect(p.clean(nil)).to be_nil

    p = p_arg(type: Text, nullable: true)
    expect(p.clean('')).to be_nil
    expect(p.clean(nil)).to be_nil
  end

  it 'rejects nil returned by custom cleaners unless nullable' do
    p = p_arg(type: String, required: true, clean: proc {})
    expect { p.clean('value') }.to raise_error(HaveAPI::ValidationError, /cannot be null/)

    p = p_arg(type: String, nullable: true, clean: proc {})
    expect(p.clean('value')).to be_nil
  end

  it 'deep stringifies custom parameter keys by default' do
    p = p_arg(type: Custom)
    raw = {
      rawId: 'credential-id',
      response: {
        clientDataJSON: 'client-data'
      },
      transports: [
        { type: :usb }
      ]
    }

    expect(p.clean(raw)).to eq({
      'rawId' => 'credential-id',
      'response' => {
        'clientDataJSON' => 'client-data'
      },
      'transports' => [
        { 'type' => :usb }
      ]
    })
    expect(raw).to have_key(:rawId)
  end

  it 'deep symbolizes custom parameter keys when requested' do
    p = p_arg(type: Custom, symbolize_keys: true)

    expect(p.clean({
      'rawId' => 'credential-id',
      'response' => {
        'clientDataJSON' => 'client-data'
      },
      'transports' => [
        { 'type' => 'usb' }
      ]
    })).to eq({
      rawId: 'credential-id',
      response: {
        clientDataJSON: 'client-data'
      },
      transports: [
        { type: 'usb' }
      ]
    })
  end

  it 'passes normalized custom keys to custom cleaners' do
    p = p_arg(type: Custom, clean: proc { |v| v.fetch('rawId') })
    expect(p.clean({ rawId: 'credential-id' })).to eq('credential-id')

    p = p_arg(type: Custom, symbolize_keys: true, clean: proc { |v| v.fetch(:rawId) })
    expect(p.clean({ 'rawId' => 'credential-id' })).to eq('credential-id')
  end

  it 'rejects invalid string encoding during coercion' do
    invalid = "\xff".b.force_encoding(Encoding::UTF_8)

    expect { p_type(String).clean(invalid) }.to raise_error(HaveAPI::ValidationError)
    expect { p_type(Integer).clean(invalid) }.to raise_error(HaveAPI::ValidationError)
    expect { p_type(Float).clean(invalid) }.to raise_error(HaveAPI::ValidationError)
    expect { p_type(Boolean).clean(invalid) }.to raise_error(HaveAPI::ValidationError)
    expect { p_type(Datetime).clean(invalid) }.to raise_error(HaveAPI::ValidationError)
  end

  it 'can be protected' do
    p = p_arg(protected: true)
    expect(p.describe(nil)[:protected]).to be true

    p = p_arg(protected: false)
    expect(p.describe(nil)[:protected]).to be false
  end

  it 'loads Time#iso8601 for datetime output formatting' do
    code = <<~RUBY
      require 'haveapi/types'
      require 'haveapi/parameters/typed'

      param = HaveAPI::Parameters::Typed.new(:at, type: Datetime)
      print param.format_output(Time.utc(1970, 1, 1))
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      '-I',
      File.expand_path('../../lib', __dir__),
      '-e',
      code
    )

    expect(status).to be_success, stderr
    expect(stdout).to eq('1970-01-01T00:00:00Z')
  end

  it 'is unprotected by default' do
    p = p_arg
    expect(p.describe(nil)[:protected]).to be false
  end
end

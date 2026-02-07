describe HaveAPI::Params do
  class MyResource < HaveAPI::Resource
    params(:all) do
      string :res_param1
      string :res_param2
    end

    class Index < HaveAPI::Actions::Default::Index
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        string :not_label
      end
    end

    class Create < HaveAPI::Actions::Default::Create
    end
  end

  it 'executes all blocks' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { string :param1 }
    p.add_block proc { string :param2 }
    p.add_block proc { string :param3 }
    p.exec
    expect(p.params.map(&:name)).to match_array(%i[param1 param2 param3])
  end

  it 'returns deduced singular namespace' do
    p = described_class.new(:input, MyResource::Index)
    expect(p.namespace).to eq(:my_resource)
  end

  it 'returns deduced plural namespace' do
    p = described_class.new(:input, MyResource::Index)
    p.layout = :object_list
    expect(p.namespace).to eq(:my_resources)
  end

  it 'returns set namespace' do
    p = described_class.new(:input, MyResource::Index)
    p.namespace = :custom_ns
    expect(p.namespace).to eq(:custom_ns)
  end

  it 'uses params from parent resource' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { use :all }
    p.exec
    expect(p.params.map(&:name)).to match_array(%i[res_param1 res_param2])
  end

  it 'has param requires' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { requires :p_required }
    p.exec
    expect(p.params.first.required?).to be true
  end

  it 'has param optional' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { optional :p_optional }
    p.exec
    expect(p.params.first.required?).to be false
  end

  it 'has param string' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { string :p_string }
    p.exec
    expect(p.params.first.type).to eq(String)
  end

  it 'has param text' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { text :p_text }
    p.exec
    expect(p.params.first.type).to eq(Text)
  end

  %i[id integer foreign_key].each do |type|
    it "has param #{type}" do
      p = described_class.new(:input, MyResource::Index)
      p.add_block proc { send(type, :"p_#{type}") }
      p.exec
      expect(p.params.first.type).to eq(Integer)
    end
  end

  it 'has param float' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { float :p_float }
    p.exec
    expect(p.params.first.type).to eq(Float)
  end

  it 'has param bool' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { bool :p_bool }
    p.exec
    expect(p.params.first.type).to eq(Boolean)
  end

  it 'has param datetime' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { datetime :p_datetime }
    p.exec
    expect(p.params.first.type).to eq(Datetime)
  end

  it 'has param param' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { param :p_param, type: Integer }
    p.exec
    expect(p.params.first.type).to eq(Integer)
  end

  it 'has param resource' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block proc { resource MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
  end

  it 'patches params' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block(proc do
      string :param1, label: 'Param 1'
      string :param2, label: 'Param 2', desc: 'Implicit description'
    end)
    p.exec
    p.patch(:param1, label: 'Better param 1')
    p.patch(:param2, desc: 'Better description')
    expect(p.params[0].label).to eq('Better param 1')
    expect(p.params[1].desc).to eq('Better description')
  end

  it 'validates upon build' do
    p = described_class.new(:output, MyResource::Index)
    p.add_block proc { resource MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
    expect { p.validate_build }.to raise_error(RuntimeError)
  end

  it 'accepts valid input layout' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block(proc do
      string :param1, required: true
      string :param2
    end)
    p.exec

    expect do
      p.check_layout({
        my_resource: {}
      })
    end.not_to raise_error
  end

  it 'rejects invalid input layout' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block(proc do
      string :param1, required: true
      string :param2
    end)
    p.exec

    expect do
      p.check_layout({
        something_bad: {}
      })
    end.to raise_error(HaveAPI::ValidationError)
  end

  it 'indexes parameters by name' do
    p = described_class.new(:input, MyResource::Index)
    p.add_block(proc do
      string :param1
      string :param2
    end)
    p.exec

    expect(p[:param1]).to eq(p.params[0])
    expect(p[:param2]).to eq(p.params[1])
  end
end

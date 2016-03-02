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
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { string :param1 }
    p.add_block Proc.new { string :param2 }
    p.add_block Proc.new { string :param3 }
    p.exec
    expect(p.params.map { |p| p.name }).to contain_exactly(*%i(param1 param2 param3))
  end

  it 'returns deduced singular namespace' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    expect(p.namespace).to eq(:my_resource)
  end

  it 'returns deduced plural namespace' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.layout = :object_list
    expect(p.namespace).to eq(:my_resources)
  end

  it 'returns set namespace' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.namespace = :custom_ns
    expect(p.namespace).to eq(:custom_ns)
  end

  it 'uses params from parent resource' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { use :all }
    p.exec
    expect(p.params.map { |p| p.name }).to contain_exactly(*%i(res_param1 res_param2))
  end

  it 'has param requires' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { requires :p_required }
    p.exec
    expect(p.params.first.required?).to be true
  end

  it 'has param optional' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { optional :p_optional }
    p.exec
    expect(p.params.first.required?).to be false
  end

  it 'has param string' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { string :p_string }
    p.exec
    expect(p.params.first.type).to eq(String)
  end

  it 'has param text' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { text :p_text }
    p.exec
    expect(p.params.first.type).to eq(Text)
  end

  %i(id integer foreign_key).each do |type|
    it "has param #{type}" do
      p = HaveAPI::Params.new(:input, MyResource::Index)
      p.add_block Proc.new { send(type, :"p_#{type}") }
      p.exec
      expect(p.params.first.type).to eq(Integer)
    end
  end

  it 'has param float' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { float :p_float }
    p.exec
    expect(p.params.first.type).to eq(Float)
  end

  it 'has param bool' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { bool :p_bool }
    p.exec
    expect(p.params.first.type).to eq(Boolean)
  end

  it 'has param datetime' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { datetime :p_datetime }
    p.exec
    expect(p.params.first.type).to eq(Datetime)
  end

  it 'has param param' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { param :p_param, type: Integer }
    p.exec
    expect(p.params.first.type).to eq(Integer)
  end

  it 'has param resource' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block Proc.new { resource MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
  end

  it 'patches params' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block(Proc.new do
      string :param1, label: 'Param 1'
      string :param2, label: 'Param 2', desc: 'Implicit description'
    end)
    p.exec
    p.patch(:param1, label: 'Better param 1')
    p.patch(:param2, desc: 'Better description')
    expect(p.params.first.label).to eq('Better param 1')
    expect(p.params.second.desc).to eq('Better description')
  end

  it 'validates upon build' do
    p = HaveAPI::Params.new(:output, MyResource::Index)
    p.add_block Proc.new { resource MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
    expect { p.validate_build }.to raise_error(RuntimeError)
  end

  it 'accepts valid input layout' do
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block(Proc.new do
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
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block(Proc.new do
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
    p = HaveAPI::Params.new(:input, MyResource::Index)
    p.add_block(Proc.new do
      string :param1
      string :param2
    end)
    p.exec
    
    expect(p[:param1]).to eq(p.params[0])
    expect(p[:param2]).to eq(p.params[1])
  end
end

module ParamsSpec
  class Authorization
    def filter_input(_definitions, params)
      params
    end
  end

  class DescriptionContext
    attr_accessor :server, :resource_path, :action, :layout, :authorization,
                  :endpoint, :action_prepare

    def initialize(server:, resource_path:, action:)
      @server = server
      @resource_path = resource_path
      @action = action
      @authorization = Authorization.new
      @endpoint = false
      @action_prepare = false
    end

    def path_for(*)
      '/v1/my_resources'
    end
  end

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
end

describe HaveAPI::Params do
  it 'executes all blocks' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { string :param1 }
    p.add_block proc { string :param2 }
    p.add_block proc { string :param3 }
    p.exec
    expect(p.params.map(&:name)).to match_array(%i[param1 param2 param3])
  end

  it 'returns deduced singular namespace' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    expect(p.namespace).to eq(:my_resource)
  end

  it 'returns deduced plural namespace' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.layout = :object_list
    expect(p.namespace).to eq(:my_resources)
  end

  it 'returns set namespace' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.namespace = :custom_ns
    expect(p.namespace).to eq(:custom_ns)
  end

  it 'uses params from parent resource' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { use :all }
    p.exec
    expect(p.params.map(&:name)).to match_array(%i[res_param1 res_param2])
  end

  it 'normalizes string include and exclude names from shared params' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { use :all, include: ['res_param1'] }
    p.exec
    expect(p.params.map(&:name)).to eq([:res_param1])

    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { use :all, exclude: ['res_param2'] }
    p.exec
    expect(p.params.map(&:name)).to eq([:res_param1])
  end

  it 'has param requires' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { requires :p_required }
    p.exec
    expect(p.params.first.required?).to be true
  end

  it 'has param optional' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { optional :p_optional }
    p.exec
    expect(p.params.first.required?).to be false
  end

  it 'has param string' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { string :p_string }
    p.exec
    expect(p.params.first.type).to eq(String)
  end

  it 'has param text' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { text :p_text }
    p.exec
    expect(p.params.first.type).to eq(Text)
  end

  %i[id integer foreign_key].each do |type|
    it "has param #{type}" do
      p = described_class.new(:input, ParamsSpec::MyResource::Index)
      p.add_block proc { send(type, :"p_#{type}") }
      p.exec
      expect(p.params.first.type).to eq(Integer)
    end
  end

  it 'has param float' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { float :p_float }
    p.exec
    expect(p.params.first.type).to eq(Float)
  end

  it 'has param bool' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { bool :p_bool }
    p.exec
    expect(p.params.first.type).to eq(Boolean)
  end

  it 'has param datetime' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { datetime :p_datetime }
    p.exec
    expect(p.params.first.type).to eq(Datetime)
  end

  it 'has param param' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { param :p_param, type: Integer }
    p.exec
    expect(p.params.first.type).to eq(Integer)
  end

  it 'has param resource' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { resource ParamsSpec::MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
  end

  it 'localizes resource parameter metadata' do
    previous_locale = ::I18n.locale
    previous_available = ::I18n.available_locales
    ::I18n.available_locales = (previous_available + %i[en cs]).uniq
    ::I18n.backend.store_translations(
      :cs,
      params_spec: {
        resource: {
          label: 'Vlastnik',
          description: 'Vyber vlastnika'
        }
      }
    )

    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block(proc do
      resource ParamsSpec::MyResource,
               label: HaveAPI.message('params_spec.resource.label'),
               desc: HaveAPI.message('params_spec.resource.description')
    end)
    p.exec

    context = double(
      path_for: '/v1/my_resources',
      endpoint: false,
      action_prepare: false
    )

    ::I18n.locale = :cs
    expect(p.params.first.describe(context)).to include(
      label: 'Vlastnik',
      description: 'Vyber vlastnika'
    )
  ensure
    ::I18n.locale = previous_locale
    ::I18n.available_locales = previous_available
  end

  it 'localizes resource parameter metadata from a parameter scope' do
    previous_locale = ::I18n.locale
    previous_available = ::I18n.available_locales
    ::I18n.available_locales = (previous_available + %i[en cs]).uniq
    ::I18n.backend.store_translations(
      :cs,
      params_spec: {
        resources: {
          my_resource: {
            actions: {
              index: {
                input: {
                  my_resource: {
                    label: 'Zdroj',
                    description: 'Vyber zdroj'
                  }
                }
              }
            }
          }
        }
      }
    )

    server = double(parameter_i18n_scope: 'params_spec')
    context = ParamsSpec::DescriptionContext.new(
      server:,
      resource_path: %w[my_resource],
      action: ParamsSpec::MyResource::Index
    )

    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block(proc do
      resource ParamsSpec::MyResource, desc: 'Choose a resource'
    end)
    p.exec

    ::I18n.locale = :cs
    param = p.describe(context)[:parameters][:my_resource]
    expect(param).to include(
      label: 'Zdroj',
      description: 'Vyber zdroj'
    )
  ensure
    ::I18n.locale = previous_locale
    ::I18n.available_locales = previous_available
  end

  it 'returns app-owned parameter metadata i18n catalog candidates' do
    server = double(parameter_i18n_scope: 'params_spec')
    context = ParamsSpec::DescriptionContext.new(
      server:,
      resource_path: %w[my_resource],
      action: ParamsSpec::MyResource::Index
    )

    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block(proc do
      string :hostname, label: 'Hostname', desc: 'VPS hostname'
      string :framework,
             label: HaveAPI.message('haveapi.parameters.metadata.no.label')
    end)
    p.exec

    items = p.parameter_metadata_i18n_items(context)
    label = items.detect { |item| item[:param] == 'hostname' && item[:kind] == 'label' }

    expect(label[:value]).to eq('Hostname')
    expect(label[:keys]).to eq(%w[
                                 params_spec.resources.my_resource.actions.index.input.hostname.label
                                 params_spec.resources.my_resource.input.hostname.label
                                 params_spec.resources.my_resource.attributes.hostname.label
                                 params_spec.attributes.hostname.label
                               ])
    expect(items.none? { |item| item[:param] == 'framework' }).to be true
  end

  it 'does not parse meta resource path segments as metadata paths' do
    server = double(parameter_i18n_scope: 'params_spec')
    context = ParamsSpec::DescriptionContext.new(
      server:,
      resource_path: %w[meta],
      action: ParamsSpec::MyResource::Index
    )

    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block proc { string :hostname, label: 'Hostname' }
    p.exec

    item = p.parameter_metadata_i18n_items(context).first

    expect(item[:keys]).to eq(%w[
                                params_spec.resources.meta.actions.index.input.hostname.label
                                params_spec.resources.meta.input.hostname.label
                                params_spec.resources.meta.attributes.hostname.label
                                params_spec.attributes.hostname.label
                              ])
  end

  it 'returns meta parameter metadata i18n catalog candidates' do
    server = double(parameter_i18n_scope: 'params_spec')
    context = ParamsSpec::DescriptionContext.new(
      server:,
      resource_path: %w[my_resource],
      action: ParamsSpec::MyResource::Index
    )
    i18n_path = described_class.metadata_i18n_path(context, :global, :output)

    p = described_class.new(:output, ParamsSpec::MyResource::Index)
    p.add_block proc { integer :count, label: 'Count' }
    p.exec

    item = p.parameter_metadata_i18n_items(context, i18n_path:, meta_type: :global).first

    expect(item[:keys]).to eq(%w[
                                params_spec.resources.my_resource.actions.index.meta.global.output.count.label
                                params_spec.resources.my_resource.meta.global.output.count.label
                                params_spec.meta.global.output.count.label
                              ])
  end

  it 'patches params' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
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
    p = described_class.new(:output, ParamsSpec::MyResource::Index)
    p.add_block proc { resource ParamsSpec::MyResource }
    p.exec
    expect(p.params.first).to be_an_instance_of(HaveAPI::Parameters::Resource)
    expect { p.validate_build }.to raise_error(RuntimeError)
  end

  it 'accepts valid input layout' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
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
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
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

  it 'rejects present optional namespaces with invalid shapes' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block(proc do
      string :param1
    end)
    p.exec

    expect do
      p.check_layout({
        my_resource: 'not-a-hash'
      })
    end.to raise_error(HaveAPI::ValidationError)
  end

  it 'rejects non-hash list elements' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.layout = :hash_list
    p.add_block(proc do
      string :param1
    end)
    p.exec

    expect do
      p.check_layout({
        my_resources: ['not-a-hash']
      })
    end.to raise_error(HaveAPI::ValidationError)
  end

  it 'indexes parameters by name' do
    p = described_class.new(:input, ParamsSpec::MyResource::Index)
    p.add_block(proc do
      string :param1
      string :param2
    end)
    p.exec

    expect(p[:param1]).to eq(p.params[0])
    expect(p[:param2]).to eq(p.params[1])
  end
end

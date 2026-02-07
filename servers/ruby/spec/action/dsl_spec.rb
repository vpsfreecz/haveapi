describe HaveAPI::Action do
  def stub_resource_class(const_name)
    resource_class = Class.new(HaveAPI::Resource)
    stub_const(const_name, resource_class)
    resource_class
  end

  def build_action(resource_const, action_const, superclass = HaveAPI::Action, &block)
    klass = Class.new(superclass)
    stub_const("#{resource_const}::#{action_const}", klass)
    klass.superclass.delayed_inherited(klass)
    klass.class_exec(&block) if block
    klass
  end

  context 'with DSL' do
    it 'inherits input' do
      stub_resource_class('Resource')
      input_action_class = build_action('Resource', 'InputAction') do
        input do
          string :param
        end
      end
      build_action('Resource', 'SubInputAction', input_action_class)

      # Invokes execution of input/output blocks
      Resource.routes
      expect(Resource::SubInputAction.input.params.first.name).to eq(:param)
    end

    it 'inherits output' do
      stub_resource_class('Resource')
      output_action_class = build_action('Resource', 'OutputAction') do
        output do
          string :param
        end
      end
      build_action('Resource', 'SubOutputAction', output_action_class)

      # Invokes execution of input/output blocks
      Resource.routes
      expect(Resource::SubOutputAction.output.params.first.name).to eq(:param)
    end

    it 'chains input' do
      stub_resource_class('Resource')
      build_action('Resource', 'InputChainAction') do
        input do
          string :param1
        end

        input do
          string :param2
        end
      end

      # Invokes execution of input/output blocks
      Resource.routes

      params = Resource::InputChainAction.input.params.map(&:name)
      expect(params).to contain_exactly(:param1, :param2)
    end

    it 'chains output' do
      stub_resource_class('Resource')
      build_action('Resource', 'OutputChainAction') do
        output do
          string :param1
        end

        output do
          string :param2
        end
      end

      # Invokes execution of input/output blocks
      Resource.routes

      params = Resource::OutputChainAction.output.params.map(&:name)
      expect(params).to contain_exactly(:param1, :param2)
    end

    it 'can combine chaining and inheritance' do
      stub_resource_class('Resource')
      base_action_class = build_action('Resource', 'BaseAction') do
        input do
          string :inbase1
        end

        input do
          string :inbase2
        end

        output do
          string :outbase1
        end

        output do
          string :outbase2
        end
      end
      build_action('Resource', 'SubAction', base_action_class) do
        input do
          string :insub1
          string :insub2
        end

        input do
          string :insub3
        end

        output do
          string :outsub1
          string :outsub2
        end

        output do
          string :outsub3
        end
      end

      # Invokes execution of input/output blocks
      Resource.routes

      input = Resource::SubAction.input.params.map(&:name)
      output = Resource::SubAction.output.params.map(&:name)

      expect(input).to match_array(%i[inbase1 inbase2 insub1 insub2 insub3])
      expect(output).to match_array(%i[outbase1 outbase2 outsub1 outsub2 outsub3])
    end

    it 'sets layout' do
      stub_resource_class('Resource')
      build_action('Resource', 'DefaultLayoutAction')
      build_action('Resource', 'ObjectLayoutAction') do
        input(:object) {}
        output(:object) {}
      end
      build_action('Resource', 'ObjectListLayoutAction') do
        input(:object_list) {}
        output(:object_list) {}
      end
      build_action('Resource', 'HashLayoutAction') do
        input(:hash) {}
        output(:hash) {}
      end
      build_action('Resource', 'HashListLayoutAction') do
        input(:hash_list) {}
        output(:hash_list) {}
      end
      build_action('Resource', 'CombinedLayoutAction') do
        input(:hash) {}
        output(:object_list) {}
      end

      expect(Resource::DefaultLayoutAction.input.layout).to eq(:object)
      expect(Resource::DefaultLayoutAction.output.layout).to eq(:object)

      expect(Resource::ObjectLayoutAction.input.layout).to eq(:object)
      expect(Resource::ObjectLayoutAction.output.layout).to eq(:object)

      expect(Resource::ObjectListLayoutAction.input.layout).to eq(:object_list)
      expect(Resource::ObjectListLayoutAction.output.layout).to eq(:object_list)

      expect(Resource::HashLayoutAction.input.layout).to eq(:hash)
      expect(Resource::HashLayoutAction.output.layout).to eq(:hash)

      expect(Resource::HashListLayoutAction.input.layout).to eq(:hash_list)
      expect(Resource::HashListLayoutAction.output.layout).to eq(:hash_list)

      expect(Resource::CombinedLayoutAction.input.layout).to eq(:hash)
      expect(Resource::CombinedLayoutAction.output.layout).to eq(:object_list)
    end

    it 'catches exceptions in input' do
      stub_resource_class('ExResourceIn')
      build_action('ExResourceIn', 'ExInputAction') do
        input do
          raise 'this is terrible!'
        end
      end

      expect { ExResourceIn.routes }.to raise_error(HaveAPI::BuildError)
    end

    it 'catches exceptions in output' do
      stub_resource_class('ExResourceOut')
      build_action('ExResourceOut', 'ExOutputAction') do
        output do
          raise 'this is terrible!'
        end
      end

      expect { ExResourceOut.routes }.to raise_error(HaveAPI::BuildError)
    end
  end
end

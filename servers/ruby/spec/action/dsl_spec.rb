describe HaveAPI::Action do
  context 'DSL' do
    it 'inherits input' do
      class Resource < HaveAPI::Resource
        class InputAction < HaveAPI::Action
          input do
            string :param
          end
        end

        class SubInputAction < InputAction; end
      end

      # Invokes execution of input/output blocks
      Resource.routes
      expect(Resource::SubInputAction.input.params.first.name).to eq(:param)
    end

    it 'inherits output' do
      class Resource < HaveAPI::Resource
        class OutputAction < HaveAPI::Action
          output do
            string :param
          end
        end

        class SubOutputAction < OutputAction; end
      end

      # Invokes execution of input/output blocks
      Resource.routes
      expect(Resource::SubOutputAction.output.params.first.name).to eq(:param)
    end

    it 'chains input' do
      class Resource < HaveAPI::Resource
        class InputChainAction < HaveAPI::Action
          input do
            string :param1
          end

          input do
            string :param2
          end
        end
      end

      # Invokes execution of input/output blocks
      Resource.routes

      params = Resource::InputChainAction.input.params.map { |p| p.name }
      expect(params).to contain_exactly(:param1, :param2)
    end

    it 'chains output' do
      class Resource < HaveAPI::Resource
        class OutputChainAction < HaveAPI::Action
          output do
            string :param1
          end

          output do
            string :param2
          end
        end
      end

      # Invokes execution of input/output blocks
      Resource.routes

      params = Resource::OutputChainAction.output.params.map { |p| p.name }
      expect(params).to contain_exactly(:param1, :param2)
    end

    it 'can combine chaining and inheritance' do
      class Resource < HaveAPI::Resource
        class BaseAction < HaveAPI::Action
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

        class SubAction < BaseAction
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
      end

      # Invokes execution of input/output blocks
      Resource.routes

      input = Resource::SubAction.input.params.map { |p| p.name }
      output = Resource::SubAction.output.params.map { |p| p.name }

      expect(input).to contain_exactly(*%i[inbase1 inbase2 insub1 insub2 insub3])
      expect(output).to contain_exactly(*%i[outbase1 outbase2 outsub1 outsub2 outsub3])
    end

    it 'sets layout' do
      class Resource < HaveAPI::Resource
        class DefaultLayoutAction < HaveAPI::Action; end

        class ObjectLayoutAction < HaveAPI::Action
          input(:object) {}
          output(:object) {}
        end

        class ObjectListLayoutAction < HaveAPI::Action
          input(:object_list) {}
          output(:object_list) {}
        end

        class HashLayoutAction < HaveAPI::Action
          input(:hash) {}
          output(:hash) {}
        end

        class HashListLayoutAction < HaveAPI::Action
          input(:hash_list) {}
          output(:hash_list) {}
        end

        class CombinedLayoutAction < HaveAPI::Action
          input(:hash) {}
          output(:object_list) {}
        end
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
      class ExResourceIn < HaveAPI::Resource
        class ExInputAction < HaveAPI::Action
          input do
            raise 'this is terrible!'
          end
        end
      end

      expect { ExResourceIn.routes }.to raise_error(HaveAPI::BuildError)
    end

    it 'catches exceptions in output' do
      class ExResourceOut < HaveAPI::Resource
        class ExOutputAction < HaveAPI::Action
          output do
            raise 'this is terrible!'
          end
        end
      end

      expect { ExResourceOut.routes }.to raise_error(HaveAPI::BuildError)
    end
  end
end

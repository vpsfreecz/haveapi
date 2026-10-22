# frozen_string_literal: true

require 'spec_helper'

describe HaveAPI::Example do
  api do
    define_resource(:Widget) do
      version 1
      auth false

      define_action(:BulkImport) do
        route 'bulk_import'
        http_method :post
        authorize { allow }

        input(:hash_list) do
          string :name
        end

        output(:hash) do
          integer :count
        end

        # rubocop:disable RSpec/NoExpectationExample
        example 'bulk import' do
          request([{ name: 'alpha' }])
          response({ count: 1 })
        end
        # rubocop:enable RSpec/NoExpectationExample

        def exec
          { count: input.size }
        end
      end

      define_action(:ProseOnly) do
        route 'prose_only'
        http_method :get
        authorize { allow }

        input(:hash) do
          string :filter
        end

        output(:hash) do
          string :name
        end

        # rubocop:disable RSpec/NoExpectationExample
        example 'prose only' do
          comment 'No request or response body is needed.'
        end
        # rubocop:enable RSpec/NoExpectationExample

        def exec
          { name: 'alpha' }
        end
      end

      define_action(:ValidatedExample) do
        route 'validated/{widget_id}'
        http_method :post
        authorize { allow }

        input(:hash) do
          string :name, required: true
          integer :count
          bool :active
          datetime :created_at
          custom :metadata
        end

        output(:hash) do
          integer :count
          bool :accepted
        end

        # rubocop:disable RSpec/NoExpectationExample
        example 'valid structured data' do
          path_params 101
          request({
                    name: 'alpha',
                    count: 2,
                    active: true,
                    created_at: '2026-07-26T10:30:00Z',
                    metadata: { source: 'documentation' }
                  })
          response({ count: 2 })
        end
        # rubocop:enable RSpec/NoExpectationExample

        def exec
          { count: input[:count], accepted: true }
        end
      end
    end
  end

  default_version 1

  it 'describes list-shaped request examples' do
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    examples = api_response[:resources][:widget][:actions][:bulk_import][:examples]
    expect(examples.first[:request]).to eq([{ name: 'alpha' }])

    call_api(:options, '/v1/widgets/bulk_import?method=POST')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:examples].first[:request]).to eq([{ name: 'alpha' }])
  end

  it 'describes prose-only examples without filtering missing bodies' do
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    examples = api_response[:resources][:widget][:actions][:prose_only][:examples]
    expect(examples.first[:request]).to be_nil
    expect(examples.first[:response]).to be_nil

    call_api(:options, '/v1/widgets/prose_only?method=GET')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:examples].first[:request]).to be_nil
    expect(api_response[:examples].first[:response]).to be_nil
  end

  describe 'build validation' do
    def example_for(action, path:, title: 'invalid example', &)
      example = HaveAPI::Example.new(title)
      example.instance_eval(&)
      example.validate_build(action, path:, index: 0)
    end

    def validated_example_action
      self.class.const_get(:ApiModule)::Widget::ValidatedExample
    end

    it 'accepts valid structured and prose-only examples' do
      expect do
        example_for(
          validated_example_action,
          path: '/v1/widgets/validated/{widget_id}',
          title: 'valid'
        ) do
          path_params 101
          request(name: 'alpha', count: 2, active: false)
          response(count: 2)
        end
      end.not_to raise_error

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          comment 'The prose describes a request that is not represented as structured data.'
        end
      end.not_to raise_error
    end

    it 'rejects path parameter count and request layout errors' do
      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          request([{ name: 'alpha' }])
        end
      end.to raise_error(/path_params has 0 values.*requires 1/)

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated') do
          request([{ name: 'alpha' }])
        end
      end.to raise_error(/request must be an object/)
    end

    it 'rejects unknown, missing, and incorrectly typed request parameters' do
      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(name: 'alpha', mystery: true)
        end
      end.to raise_error(/unknown parameters: mystery/)

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(count: 2)
        end
      end.to raise_error(/missing required parameters: name/)

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(name: 'alpha', count: 'two')
        end
      end.to raise_error(/request.count has invalid Integer value/)
    end

    it 'allows abbreviated responses but validates present fields and error keys' do
      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(name: 'alpha')
          response(count: 1)
        end
      end.not_to raise_error

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(name: 'alpha')
          response(accepted: 'yes')
        end
      end.to raise_error(/response.accepted has invalid Boolean value/)

      expect do
        example_for(validated_example_action, path: '/v1/widgets/validated/{widget_id}') do
          path_params 101
          request(name: 'alpha')
          status false
          errors missing: ['is invalid']
        end
      end.to raise_error(/errors refer to unknown input parameters: missing/)
    end

    it 'accepts resource IDs and rejects malformed resource objects' do
      output = HaveAPI::Params.new(:output, validated_example_action)
      output.add_block(proc do
        resource HaveAPI::Resources::ActionState, name: :state
      end)
      output.exec
      action = Struct.new(:input, :output) do
        def path_param_names(_path)
          []
        end

        def to_s
          'ResourceExampleAction'
        end
      end.new(nil, output)

      expect do
        example_for(action, path: '/v1/resource-example') do
          response(state: 101)
        end
      end.not_to raise_error

      expect do
        example_for(action, path: '/v1/resource-example') do
          response(state: { label: 'missing ID' })
        end
      end.to raise_error(/resource object is missing id/)
    end
  end
end

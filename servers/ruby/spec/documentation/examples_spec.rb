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
end

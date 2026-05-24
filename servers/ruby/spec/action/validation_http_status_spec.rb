# frozen_string_literal: true

describe HaveAPI::Action do
  describe 'validation error HTTP status' do
    context 'with compatibility behavior' do
      api do
        define_resource(:ValidationStatus) do
          version 1
          auth false

          define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
            authorize { allow }

            input do
              string :name, required: true
            end

            output do
              string :name
            end

            def exec
              { name: input[:name] }
            end
          end
        end
      end

      default_version 1

      it 'keeps validation envelopes on HTTP 200 by default' do
        call_api([:ValidationStatus], :create, { validation_status: {} })

        expect(last_response.status).to eq(200)
        expect(api_response).not_to be_ok
        expect(api_response.errors[:name]).to include('required parameter missing')
      end
    end

    context 'with configured HTTP 400 status' do
      api do
        define_resource(:StrictValidationStatus) do
          version 1
          auth false

          define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
            authorize { allow }

            input do
              string :name, required: true
            end

            output do
              string :name
            end

            def exec
              { name: input[:name] }
            end
          end
        end
      end

      default_version 1
      validation_error_http_status 400

      it 'returns HTTP 400 for validation envelopes' do
        call_api([:StrictValidationStatus], :create, { strict_validation_status: {} })

        expect(last_response.status).to eq(400)
        expect(api_response).not_to be_ok
        expect(api_response.errors[:name]).to include('required parameter missing')
      end
    end
  end
end

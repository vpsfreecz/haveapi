require 'spec_helper'

describe 'Dummy' do
  api API::Resources
  use_version '1.0'

  it 'returns a list of dummies' do
    call_api :get, '/v1.0/dummies'
    expect(api_response).to be_ok
    expect(api_response.response[:dummies].length).to eq(3)
  end
  
  it 'returns a dummy' do
    call_api :get, '/v1.0/dummies/1'
    expect(api_response).to be_ok
    expect(api_response.response[:dummy][:name]).to eq('Second')
  end
end

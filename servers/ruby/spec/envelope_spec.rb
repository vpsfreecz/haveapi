describe 'Envelope' do
  context 'documentation' do
    empty_api

    it 'returns correct envelope' do
      call_api(:options, '/')
      expect(api_response.envelope.keys).to contain_exactly(
        *%i[version status response message errors]
      )
    end

    it 'succeeds' do
      call_api(:options, '/')
      expect(api_response).to be_ok
    end
  end

  context 'data' do
    empty_api

    it 'returns correct envelope' do
      call_api(:get, '/unknown_resource')
      expect(api_response.envelope.keys).to contain_exactly(
        *%i[status response message errors]
      )
    end

    it 'fails' do
      call_api(:get, '/unknown_resource')
      expect(api_response).to_not be_ok
    end
  end
end

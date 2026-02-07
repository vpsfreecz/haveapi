describe HaveAPI::Validators::Acceptance do
  shared_examples('all') do
    it 'accepts correct value' do
      expect(validator.valid?('foo')).to be true
    end

    it 'rejects incorrect value' do
      expect(validator.valid?('bar')).to be false
    end
  end

  context 'with short form' do
    let(:validator) { described_class.new(:accept, 'foo') }

    it_behaves_like 'all'
  end

  context 'with full form' do
    let(:validator) do
      described_class.new(:accept, {
        value: 'foo'
      })
    end

    it_behaves_like 'all'
  end
end

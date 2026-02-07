describe HaveAPI::Validators::Exclusion do
  shared_examples('all') do
    it 'rejects a listed value' do
      expect(validator.valid?('one')).to be false
      expect(validator.valid?('two')).to be false
      expect(validator.valid?('three')).to be false
    end

    it 'accepts an unlisted value' do
      expect(validator.valid?('zero')).to be true
      expect(validator.valid?('four')).to be true
    end
  end

  context 'with short form' do
    let(:validator) { described_class.new(:exclude, %w[one two three]) }

    it_behaves_like 'all'
  end

  context 'with full form' do
    let(:validator) do
      described_class.new(:exclude, {
        values: %w[one two three]
      })
    end

    it_behaves_like 'all'
  end
end

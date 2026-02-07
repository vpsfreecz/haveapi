describe HaveAPI::Validators::Presence do
  shared_examples('all') do
    it 'accepts a present value' do
      expect(validator.valid?('foo')).to be true
    end

    it 'rejects a missing or empty value' do
      expect(validator.valid?(nil)).to be false
      expect(validator.valid?('')).to be false
      expect(validator.valid?(" \t" * 4)).to be false
    end
  end

  context 'with empty = true' do
    context 'with short form' do
      let(:validator) { described_class.new(:required, true) }

      it_behaves_like 'all'
    end

    context 'with full form' do
      let(:validator) { described_class.new(:required, {}) }

      it_behaves_like 'all'
    end
  end

  context 'with empty = false' do
    let(:validator) { described_class.new(:required, { empty: true }) }

    it 'accepts a present value' do
      expect(validator.valid?('foo')).to be true
    end

    it 'rejects a missing or an empty value' do
      expect(validator.valid?(nil)).to be false
      expect(validator.valid?('')).to be true
      expect(validator.valid?(" \t" * 4)).to be true
    end
  end
end

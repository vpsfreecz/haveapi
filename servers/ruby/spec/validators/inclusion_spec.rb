describe HaveAPI::Validators::Inclusion do
  shared_examples('all') do
    it 'accepts a listed value' do
      expect(validator.valid?('one')).to be true
      expect(validator.valid?('two')).to be true
      expect(validator.valid?('three')).to be true
    end

    it 'rejects an unlisted value' do
      expect(validator.valid?('zero')).to be false
      expect(validator.valid?('four')).to be false
    end
  end

  context 'with include as an Array' do
    let(:values) { %w[one two three] }

    context 'with short form' do
      let(:validator) { described_class.new(:include, values) }

      it_behaves_like 'all'
    end

    context 'with full form' do
      let(:validator) { described_class.new(:include, { values: }) }

      it_behaves_like 'all'
    end
  end

  context 'with include as a Hash' do
    let(:values) do
      {
        one: 'Fancy one',
        two: 'Fancy two',
        three: 'Fancy three'
      }
    end
    let(:validator) { described_class.new(:include, { values: }) }

    it_behaves_like 'all'
  end
end

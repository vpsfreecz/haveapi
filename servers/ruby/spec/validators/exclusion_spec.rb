describe HaveAPI::Validators::Exclusion do
  shared_examples('all') do
    it 'rejects a listed value' do
      expect(@v.valid?('one')).to be false
      expect(@v.valid?('two')).to be false
      expect(@v.valid?('three')).to be false
    end

    it 'accepts an unlisted value' do
      expect(@v.valid?('zero')).to be true
      expect(@v.valid?('four')).to be true
    end
  end

  context 'short form' do
    before do
      @v = described_class.new(:exclude, %w[one two three])
    end

    it_behaves_like 'all'
  end

  context 'full form' do
    before do
      @v = described_class.new(:exclude, {
        values: %w[one two three]
      })
    end

    it_behaves_like 'all'
  end
end

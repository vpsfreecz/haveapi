describe HaveAPI::Validators::Presence do
  shared_examples('all') do
    it 'accepts a present value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects a missing or empty value' do
      expect(@v.valid?(nil)).to be false
      expect(@v.valid?('')).to be false
      expect(@v.valid?(" \t" * 4)).to be false
    end
  end

  context 'with empty = true' do
    context 'with short form' do
      before do
        @v = described_class.new(:required, true)
      end

      it_behaves_like 'all'
    end

    context 'with full form' do
      before do
        @v = described_class.new(:required, {})
      end

      it_behaves_like 'all'
    end
  end

  context 'with empty = false' do
    before do
      @v = described_class.new(:required, { empty: true })
    end

    it 'accepts a present value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects a missing or an empty value' do
      expect(@v.valid?(nil)).to be false
      expect(@v.valid?('')).to be true
      expect(@v.valid?(" \t" * 4)).to be true
    end
  end
end

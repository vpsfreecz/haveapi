describe HaveAPI::Validators::Acceptance do
  shared_examples('all') do
    it 'accepts correct value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects incorrect value' do
      expect(@v.valid?('bar')).to be false
    end
  end

  context 'with short form' do
    before do
      @v = described_class.new(:accept, 'foo')
    end

    it_behaves_like 'all'
  end

  context 'with full form' do
    before do
      @v = described_class.new(:accept, {
        value: 'foo'
      })
    end

    it_behaves_like 'all'
  end
end

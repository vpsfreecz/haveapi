describe HaveAPI::Validators::Format do
  shared_examples('all') do
    it 'accepts a value that matches the regexp' do
      expect(@v.valid?('aab')).to be true
      expect(@v.valid?('aacacb')).to be true
    end

    it 'rejects a value that does not match the regexp' do
      expect(@v.valid?('aacac')).to be false
      expect(@v.valid?('bacacb')).to be false
      expect(@v.valid?('b')).to be false
    end
  end

  context 'with match = true' do
    context 'with short form' do
      before do
        @v = described_class.new(:format, /^a[^b]+b$/)
      end

      it_behaves_like 'all'
    end

    context 'with full form' do
      before do
        @v = described_class.new(:format, {
          rx: /^a[^b]+b$/
        })
      end

      it_behaves_like 'all'
    end
  end

  context 'with match = false' do
    before do
      @v = described_class.new(:format, {
        rx: /^a[^b]+b$/,
        match: false
      })
    end

    it 'rejects a value that matches the regexp' do
      expect(@v.valid?('aab')).to be false
      expect(@v.valid?('aacacb')).to be false
    end

    it 'accepts a value if it does not match the regexp' do
      expect(@v.valid?('aacac')).to be true
      expect(@v.valid?('bacacb')).to be true
      expect(@v.valid?('b')).to be true
    end
  end
end

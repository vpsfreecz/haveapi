describe HaveAPI::Validators::Format do
  shared_examples(:all) do
    it 'accepts a value that matches the regexp' do
      expect(@v.valid?('aab')).to be true
      expect(@v.valid?('aacacb')).to be true
    end

    it "rejects a value that does not match the regexp" do
      expect(@v.valid?('aacac')).to be false
      expect(@v.valid?('bacacb')).to be false
      expect(@v.valid?('b')).to be false
    end
  end

  context 'with match = true' do
    context 'short form' do
      before(:each) do
        @v = HaveAPI::Validators::Format.new(:format, /^a[^b]+b$/)
      end

      include_examples :all
    end

    context 'full form' do
      before(:each) do
        @v = HaveAPI::Validators::Format.new(:format, {
          rx: /^a[^b]+b$/
        })
      end

      include_examples :all
    end
  end

  context 'with match = false' do
    before(:each) do
      @v = HaveAPI::Validators::Format.new(:format, {
        rx: /^a[^b]+b$/,
        match: false
      })
    end

    it 'rejects a value that matches the regexp' do
      expect(@v.valid?('aab')).to be false
      expect(@v.valid?('aacacb')).to be false
    end

    it "accepts a value if it does not match the regexp" do
      expect(@v.valid?('aacac')).to be true
      expect(@v.valid?('bacacb')).to be true
      expect(@v.valid?('b')).to be true
    end
  end
end

describe HaveAPI::Validators::Presence do
  shared_examples(:all) do
    it 'accepts a present value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects a missing or empty value' do
      expect(@v.valid?(nil)).to be false
      expect(@v.valid?('')).to be false
      expect(@v.valid?(" \t"*4)).to be false
    end
  end

  context 'with empty = true' do
    context 'in short form' do
      before(:each) do
        @v = HaveAPI::Validators::Presence.new(:required, true)
      end

      include_examples :all
    end

    context 'in full form' do
      before(:each) do
        @v = HaveAPI::Validators::Presence.new(:required, {})
      end

      include_examples :all
    end
  end

  context 'with empty = false' do
    before(:each) do
      @v = HaveAPI::Validators::Presence.new(:required, {empty: true})
    end

    it 'accepts a present value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects a missing or an empty value' do
      expect(@v.valid?(nil)).to be false
      expect(@v.valid?('')).to be true
      expect(@v.valid?(" \t"*4)).to be true
    end
  end
end

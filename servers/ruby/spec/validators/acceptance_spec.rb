describe HaveAPI::Validators::Acceptance do
  shared_examples(:all) do
    it 'accepts correct value' do
      expect(@v.valid?('foo')).to be true
    end

    it 'rejects incorrect value' do
      expect(@v.valid?('bar')).to be false
    end
  end

  context 'short form' do
    before(:each) do
      @v = HaveAPI::Validators::Acceptance.new(:accept, 'foo')
    end

    include_examples :all
  end

  context 'full form' do
    before(:each) do
      @v = HaveAPI::Validators::Acceptance.new(:accept, {
        value: 'foo'
      })
    end

    include_examples :all
  end
end

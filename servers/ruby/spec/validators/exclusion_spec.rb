describe HaveAPI::Validators::Exclusion do
  shared_examples(:all) do
    it 'rejects a listed value' do
      expect(@v.valid?('one')).to be false
      expect(@v.valid?('two')).to be false
      expect(@v.valid?('three')).to be false
    end

    it "accepts an unlisted value" do
      expect(@v.valid?('zero')).to be true
      expect(@v.valid?('four')).to be true
    end
  end 

  context 'short form' do
    before(:each) do
      @v = HaveAPI::Validators::Exclusion.new(:exclude, %w(one two three))
    end

    include_examples :all
  end

  context 'full form' do
    before(:each) do
      @v = HaveAPI::Validators::Exclusion.new(:exclude, {
          values: %w(one two three)
      })
    end

    include_examples :all
  end
end

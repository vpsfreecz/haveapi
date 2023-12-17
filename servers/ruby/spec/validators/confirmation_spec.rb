describe HaveAPI::Validators::Confirmation do
  shared_examples(:all) do
    it 'accepts the same value' do
      expect(@v.validate('foo', {other_param: 'foo'})).to be true
    end

    it "rejects a different value" do
      expect(@v.validate('bar', {other_param: 'foo'})).to be false
    end
  end

  context 'short form' do
    before(:each) do
      @v = HaveAPI::Validators::Confirmation.new(:confirm, :other_param)
    end

    include_examples :all
  end

  context 'full form' do
    before(:each) do
      @v = HaveAPI::Validators::Confirmation.new(:confirm, {
        param: :other_param
      })
    end

    include_examples :all
  end

  context 'with equal = false' do
    before(:each) do
      @v = HaveAPI::Validators::Confirmation.new(:confirm, {
        param: :other_param,
        equal: false
      })
    end

    it 'rejects the same value' do
      expect(@v.validate('foo', {other_param: 'foo'})).to be false
    end

    it 'accepts a different value' do
      expect(@v.validate('bar', {other_param: 'foo'})).to be true
    end
  end
end

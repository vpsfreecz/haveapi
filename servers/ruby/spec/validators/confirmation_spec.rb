describe HaveAPI::Validators::Confirmation do
  shared_examples('all') do
    it 'accepts the same value' do
      expect(validator.validate('foo', { other_param: 'foo' })).to be true
    end

    it 'rejects a different value' do
      expect(validator.validate('bar', { other_param: 'foo' })).to be false
    end
  end

  context 'with short form' do
    let(:validator) { described_class.new(:confirm, :other_param) }

    it_behaves_like 'all'
  end

  context 'with full form' do
    let(:validator) do
      described_class.new(:confirm, {
        param: :other_param
      })
    end

    it_behaves_like 'all'
  end

  context 'with equal = false' do
    let(:validator) do
      described_class.new(:confirm, {
        param: :other_param,
        equal: false
      })
    end

    it 'rejects the same value' do
      expect(validator.validate('foo', { other_param: 'foo' })).to be false
    end

    it 'accepts a different value' do
      expect(validator.validate('bar', { other_param: 'foo' })).to be true
    end
  end
end

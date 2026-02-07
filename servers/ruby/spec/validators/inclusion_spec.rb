describe HaveAPI::Validators::Inclusion do
  shared_examples('all') do
    it 'accepts a listed value' do
      expect(validator.valid?('one')).to be true
      expect(validator.valid?('two')).to be true
      expect(validator.valid?('three')).to be true
    end

    it 'rejects an unlisted value' do
      expect(validator.valid?('zero')).to be false
      expect(validator.valid?('four')).to be false
    end
  end

  [
    %w[one two three],
    {
      one: 'Fancy one',
      two: 'Fancy two',
      three: 'Fancy three'
    }
  ].each do |include|
    context "with include as a '#{include.class}'" do
      context 'with short form' do
        let(:validator) { described_class.new(:include, %w[one two three]) }

        it_behaves_like 'all'
      end

      context 'with full form' do
        let(:validator) do
          described_class.new(:include, {
            values: %w[one two three]
          })
        end

        it_behaves_like 'all'
      end
    end
  end
end

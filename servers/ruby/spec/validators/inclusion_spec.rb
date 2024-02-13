describe HaveAPI::Validators::Inclusion do
  shared_examples(:all) do
    it 'accepts a listed value' do
      expect(@v.valid?('one')).to be true
      expect(@v.valid?('two')).to be true
      expect(@v.valid?('three')).to be true
    end

    it 'rejects an unlisted value' do
      expect(@v.valid?('zero')).to be false
      expect(@v.valid?('four')).to be false
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
      context 'short form' do
        before(:each) do
          @v = HaveAPI::Validators::Inclusion.new(:include, %w[one two three])
        end

        include_examples :all
      end

      context 'full form' do
        before(:each) do
          @v = HaveAPI::Validators::Inclusion.new(:include, {
            values: %w[one two three]
          })
        end

        include_examples :all
      end
    end
  end
end

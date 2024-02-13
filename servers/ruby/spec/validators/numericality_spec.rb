describe HaveAPI::Validators::Numericality do
  it 'cannot be both even and odd at the same time' do
    expect do
      HaveAPI::Validators::Numericality.new(:number, { odd: true, even: true })
    end.to raise_error(RuntimeError)
  end

  it 'checks minimum' do
    v = HaveAPI::Validators::Numericality.new(:number, { min: 5 })
    expect(v.valid?(4)).to be false
    expect(v.valid?(5)).to be true
    expect(v.valid?(6)).to be true
  end

  it 'checks maximum' do
    v = HaveAPI::Validators::Numericality.new(:number, { max: 50 })
    expect(v.valid?(100)).to be false
    expect(v.valid?(51)).to be false
    expect(v.valid?(50)).to be true
    expect(v.valid?(40)).to be true
  end

  it 'checks that x % y = 0' do
    v = HaveAPI::Validators::Numericality.new(:number, { mod: 2 })
    expect(v.valid?(3)).to be false
    expect(v.valid?(15)).to be false
    expect(v.valid?(0)).to be true
    expect(v.valid?(2)).to be true
    expect(v.valid?(48)).to be true
  end

  it 'checks that the number is in a step' do
    v = HaveAPI::Validators::Numericality.new(:number, { step: 3 })
    expect(v.valid?(4)).to be false
    expect(v.valid?(14)).to be false
    expect(v.valid?(0)).to be true
    expect(v.valid?(3)).to be true
    expect(v.valid?(6)).to be true
    expect(v.valid?(9)).to be true
  end

  it 'checks that the number is in a step with a minimum' do
    v = HaveAPI::Validators::Numericality.new(:number, { min: 5, step: 3 })
    expect(v.valid?(0)).to be false
    expect(v.valid?(3)).to be false
    expect(v.valid?(4)).to be false
    expect(v.valid?(12)).to be false
    expect(v.valid?(15)).to be false
    expect(v.valid?(5)).to be true
    expect(v.valid?(8)).to be true
    expect(v.valid?(11)).to be true
    expect(v.valid?(14)).to be true
  end

  it 'checks that the number is even' do
    v = HaveAPI::Validators::Numericality.new(:number, { even: true })
    expect(v.valid?(1)).to be false
    expect(v.valid?(3)).to be false
    expect(v.valid?(0)).to be true
    expect(v.valid?(2)).to be true
  end

  it 'checks that the number is odd' do
    v = HaveAPI::Validators::Numericality.new(:number, { odd: true })
    expect(v.valid?(1)).to be true
    expect(v.valid?(3)).to be true
    expect(v.valid?(0)).to be false
    expect(v.valid?(2)).to be false
  end

  it 'checks number as string' do
    v = HaveAPI::Validators::Numericality.new(:number, { min: 5 })
    expect(v.valid?('5')).to be true
  end

  it 'rejects a string that is not a number' do
    v = HaveAPI::Validators::Numericality.new(:number, { min: 5 })
    expect(v.valid?('abc')).to be false
  end
end

describe HaveAPI::Validators::Length do
  it 'does not allow to mix min/max with equals' do
    expect do
      HaveAPI::Validators::Length.new(:length, {min: 33, equals: 42})
    end.to raise_error(RuntimeError)
  end
  
  it 'requires one of min, max or equals' do
    expect do
      HaveAPI::Validators::Length.new(:length, {})
    end.to raise_error(RuntimeError)
  end

  it 'checks minimum' do
    v = HaveAPI::Validators::Length.new(:length, {min: 2})
    expect(v.valid?('a'*1)).to be false
    expect(v.valid?('a'*2)).to be true
    expect(v.valid?('a'*33)).to be true
  end
  
  it 'checks maximum' do
    v = HaveAPI::Validators::Length.new(:length, {max: 5})
    expect(v.valid?('a'*4)).to be true
    expect(v.valid?('a'*5)).to be true
    expect(v.valid?('a'*6)).to be false
    expect(v.valid?('a'*11)).to be false
  end

  it 'checks range' do
    v = HaveAPI::Validators::Length.new(:length, {min: 3, max: 6})
    expect(v.valid?('a'*2)).to be false
    expect(v.valid?('a'*3)).to be true
    expect(v.valid?('a'*4)).to be true
    expect(v.valid?('a'*5)).to be true
    expect(v.valid?('a'*6)).to be true
    expect(v.valid?('a'*7)).to be false
  end

  it 'check a specific length' do
    v = HaveAPI::Validators::Length.new(:length, {equals: 4})
    expect(v.valid?('a'*2)).to be false
    expect(v.valid?('a'*4)).to be true
    expect(v.valid?('a'*5)).to be false
  end
end

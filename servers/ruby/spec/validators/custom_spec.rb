describe HaveAPI::Validators::Custom do
  it 'always passes' do
    v = HaveAPI::Validators::Custom.new(:validate, 'some custom validation')
    expect(v.valid?('WHATEVER')).to be true
  end
end

describe HaveAPI::Common do
  class Test1 < HaveAPI::Common
    has_attr :attr1
    has_attr :attr2, 42
  end

  it 'defines attributes' do
    expect(Test1.attr1).to be_nil
    expect(Test1.attr2).to eq(42)
  end

  class Test2 < HaveAPI::Common
    has_attr :attr1
    has_attr :attr2, 42
  end

  it 'sets attributes' do
    Test2.attr1 'val1'
    Test2.attr2 663

    expect(Test2.attr1).to eq('val1')
    expect(Test2.attr2).to eq(663)
  end

  class Test3 < HaveAPI::Common
    has_attr :attr1
    has_attr :attr2, 42
    has_attr :attr3

    attr1 'foo'
    attr2 :bar

    def self.inherited(subclass)
      super
      inherit_attrs(subclass)
    end
  end

  class SubTest3 < Test3
    attr3 'bar'
  end

  it 'inherites attributes' do
    expect(SubTest3.attr1).to eq('foo')
    expect(SubTest3.attr2).to eq(:bar)
    expect(SubTest3.attr3).to eq('bar')
  end
end

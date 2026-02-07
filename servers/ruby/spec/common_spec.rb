module CommonSpec
  class Test1 < HaveAPI::Common
    has_attr :attr1
    has_attr :attr2, 42
  end

  class Test2 < HaveAPI::Common
    has_attr :attr1
    has_attr :attr2, 42
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
end

describe HaveAPI::Common do

  it 'defines attributes' do
    expect(CommonSpec::Test1.attr1).to be_nil
    expect(CommonSpec::Test1.attr2).to eq(42)
  end

  it 'sets attributes' do
    CommonSpec::Test2.attr1 'val1'
    CommonSpec::Test2.attr2 663

    expect(CommonSpec::Test2.attr1).to eq('val1')
    expect(CommonSpec::Test2.attr2).to eq(663)
  end

  it 'inherites attributes' do
    expect(CommonSpec::SubTest3.attr1).to eq('foo')
    expect(CommonSpec::SubTest3.attr2).to eq(:bar)
    expect(CommonSpec::SubTest3.attr3).to eq('bar')
  end
end

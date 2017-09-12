describe HaveAPI::Resource do
  class PluralTest < HaveAPI::Resource
    
  end

  class SingularTest < HaveAPI::Resource
    singular true
  end

  it 'has correct obj_type' do
    expect(PluralTest.obj_type).to eq(:resource)
    expect(SingularTest.obj_type).to eq(:resource)
  end

  it 'has plural name' do
    expect(PluralTest.resource_name).to eq('plural_tests')
  end

  it 'has singular name' do
    expect(SingularTest.resource_name).to eq('singular_test')
  end

  class ComplexTest < HaveAPI::Resource
    class Index < HaveAPI::Actions::Default::Index ; end
    class Show < HaveAPI::Actions::Default::Show ; end
    class Create < HaveAPI::Actions::Default::Create ; end
    class Dummy ; end

    class SubResource < HaveAPI::Resource
      class Index < HaveAPI::Actions::Default::Index ; end
      class Show < HaveAPI::Actions::Default::Show ; end
    end
  end

  it 'iterates over actions' do
    actions = []

    ComplexTest.actions do |a|
      actions << a
    end

    expect(actions).to contain_exactly(
      ComplexTest::Index,
      ComplexTest::Show,
      ComplexTest::Create
    )
  end

  it 'iterates over resources' do
    resources = []

    ComplexTest.resources do |r|
      resources << r
    end

    expect(resources).to contain_exactly(ComplexTest::SubResource)
  end

  it 'defines and returns resource-wide params' do
    ComplexTest.params(:name) { 'executed' }
    expect(ComplexTest.params(:name).call).to eq('executed')
  end
end

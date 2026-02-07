module ResourceSpec
  class PluralTest < HaveAPI::Resource
  end

  class SingularTest < HaveAPI::Resource
    singular true
  end

  class ComplexTest < HaveAPI::Resource
    class Index < HaveAPI::Actions::Default::Index; end
    class Show < HaveAPI::Actions::Default::Show; end
    class Create < HaveAPI::Actions::Default::Create; end

    class SubResource < HaveAPI::Resource
      class Index < HaveAPI::Actions::Default::Index; end
      class Show < HaveAPI::Actions::Default::Show; end
    end
  end
end

describe HaveAPI::Resource do
  it 'has correct obj_type' do
    expect(ResourceSpec::PluralTest.obj_type).to eq(:resource)
    expect(ResourceSpec::SingularTest.obj_type).to eq(:resource)
  end

  context 'when resource is plural' do
    it 'has singular resource name' do
      expect(ResourceSpec::PluralTest.resource_name).to eq('PluralTest')
    end

    it 'has plural rest name' do
      expect(ResourceSpec::PluralTest.rest_name).to eq('plural_tests')
    end
  end

  context 'when resource is singular' do
    it 'has singular resource name' do
      expect(ResourceSpec::SingularTest.resource_name).to eq('SingularTest')
    end

    it 'has singular rest name' do
      expect(ResourceSpec::SingularTest.rest_name).to eq('singular_test')
    end
  end

  it 'iterates over actions' do
    actions = []

    ResourceSpec::ComplexTest.actions do |a|
      actions << a
    end

    expect(actions).to contain_exactly(
      ResourceSpec::ComplexTest::Index,
      ResourceSpec::ComplexTest::Show,
      ResourceSpec::ComplexTest::Create
    )
  end

  it 'iterates over resources' do
    resources = []

    ResourceSpec::ComplexTest.resources do |r|
      resources << r
    end

    expect(resources).to contain_exactly(ResourceSpec::ComplexTest::SubResource)
  end

  it 'defines and returns resource-wide params' do
    ResourceSpec::ComplexTest.params(:name) { 'executed' }
    expect(ResourceSpec::ComplexTest.params(:name).call).to eq('executed')
  end
end

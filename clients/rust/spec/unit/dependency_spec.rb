require 'spec_helper'

describe HaveAPI::RustClient::Generator do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:gemspec) { Gem::Specification.load(File.join(root, 'haveapi-rust-client.gemspec')) }

  it 'declares the Fiddle runtime dependency used for atomic generated-tree replacement' do
    dependency = gemspec.runtime_dependencies.find { |item| item.name == 'fiddle' }
    expect(dependency).not_to be_nil
    expect(dependency.requirement.satisfied_by?(Gem::Version.new('1.1.8'))).to be(true)
    expect(dependency.requirement.satisfied_by?(Gem::Version.new('1.1.7'))).to be(false)
    expect(gemspec.required_ruby_version.satisfied_by?(Gem::Version.new('3.2.0'))).to be(true)
  end

  it 'locks and activates Fiddle from the component bundle rather than a default gem' do
    lock = Bundler::LockfileParser.new(File.read(File.join(root, 'Gemfile.lock')))
    locked = lock.specs.find { |item| item.name == 'fiddle' }
    expect(locked).not_to be_nil
    expect(locked.version.to_s).to eq('1.1.8')
    selected = Gem.loaded_specs.fetch('fiddle')
    expect(selected.version).to eq(locked.version)
    expect(selected.default_gem?).to be(false)
    expect(defined?(Fiddle::Importer)).to eq('constant')
  end
end

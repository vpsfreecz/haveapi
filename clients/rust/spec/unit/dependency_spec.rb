require 'spec_helper'
require 'rubygems/package'

describe HaveAPI::RustClient::Generator do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:gemspec) { Gem::Specification.load(File.join(root, 'haveapi-rust-client.gemspec')) }
  let(:fiddle_dependency) { gemspec.runtime_dependencies.find { |item| item.name == 'fiddle' } }

  it 'declares the Fiddle runtime dependency used for atomic generated-tree replacement' do
    dependency = fiddle_dependency
    expect(dependency).not_to be_nil
    expect(dependency.requirement.satisfied_by?(Gem::Version.new('1.1.8'))).to be(true)
    expect(dependency.requirement.satisfied_by?(Gem::Version.new('1.1.7'))).to be(false)
    expect(gemspec.required_ruby_version.satisfied_by?(Gem::Version.new('3.2.0'))).to be(true)
  end

  it 'activates the prepared compatible Fiddle version without default-gem fallback' do
    lock = Bundler::LockfileParser.new(File.read(File.join(root, 'Gemfile.lock')))
    locked = lock.specs.find { |item| item.name == 'fiddle' }
    expect(locked).not_to be_nil
    expect(fiddle_dependency.requirement.satisfied_by?(locked.version)).to be(true)
    selected = Gem.loaded_specs.fetch('fiddle')
    expect(selected.version).to eq(locked.version)
    expect(selected.default_gem?).to be(false)
    expect(defined?(Fiddle::Importer)).to eq('constant')
  end

  def package_source(destination, include_lock:)
    paths = (gemspec.files + ['haveapi-rust-client.gemspec']).uniq
    paths -= ['Gemfile.lock'] unless include_lock
    paths.each do |path|
      target = File.join(destination, path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(root, path), target)
    end
    Gem::Specification.load(File.join(destination, 'haveapi-rust-client.gemspec'))
  end

  it 'packages the actual prepared Ruby lock and embedded runtime without the private Cargo harness' do
    Dir.mktmpdir('rust-lock-package-') do |directory|
      source = File.join(directory, 'source')
      spec = package_source(source, include_lock: true)
      output = File.join(directory, 'generator.gem')
      Dir.chdir(source) { Gem::Package.build(spec, false, false, output) }
      package = Gem::Package.new(output)
      expect(package.contents).to include('Gemfile.lock', 'runtime/src/runtime/mod.rs')
      expect(package.contents).not_to include('runtime/Cargo.lock', 'runtime/Cargo.toml')
      expect(package.contents).not_to include(a_string_starting_with('spec/'))
      extracted = File.join(directory, 'extracted')
      package.extract_files(extracted)
      expect(File.binread(File.join(extracted, 'Gemfile.lock'))).to eq(File.binread(File.join(root, 'Gemfile.lock')))
    end
  end

  it 'loads an unprepared source gemspec but refuses to package without its local Ruby lock' do
    Dir.mktmpdir('rust-lock-missing-') do |directory|
      source = File.join(directory, 'source')
      spec = package_source(source, include_lock: false)
      expect(spec).not_to be_nil
      expect(spec.files).to include('Gemfile.lock')
      output = File.join(directory, 'generator.gem')
      expect { Dir.chdir(source) { Gem::Package.build(spec, false, false, output) } }
        .to raise_error(Gem::InvalidSpecificationException, /Gemfile\.lock/)
      expect(File.exist?(output)).to be(false)
    end
  end
end

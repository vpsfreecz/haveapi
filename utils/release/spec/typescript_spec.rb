require 'rspec'
require_relative '../typescript_smoke'

RSpec.describe HaveAPI::Release::TypeScriptSmoke do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:artifacts) { HaveAPI::Release::Artifacts.new(root) }
  let(:tmp) { Dir.mktmpdir('haveapi-typescript-release-spec-') }
  let(:lock) { File.read(File.join(root, 'clients/typescript/Gemfile.lock')) }

  after { FileUtils.remove_entry(tmp) }

  def build_gem(component, name, missing: nil, corrupt: nil, extra: nil, &block)
    source = File.join(tmp, component)
    FileUtils.mkdir_p(source)
    spec = Dir.chdir(File.join(root, component)) { Gem::Specification.load("#{name}.gemspec").dup }
    spec.files.each do |path|
      target = File.join(source, path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(root, component, path), target)
    end
    if missing
      spec.files -= [missing]
      spec.executables = [] if missing.start_with?('bin/')
    end
    File.write(File.join(source, corrupt), 'corrupt payload') if corrupt
    if extra
      File.write(File.join(source, extra), 'unexpected payload')
      spec.files += [extra]
    end
    block&.call(spec)
    path = File.join(tmp, "#{name}-#{artifacts.version}.gem")
    Dir.chdir(source) { Gem::Package.build(spec, false, false, path) }
    Gem::Package.new(path)
  end

  def typescript_gem(**options, &block)
    build_gem('clients/typescript', 'haveapi-typescript-client', **options, &block)
  end

  it 'retains five gems in client-first order and ten dependency locks' do
    expect(HaveAPI::Release::GEMS.keys).to eq(%w[haveapi-client haveapi haveapi-go-client haveapi-rust-client haveapi-typescript-client])
    expect(artifacts.names).to include("haveapi-typescript-client-#{artifacts.version}.gem")
    expect(HaveAPI::Release::Artifacts::LOCK_PATHS.length).to eq(10)
    expect(HaveAPI::Release::Artifacts::LOCK_PATHS).to include('clients/typescript/Gemfile.lock')
  end

  it 'accepts the prepared TypeScript lock without loading a component bundle' do
    expect { artifacts.check_typescript_lock(lock) }.not_to raise_error
  end

  ['    haveapi-client', '    haveapi-typescript-client', '      haveapi-client', '  haveapi-client', '  haveapi-typescript-client'].each do |entry|
    it "rejects stale TypeScript lock identity or requirement at #{entry.inspect}" do
      stale = lock.sub(/^#{entry} \([^)]+\)$/, "#{entry} (999.0.0)")
      expect { artifacts.check_typescript_lock(stale) }.to raise_error(HaveAPI::Release::Error, %r{typescript/Gemfile.lock})
    end
  end

  [nil, '', 'not a lock'].each do |content|
    it "rejects malformed retained TypeScript lock #{content.inspect}" do
      expect { artifacts.check_typescript_lock(content) }.to raise_error(HaveAPI::Release::Error, %r{typescript/Gemfile.lock})
    end
  end

  it 'accepts source-exact TypeScript content including every source digest input' do
    package = typescript_gem
    expect(package.contents).to include('Gemfile', 'Rakefile', 'haveapi-typescript-client.gemspec')
    expect { artifacts.inspect_typescript(package) }.not_to raise_error
  end

  %w[Gemfile Rakefile haveapi-typescript-client.gemspec bin/haveapi-typescript-client].each do |path|
    it "rejects missing TypeScript source input #{path}" do
      expect { artifacts.inspect_typescript(typescript_gem(missing: path)) }
        .to raise_error(HaveAPI::Release::Error, /missing or unexpected/)
    end
  end

  it 'rejects extra packaged content' do
    expect { artifacts.inspect_typescript(typescript_gem(extra: 'unexpected.txt')) }
      .to raise_error(HaveAPI::Release::Error, /missing or unexpected/)
  end

  it 'rejects corrupt template bytes' do
    expect { artifacts.inspect_typescript(typescript_gem(corrupt: 'template/action.ts.erb')) }
      .to raise_error(HaveAPI::Release::Error, /differs from source/)
  end

  it 'rejects an undeclared executable' do
    expect { artifacts.inspect_typescript(typescript_gem { |spec| spec.executables = [] }) }
      .to raise_error(HaveAPI::Release::Error, /missing or unexpected/)
  end

  it 'rejects the wrong Ruby floor or shared-client requirement' do
    [->(spec) { spec.required_ruby_version = '>= 3.0' },
     ->(spec) { spec.dependencies.clear }].each do |change|
      expect { artifacts.inspect_typescript(typescript_gem(&change)) }
        .to raise_error(HaveAPI::Release::Error, /Ruby floor or shared-client dependency/)
    end
  end

  it 'verifies retained TypeScript inputs in a cold tools-only checkout without local locks' do
    package = typescript_gem
    File.write(File.join(tmp, 'VERSION'), artifacts.version)
    candidate = HaveAPI::Release::Artifacts.new(tmp)
    allow(candidate).to receive(:source).and_return('a' * 40)
    allow(candidate).to receive(:inspect_packages) { candidate.inspect_typescript(package) }
    files = candidate.names.to_h do |name|
      path = File.join(tmp, name)
      File.write(path, name) unless File.file?(path)
      [name, Digest::SHA256.file(path).hexdigest]
    end
    locks = HaveAPI::Release::Artifacts::LOCK_PATHS.to_h do |path|
      [path, case path
             when 'clients/typescript/Gemfile.lock' then lock
             when 'clients/rust/Gemfile.lock' then File.read(File.join(root, path))
             else "retained #{path}"
             end]
    end
    manifest = { schema: 1, source: candidate.source, version: candidate.version, tag: candidate.tag,
                 run_id: ENV.fetch('GITHUB_RUN_ID', 'local'), files:, dependency_locks: locks }
    File.write(File.join(tmp, 'release-manifest.json'), JSON.generate(manifest))
    expect(File).not_to exist(File.join(tmp, 'clients/typescript/Gemfile.lock'))
    expect { candidate.verify(tmp) }.not_to raise_error
    locks['clients/typescript/Gemfile.lock'] = lock.sub("haveapi-typescript-client (#{artifacts.version})", 'haveapi-typescript-client (999.0.0)')
    File.write(File.join(tmp, 'release-manifest.json'), JSON.generate(manifest))
    expect { candidate.verify(tmp) }.to raise_error(HaveAPI::Release::Error, %r{typescript/Gemfile.lock})
  end

  it 'rejects missing and corrupt shared schema code in the Ruby client gem' do
    path = 'lib/haveapi/schema/snapshot.rb'
    expect { artifacts.inspect_shared_schema(build_gem('clients/ruby', 'haveapi-client', missing: path)) }
      .to raise_error(HaveAPI::Release::Error, /missing shared schema/)
    expect { artifacts.inspect_shared_schema(build_gem('clients/ruby', 'haveapi-client', corrupt: path)) }
      .to raise_error(HaveAPI::Release::Error, /differs from source/)
  end

  it 'extracts both artifacts and removes ambient load overrides before invoking the consumer' do
    typescript_gem
    build_gem('clients/ruby', 'haveapi-client')
    runtime = File.join(tmp, 'runtime')
    FileUtils.mkdir_p(File.join(runtime, 'dist'))
    File.write(File.join(runtime, 'package.json'), JSON.generate(name: 'haveapi-client', version: '0.30.2'))
    File.write(File.join(runtime, 'dist/haveapi-client.js'), 'runtime fixture')
    allow(Digest::SHA256).to receive(:file).and_call_original
    allow(Digest::SHA256).to receive(:file).with(File.join(runtime, 'dist/haveapi-client.js'))
                                           .and_return(double(hexdigest: HaveAPI::Release::TypeScriptSmoke::RUNTIME_SHA256))
    allow(HaveAPI::Release).to receive(:capture).and_return('["source",{}]')
    allow(HaveAPI::Release).to receive(:run) do |env, ruby, disable, shared_flag, shared_lib, flag, library, expression, _script, extracted, shared, version, identity, prepared_runtime, compiler, **options|
      expect([ruby, disable, shared_flag, flag, expression]).to eq([RbConfig.ruby, '--disable-gems', '-I', '-I', '-e'])
      expect(shared_lib).to eq(File.join(shared, 'lib'))
      expect(library).to eq(File.join(extracted, 'lib'))
      expect(File.realpath(extracted)).not_to start_with(root)
      expect(File.read(File.join(shared_lib, 'haveapi/schema.rb'))).to eq(File.read(File.join(root, 'clients/ruby/lib/haveapi/schema.rb')))
      expect(File).to exist(File.join(extracted, 'Gemfile'))
      expect(env).to include('RUBYOPT' => nil, 'RUBYLIB' => nil, 'RUBYGEMS_GEMDEPS' => nil, 'NODE_PATH' => nil)
      ENV.keys.grep(/\ABUNDLE_/).each { |key| expect(env.fetch(key)).to be_nil }
      expect([version, identity, prepared_runtime]).to eq([artifacts.version, '["source",{}]', runtime])
      expect(compiler).to eq(File.join(root, 'clients/js/node_modules/typescript/bin/tsc'))
      expect(options.fetch(:chdir)).to eq(File.dirname(extracted))
    end
    described_class.run(artifacts, tmp, runtime)
    expect(HaveAPI::Release).to have_received(:run).once
  end
end

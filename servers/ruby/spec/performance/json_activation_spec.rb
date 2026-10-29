require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../../benchmarks/performance_compare'
require_relative 'support/samples'

describe HaveAPI::Performance do
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:comparison) { File.join(root, 'servers/ruby/benchmarks/performance_compare.rb') }

  def with_newer_json
    Dir.mktmpdir('haveapi-extra-json-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'specifications'))
      library = File.join(directory, 'gems/json-3.1.0/lib')
      FileUtils.mkdir_p(library)
      File.write(File.join(library, 'json.rb'), "module JSON; VERSION = '3.1.0'; end\n")
      spec = Gem::Specification.new do |gem|
        gem.name = 'json'
        gem.version = '3.1.0'
        gem.summary = 'Owned activation control'
        gem.authors = ['Fixture']
      end
      File.write(File.join(directory, 'specifications/json-3.1.0.gemspec'), spec.to_ruby)
      environment = ENV.keys.grep(/\ABUNDLE|\ABUNDLER|\ARUBY(?:OPT|LIB)\z/).to_h { |key| [key, nil] }
      environment.merge!('GEM_HOME' => directory,
                         'GEM_PATH' => [directory, Gem.loaded_specs.fetch('json').base_dir, Gem.default_dir].uniq.join(File::PATH_SEPARATOR))
      yield directory, environment
    end
  end

  def with_console_versions(pinned: true)
    with_newer_json do |directory, environment|
      (pinned ? %w[0.9.4 99.0.0] : ['99.0.0']).each do |version|
        library = File.join(directory, "gems/io-console-#{version}/lib/io")
        FileUtils.mkdir_p(library)
        File.write(File.join(library, 'console.rb'), "CONSOLE_ACTIVATION_CONTROL = #{version.inspect}\n")
        spec = Gem::Specification.new do |gem|
          gem.name = 'io-console'
          gem.version = version
          gem.summary = 'Owned worker activation control'
          gem.authors = ['Fixture']
        end
        File.write(File.join(directory, "specifications/io-console-#{version}.gemspec"), spec.to_ruby)
      end
      yield directory, environment
    end
  end

  it 'activates the exact frozen console before source loading despite a newer visible version' do
    with_console_versions do |_directory, environment|
      program = <<~RUBY
        require #{File.join(root, 'servers/ruby/benchmarks/endpoints.rb').inspect}
        visible = Gem::Specification.find_all_by_name('io-console').map { |spec| spec.version.to_s }
        begin
          HaveAPI::Performance::Worker.new('benchmark' => true, 'source_root' => '/missing-worker-source').run
        rescue Errno::ENOENT
          puts JSON.generate(visible: visible, loaded: Gem.loaded_specs.fetch('io-console').version.to_s,
                             required: CONSOLE_ACTIVATION_CONTROL, pp_loaded: $LOADED_FEATURES.any? { |path| path.end_with?('/pp.rb') })
        end
      RUBY
      output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
      expect(status).to be_success, errors
      result = JSON.parse(output)
      expect(result.fetch('visible')).to include('99.0.0')
      expect(result).to include('loaded' => '0.9.4', 'required' => '0.9.4', 'pp_loaded' => false)
      budgets = JSON.parse(File.read(File.join(root, 'servers/ruby/benchmarks/performance_budgets.json')))
      expect(budgets.fetch('environment').values.map { |value| value.fetch('gems').fetch('io-console').fetch('version') })
        .to all(eq(result.fetch('loaded')))
      lock = Bundler::LockfileParser.new(File.read(File.join(root, 'servers/ruby/benchmarks/Gemfile.lock')))
      expect(lock.specs.find { |spec| spec.name == 'io-console' }.version.to_s).to eq(result.fetch('loaded'))
    end
  end

  it 'leaves ordinary and non-Boolean worker console activation unchanged' do
    with_console_versions(pinned: false) do |_directory, environment|
      program = <<~RUBY
        require #{File.join(root, 'servers/ruby/benchmarks/endpoints.rb').inspect}
        before = Gem.loaded_specs['io-console']&.version&.to_s
        [nil, false, 'true', 1].each do |flag|
          HaveAPI::Performance::Worker.new('benchmark' => flag).send(:activate_benchmark_console)
        end
        puts JSON.generate(before: before, after: Gem.loaded_specs['io-console']&.version&.to_s,
                           required: defined?(CONSOLE_ACTIVATION_CONTROL))
      RUBY
      output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
      expect(status).to be_success, errors
      expect(JSON.parse(output)).to include('before' => nil, 'after' => nil, 'required' => nil)
    end
  end

  it 'fails frozen workers clearly when the console version is missing or already conflicting' do
    %w[missing conflicting].each do |control|
      with_console_versions(pinned: control == 'conflicting') do |directory, environment|
        program = <<~RUBY
          require #{File.join(root, 'servers/ruby/benchmarks/endpoints.rb').inspect}
          Gem.use_paths(#{directory.inspect}, [#{directory.inspect}])
          gem 'io-console', '= 99.0.0' if #{control.inspect} == 'conflicting'
          HaveAPI::Performance::Worker.new('benchmark' => true).send(:activate_benchmark_console)
        RUBY
        _output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
        expect(status).not_to be_success
        expect(errors).to include('io-console', '0.9.4')
        expect(errors).to include(control == 'missing' ? 'Could not find' : 'already activated io-console-99.0.0')
      end
    end
  end

  it 'loads the native calibrated version in each public entry despite a newer visible gem' do
    with_newer_json do |_directory, environment|
      [comparison, File.join(root, 'utils/performance_ci.rb'), File.join(root, 'servers/ruby/benchmarks/endpoints.rb')].each do |entry|
        program = <<~RUBY
          visible = Gem::Specification.find_all_by_name('json').map { |spec| spec.version.to_s }
          require #{entry.inspect}
          puts JSON.generate(visible: visible, loaded: Gem.loaded_specs.fetch('json').version.to_s,
                             parser: JSON::Ext::Parser.name, parsed: JSON.parse('{"value":42}'))
        RUBY
        output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
        expect(status).to be_success, errors
        result = JSON.parse(output)
        expect(result.fetch('visible')).to include('3.1.0')
        expect(result).to include('loaded' => '2.21.2', 'parser' => 'JSON::Ext::Parser', 'parsed' => { 'value' => 42 })
      end
    end
  end

  it 'uses the same activation in the neutral worker serialization path' do
    with_newer_json do |_directory, environment|
      program = <<~RUBY
        require #{File.join(root, 'servers/ruby/benchmarks/endpoints.rb').inspect}
        HaveAPI::Performance::Worker.define_method(:run) { { json_version: Gem.loaded_specs.fetch('json').version.to_s } }
        exit HaveAPI::Performance::CLI.new(['worker']).execute
      RUBY
      output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program, stdin_data: '{}')
      expect(status).to be_success, errors
      expect(JSON.parse(output)).to include('json_version' => '2.21.2')
    end
  end

  it 'refuses an already activated incompatible version instead of weakening the environment' do
    with_newer_json do |_directory, environment|
      program = "gem 'json', '= 3.1.0'; require 'json'; require #{comparison.inspect}"
      _output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
      expect(status).not_to be_success
      expect(errors).to include('json', '2.21.2', 'already activated json-3.1.0')
    end
  end

  it 'reports the required version when the calibrated gem is missing' do
    with_newer_json do |directory, environment|
      environment['GEM_PATH'] = directory
      program = "Gem.use_paths(#{directory.inspect}, [#{directory.inspect}]); require #{comparison.inspect}"
      _output, errors, status = Open3.capture3(environment, RbConfig.ruby, '-e', program)
      expect(status).not_to be_success
      expect(errors).to include('json', '2.21.2', '3.1.0')
      expect(errors).to include('Could not find')
    end
  end

  it 'declares the calibrated JSON constraint in all three fresh development bundles' do
    expected = JSON.parse(File.read(File.join(root, 'servers/ruby/benchmarks/performance_budgets.json')))
                   .fetch('environment').fetch('weekly').fetch('gems').fetch('json').fetch('version')
    expect(HaveAPI::Performance::JSON_VERSION).to eq(expected)
    with_newer_json do |directory, environment|
      HaveAPI::Performance::Release::JSON_GEMFILES.each do |path|
        definition = Bundler::Dsl.evaluate(File.join(root, path), nil, {})
        expect(definition.dependencies.select { |dependency| dependency.name == 'json' }.map { |dependency| dependency.requirement.to_s }).to eq(["= #{expected}"])
      end
      # Resolve only this installed constraint in an owned lockless fixture.
      # No repository lock or external dependency is resolved or installed.
      file = File.join(directory, 'Gemfile')
      File.write(file, "source 'https://rubygems.org'\ngem 'json', '= #{expected}'\n")
      _output, errors, status = Open3.capture3(environment, RbConfig.ruby, Gem.bin_path('bundler', 'bundle'), 'lock', '--local', '--gemfile', file)
      expect(status).to be_success, errors
      expect(File.read("#{file}.lock")).to include("json (#{expected})", "json (= #{expected})")
      expect(File.read("#{file}.lock")).not_to include('json (3.1.0)')
    end
  end

  it 'canonicalizes only the exact known JSON preparation declaration and binds raw replay evidence' do
    release = HaveAPI::Performance::Release
    old = release::JSON_GEMFILES.to_h { |path| [path, "source 'https://rubygems.org'\n"] }
    pinned = old.transform_values { |text| "#{text}  gem 'json', '= 2.21.2'\n" }
    receipt = release.json_preparation(pinned)
    expect(receipt.fetch('normalized_contents')).to eq(old)
    expect(receipt.fetch('raw_sha256')).not_to eq(receipt.fetch('normalized_sha256'))
    expect(receipt.fetch('declarations').values).to all(eq('exact-development-pin'))
    unversioned = old.transform_values { |text| "#{text}  gem 'json'\n" }
    expect(release.json_preparation(unversioned).fetch('normalized_contents')).to eq(old)
    ['3.1.0', '>= 2.21.2'].each do |requirement|
      changed = pinned.transform_values { |text| text.sub('= 2.21.2', requirement) }
      expect { release.json_preparation(changed) }.to raise_error(HaveAPI::Performance::ContractError)
    end
    changed = pinned.merge('Gemfile' => "#{pinned.fetch('Gemfile')}# unrelated comment\ngem 'other'\n")
    expect(release.json_preparation(changed).fetch('normalized_contents')).not_to eq(old)
    inputs = { 'json_preparation' => receipt, 'manifests' => receipt.fetch('normalized_sha256') }
    source = { 'files_sha256' => receipt.fetch('raw_sha256') }
    expect { release.validate_json_preparation(inputs, source) }.not_to raise_error
    %w[raw_sha256 normalized_sha256 declarations].each do |field|
      forged = Marshal.load(Marshal.dump(inputs))
      forged['json_preparation'][field]['Gemfile'] = 'forged'
      expect { release.validate_json_preparation(forged, source) }.to raise_error(HaveAPI::Performance::ContractError)
    end
  end

  it 'replays the exact preparation delta while rejecting other content and raw source changes' do
    release = HaveAPI::Performance::Release
    %w[exact other-content raw-source].each do |control|
      samples, budgets = PerformanceSamples.fixture
      samples.fetch('observations').each_value do |observation|
        next unless observation.fetch('source').fetch('sha') == samples.fetch('candidate_sha')

        contents = observation.fetch('inputs').fetch('json_preparation').fetch('contents')
                              .transform_values { |text| "#{text}  gem 'json', '= 2.21.2'\n" }
        contents['Gemfile'] << "# other content\n" if control == 'other-content'
        receipt = release.json_preparation(contents)
        observation['inputs'].merge!('json_preparation' => receipt, 'manifests' => receipt.fetch('normalized_sha256'))
        samples['sources']['candidate']['files_sha256'].merge!(receipt.fetch('raw_sha256')) unless control == 'raw-source'
      end
      comparator = HaveAPI::Performance::Comparator.new(samples, JSON.parse(budgets), budget_sha256: samples.fetch('budget_sha256'))
      if control == 'exact'
        expect(comparator.compare.fetch('status')).to eq('pass')
      else
        expect { comparator.compare }.to raise_error(HaveAPI::Performance::ContractError)
      end
    end
  end
end

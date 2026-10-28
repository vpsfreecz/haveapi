# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rake'
require 'rbconfig'
require 'rubygems/package'
require 'tmpdir'

describe HaveAPI::Server do
  def required_docs
    %w[json-schema.html protocol.md create-client.md typed-input-validation.md client-examples.md protocol.png]
  end

  before(:context) do
    load File.expand_path('../Rakefile', __dir__)
  end

  def invoke_build
    Rake::Task[:check_doc].reenable
    Rake::Task[:build].reenable
    Rake::Task[:build].invoke
  end

  %i[missing empty].each do |condition|
    it "rejects a direct build with #{condition} shared documentation" do
      Dir.mktmpdir('haveapi-doc-check') do |dir|
        FileUtils.mkdir_p(File.join(dir, 'doc'))
        required_docs.each do |name|
          next if name == 'json-schema.html' && condition == :missing

          content = name == 'json-schema.html' && condition == :empty ? '' : 'document'
          File.write(File.join(dir, 'doc', name), content)
        end

        Dir.chdir(dir) do
          expect do
            expect { invoke_build }.to raise_error(SystemExit) do |error|
              expect(error.status).to eq(1)
            end
          end.to output(/json-schema.html.*Run `make doc`/).to_stderr
        end
      end
    end
  end

  it 'ships and serves shared documentation from the built gem' do
    invoke_build
    gem_path = File.expand_path("../pkg/haveapi-#{HaveAPI::VERSION}.gem", __dir__)

    Dir.mktmpdir('haveapi-package') do |dir|
      Gem::Package.new(gem_path).extract_files(dir)
      required_docs.each do |name|
        expect(File.read(File.join(dir, 'doc', name))).not_to be_empty
      end
      %w[
        lib/haveapi/documentation_context.rb lib/haveapi/documentation_clients.rb
        lib/haveapi/shared_documentation_helpers.rb
        lib/haveapi/views/shared_sidebar.erb lib/haveapi/views/shared_documentation.erb
        lib/haveapi/views/version_page/client_result.erb
        lib/haveapi/public/js/highlight.pack.js lib/haveapi/public/js/highlight-LICENSE
      ].each do |name|
        expect(File.size?(File.join(dir, name))).not_to be_nil
      end

      script = <<~RUBY
        require 'haveapi'
        require 'rack/mock'

        module PackagedAPI
          class Test < HaveAPI::Resource
            version 1
            auth false

            class Index < HaveAPI::Actions::Default::Index
              authorize { allow }
              def exec
                []
              end
            end
          end
        end

        server = HaveAPI::Server.new(PackagedAPI)
        server.use_version(1)
        server.mount('/')
        request = Rack::MockRequest.new(server.app)
        responses = %w[/ /doc /doc/index /doc/index.md /doc/readme /doc/json-schema /doc/protocol.md /doc/create-client.md /doc/client-examples.md /js/highlight-LICENSE].to_h do |path|
          response = request.get(path, 'HTTP_HOST' => 'localhost')
          [path, { status: response.status, type: response.content_type, cache_control: response['Cache-Control'], body: response.body }]
        end
        puts JSON.generate({
          framework: HaveAPI::Server.instance_method(:mount).source_location.first,
          responses: responses
        })
      RUBY

      empty_gem_home = File.join(dir, 'empty-gems')
      original_env = Bundler.original_env.merge('GEM_HOME' => empty_gem_home, 'GEM_PATH' => empty_gem_home)
      allow(Bundler).to receive(:original_env).and_return(original_env)

      # Retain Bundler's resolved gem paths for installations such as vendor/bundle.
      child_env = {
        'GEM_HOME' => Gem.dir,
        'GEM_PATH' => Gem.path.join(File::PATH_SEPARATOR),
        'RUBYLIB' => nil,
        'RUBYOPT' => nil
      }
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(
          child_env,
          RbConfig.ruby, '-I', File.join(dir, 'lib'), '-e', script,
          '-I', File.join(Gem.loaded_specs.fetch('haveapi-client').full_gem_path, 'lib'),
          chdir: dir
        )
      end
      expect(status.success?).to be(true), "Packaged server failed: #{stderr}"
      result = JSON.parse(stdout)
      expect(File.realpath(result.fetch('framework'))).to eq(File.join(dir, 'lib/haveapi/server.rb'))

      {
        '/' => 'API versions',
        '/doc' => 'Server-side implementation',
        '/doc/index' => 'Server-side implementation',
        '/doc/index.md' => 'Server-side implementation',
        '/doc/readme' => 'Server-side implementation',
        '/doc/json-schema' => 'Envelope',
        '/doc/protocol.md' => 'Protocol definition',
        '/doc/create-client.md' => 'Client definition',
        '/doc/client-examples.md' => 'Client examples',
        '/js/highlight-LICENSE' => 'Copyright'
      }.each do |path, heading|
        response = result.fetch('responses').fetch(path)
        expect(response.fetch('status')).to eq(200), "Packaged route failed: #{path}"
        expect(response.fetch('type')).to include('text/html') unless path == '/js/highlight-LICENSE'
        expect(response.fetch('body')).to include(heading)
        next if path == '/js/highlight-LICENSE'

        expect(response.fetch('cache_control')).to eq('private, no-store')
        expect(response.fetch('body')).to include('data-docs', '/js/documentation.js', '/css/documentation.css')
        expect(response.fetch('body')).not_to include('/js/main.js', '/css/bootstrap')
      end
      %w[/doc /doc/index /doc/index.md /doc/readme].each do |path|
        body = result.fetch('responses').fetch(path).fetch('body')
        expect(body).to include('<title>HaveAPI internals · ', 'Server framework features',
                                '<pre><code class="ruby">', 'class User &lt; ActiveRecord::Base')
        menu = body.match(%r{<nav aria-label="Shared documentation">(.*?)</nav>}m)[1]
        expect(menu).not_to include('href="/doc/readme"')
      end
    end
  end
end

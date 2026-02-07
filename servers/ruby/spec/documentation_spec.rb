# frozen_string_literal: true

describe 'Documentation' do
  #
  # Build a minimal API with two versions so we can test:
  # - OPTIONS /?describe=versions and default
  # - OPTIONS /v1/ and /v2/
  # - per-action OPTIONS docs including method disambiguation
  #
  api do
    define_resource(:User) do
      version 1
      desc 'User resource'
      auth false

      # IMPORTANT: use define_action (not `class Index < ...`)
      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        desc 'List users'
        authorize { allow }
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        desc 'Show user'
        authorize { allow }
      end

      define_action(:Update, superclass: HaveAPI::Actions::Default::Update) do
        desc 'Update user'
        authorize { allow }
      end
    end

    define_resource(:Admin) do
      version 2
      desc 'Admin resource'
      auth false

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        desc 'List admins'
        authorize { allow }
      end
    end
  end

  default_version 1

  #
  # Replace `{param}` placeholders with dummy values so we can request real paths.
  #
  def resolve_path_args(path)
    ret = path.dup
    i = 0

    while ret.match?(/\{[a-zA-Z\-_]+\}/)
      i += 1
      ret.sub!(/\{[a-zA-Z\-_]+\}/, i.to_s)
    end

    ret
  end

  #
  # Walk the @api.routes tree and yield all actions.
  # Yields [action_class, template_path].
  #
  def each_action_route(node, &block)
    (node[:actions] || {}).each(&block)

    (node[:resources] || {}).each_value do |child|
      each_action_route(child, &block)
    end
  end

  it 'responds to OPTIONS /' do
    call_api(:options, '/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    expect(api_response.response).to include(:default_version, :versions)
    expect(api_response[:default_version]).to eq(1)

    versions = api_response[:versions]
    expect(versions).to have_key(:default)

    # Keys are JSON-serialized, so numeric version keys often appear as strings.
    expect(versions.keys.map(&:to_s)).to include('1', '2')
  end

  it 'responds to OPTIONS /?describe=versions' do
    call_api(:options, '/?describe=versions')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    expect(api_response.response).to include(:versions, :default)
    expect(api_response[:default]).to eq(1)
    expect(api_response[:versions]).to contain_exactly(1, 2)
  end

  it 'responds to OPTIONS /?describe=default' do
    call_api(:options, '/?describe=default')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    expect(api_response.response).to include(:authentication, :resources, :meta, :help)
    expect(api_response[:help]).to eq('/v1/')
    expect(api_response[:resources]).to have_key(:user)
    expect(api_response[:resources]).not_to have_key(:admin)

    default_desc = api_response.response

    # should match OPTIONS /v1/
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response.response).to eq(default_desc)
  end

  it 'responds to OPTIONS /<version> for v1 and v2' do
    call_api(:options, '/v1/')
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response.response).to include(:authentication, :resources, :meta, :help)
    expect(api_response[:help]).to eq('/v1/')
    expect(api_response[:resources]).to have_key(:user)
    expect(api_response[:resources]).not_to have_key(:admin)

    call_api(:options, '/v2/')
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response.response).to include(:authentication, :resources, :meta, :help)
    expect(api_response[:help]).to eq('/v2/')
    expect(api_response[:resources]).to have_key(:admin)
    expect(api_response[:resources]).not_to have_key(:user)
  end

  it 'responds to OPTIONS for every action with ?method=' do
    app # ensure @api is built/mounted
    api_instance = instance_variable_get(:@api)

    api_instance.routes.each_value do |tree|
      next unless tree[:resources]

      each_action_route(tree) do |action, template_path|
        request_path = resolve_path_args(template_path)
        method = action.http_method.to_s.upcase

        call_api(:options, "#{request_path}?method=#{method}")

        expect(last_response.status).to eq(200),
                                        "OPTIONS #{request_path}?method=#{method} failed with #{last_response.status}: #{last_response.body}"

        expect(api_response).to be_ok

        # These keys are set in Action.describe
        expect(api_response[:method]).to eq(method)
        expect(api_response[:help]).to eq("#{template_path}?method=#{method}")
        expect(api_response[:path]).to eq(request_path)
      end
    end
  end

  it 'has online doc' do
    get '/doc'

    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/html')

    # servers/ruby/doc/index.md contains this heading
    expect(last_response.body).to include('HaveAPI documentation')
  end

  it 'has online doc for every version' do
    get '/v1/'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/html')

    get '/v2/'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/html')
  end
end

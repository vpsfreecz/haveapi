# frozen_string_literal: true

require 'spec_helper'

module AuthorizeSpec
  User = Struct.new(:id, :login, :admin) do
    def admin?
      admin
    end
  end

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      return nil unless password == 'pass'

      case username
      when 'user'
        User.new(1, 'user', false)
      when 'admin'
        User.new(2, 'admin', true)
      end
    end
  end
end

describe AuthorizeSpec do
  api do
    define_resource(:Item) do
      version 1
      route 'items'

      define_action(:AdminOnly) do
        route 'admin_only'
        http_method :get

        authorize do |user|
          allow if user&.admin?
          deny
        end

        output do
          string :msg
        end

        def exec
          { msg: 'ok' }
        end
      end

      define_action(:Echo) do
        route 'echo'
        http_method :post

        authorize do |user|
          unless user&.admin?
            input blacklist: %i[secret nested.hidden]
            output blacklist: %i[secret nested.hidden]
          end

          allow
        end

        input do
          string :public
          string :secret
          string :'nested.visible'
          string :'nested.hidden'
        end

        output do
          string :public
          string :secret
          string :'nested.visible'
          string :'nested.hidden'
          bool :seen_secret
          bool :seen_nested_hidden
        end

        def exec
          {
            public: input[:public],
            secret: input[:secret],
            'nested.visible': input[:'nested.visible'],
            'nested.hidden': input[:'nested.hidden'],
            seen_secret: input.has_key?(:secret),
            seen_nested_hidden: input.has_key?(:'nested.hidden')
          }
        end
      end

      items = [
        { id: 1, owner_id: 1, name: 'u1' },
        { id: 2, owner_id: 2, name: 'u2' },
        { id: 3, owner_id: 1, name: 'u1b' }
      ].freeze

      define_action(:List) do
        route 'list'
        http_method :get

        authorize do |user|
          restrict owner_id: user.id
          allow
        end

        input do
          integer :owner_id
        end

        output(:object_list) do
          integer :id
          integer :owner_id
          string :name
        end

        define_method(:exec) do
          restrictions = with_restricted(owner_id: input[:owner_id])
          items.select { |item| item[:owner_id] == restrictions[:owner_id] }
        end
      end
    end
  end

  default_version 1
  auth_chain AuthorizeSpec::BasicProvider

  let(:echo_input) do
    {
      item: {
        public: 'pub',
        secret: 'shh',
        'nested.visible': 'visible',
        'nested.hidden': 'hidden'
      }
    }
  end

  def call_get_action(resource, action, params = {})
    env 'rack.input', StringIO.new('')
    call_api(resource, action, params)
  end

  it 'denies non-admins from admin-only action' do
    login('user', 'pass')
    call_get_action([:Item], :admin_only, {})

    expect(last_response.status).to eq(403)
    expect(api_response).to be_failed
    expect(api_response.message).to match(/not authorized|forbidden|denied|access denied/i)
  end

  it 'allows admins to access admin-only action' do
    login('admin', 'pass')
    call_get_action([:Item], :admin_only, {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:item][:msg]).to eq('ok')
  end

  it 'filters output fields for non-admins' do
    login('user', 'pass')
    call_api([:Item], :echo, echo_input)

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    item = api_response[:item]
    expect(item).to include(:public, :'nested.visible', :seen_secret, :seen_nested_hidden)
    expect(item).not_to have_key(:secret)
    expect(item).not_to have_key(:'nested.hidden')
    expect(item[:seen_secret]).to be(false)
    expect(item[:seen_nested_hidden]).to be(false)
  end

  it 'ignores forbidden input fields for non-admins' do
    login('user', 'pass')
    call_api([:Item], :echo, echo_input)

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:item][:seen_secret]).to be(false)
    expect(api_response[:item][:seen_nested_hidden]).to be(false)
  end

  it 'accepts allowed input for non-admins' do
    login('user', 'pass')
    call_api([:Item], :echo, { item: { public: 'pub', 'nested.visible': 'visible' } })

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:item][:public]).to eq('pub')
    expect(api_response[:item]).not_to have_key(:secret)
    expect(api_response[:item]).not_to have_key(:'nested.hidden')
    expect(api_response[:item][:seen_secret]).to be(false)
    expect(api_response[:item][:seen_nested_hidden]).to be(false)
  end

  it 'shows full output for admins' do
    login('admin', 'pass')
    call_api([:Item], :echo, echo_input)

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    item = api_response[:item]
    expect(item[:secret]).to eq('shh')
    expect(item[:'nested.hidden']).to eq('hidden')
    expect(item[:seen_secret]).to be(true)
    expect(item[:seen_nested_hidden]).to be(true)
  end

  it 'does not cache authorization filters between requests' do
    login('user', 'pass')
    call_api([:Item], :echo, echo_input)

    expect(api_response).to be_ok
    expect(api_response[:item]).not_to have_key(:secret)

    login('admin', 'pass')
    call_api([:Item], :echo, echo_input)

    expect(api_response).to be_ok
    expect(api_response[:item]).to have_key(:secret)
  end

  it 'restricts list results to the current user' do
    login('user', 'pass')
    call_get_action([:Item], :list, {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    owners = api_response[:items].map { |item| item[:owner_id] }.uniq
    expect(owners).to eq([1])
  end

  it 'restricts list results to the admin user id' do
    login('admin', 'pass')
    call_get_action([:Item], :list, {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    owners = api_response[:items].map { |item| item[:owner_id] }.uniq
    expect(owners).to eq([2])
  end

  it 'overrides client-supplied filters with restrictions' do
    login('user', 'pass')
    call_get_action([:Item], :list, { item: { owner_id: 2 } })

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    owners = api_response[:items].map { |item| item[:owner_id] }.uniq
    expect(owners).to eq([1])
  end

  it 'hides admin-only actions from non-admin documentation' do
    login('user', 'pass')
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    actions = api_response[:resources][:item][:actions]
    expect(actions).to have_key(:echo)
    expect(actions).to have_key(:list)
    expect(actions).not_to have_key(:admin_only)
  end

  it 'shows admin-only actions for admin documentation' do
    login('admin', 'pass')
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    actions = api_response[:resources][:item][:actions]
    expect(actions).to have_key(:admin_only)
  end

  it 'filters action docs input and output for non-admins' do
    login('user', 'pass')
    call_api(:options, '/v1/items/echo?method=POST')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    input_params = api_response[:input][:parameters]
    output_params = api_response[:output][:parameters]

    expect(input_params).not_to have_key(:secret)
    expect(input_params).not_to have_key(:'nested.hidden')
    expect(output_params).not_to have_key(:secret)
    expect(output_params).not_to have_key(:'nested.hidden')
  end

  it 'shows full action docs input and output for admins' do
    login('admin', 'pass')
    call_api(:options, '/v1/items/echo?method=POST')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    input_params = api_response[:input][:parameters]
    output_params = api_response[:output][:parameters]

    expect(input_params).to have_key(:secret)
    expect(input_params).to have_key(:'nested.hidden')
    expect(output_params).to have_key(:secret)
    expect(output_params).to have_key(:'nested.hidden')
  end
end

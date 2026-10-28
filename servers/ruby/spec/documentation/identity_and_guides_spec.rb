require 'spec_helper'

module DocumentationIdentitySpec
  User = Struct.new(:login)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if password == 'pass'
    end
  end
end

describe DocumentationIdentitySpec do
  api do
    define_resource(:Sample) do
      version 1
      auth false
      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        input(:hash) { string :admin_field, choices: { values: { 'secret-value' => 'Admin choice' } } }
        authorize do |user|
          input blacklist: [:admin_field] if user && user.login != 'admin'
          allow
        end
      end
    end
  end
  default_version 1
  auth_chain DocumentationIdentitySpec::Provider

  it 'shows anonymous visibility and themes without Basic controls when docs OAuth is absent' do
    login('admin', 'pass')
    get '/v1/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Showing all resources, actions and parameters.', 'Using this reference',
                                          'data-documentation-menu', 'aria-label="Documentation settings"', 'aria-label="Theme"')
    expect(last_response.body).not_to include('docs-identity', 'docs-sign-in', 'data-account-menu', 'data-theme-menu')
    expect(last_response.body.index('docs-visibility-note')).to be < last_response.body.index('data-documentation-search')
  end

  it 'uses the requested primary order and indents methods beneath Authentication' do
    get '/v1/?page=authentication'
    primary = last_response.body.match(%r{<nav aria-label="Documentation pages">(.*?)</nav>\s*</li>\s*<li>}m)
    expect(primary).not_to be_nil
    body = primary[1]
    expect(body.index('Overview')).to be < body.index('Authentication')
    expect(body).to include('docs-authentication-submenu', 'href="#auth-basic"')
    sidebar = last_response.body.match(%r{<aside[^>]*>(.*?)</aside>}m)[1]
    expect(sidebar.index('Authentication')).to be < sidebar.index('>Resources</a>')
    expect(sidebar).not_to include('Guides', 'doc/protocol', 'doc/client-examples')
  end

  it 'keeps technical links explicitly in internals and removes the index content link' do
    get '/'
    main = last_response.body.match(%r{<main[^>]*>(.*?)</main>}m)[1]
    expect(main).not_to include('>Documentation</a>')
    expect(last_response.body).to include('HaveAPI internals', 'doc/client-examples')
    get '/v1/'
    expect(last_response.body).not_to include('HaveAPI internals', 'doc/client-examples')
  end

  it 'renders real fenced examples on technical pages and README as code' do
    get '/doc/client-examples'
    expect(last_response).to be_ok
    expect(last_response.body).to match(/<pre><code[^>]*>.*?documentation_clients/m)
    expect(last_response.body).not_to include('```ruby')
    get '/doc/readme'
    expect(last_response).to be_ok
    expect(last_response.body).not_to include('```')
  end
end

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

  it 'shows anonymous visibility and a compact labelled sign-in icon' do
    get '/v1/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Showing all resources, actions and parameters.', 'aria-label="Sign in" title="Sign in"',
                                          'class="docs-sign-in login"', 'Using this reference')
    expect(last_response.body).not_to include('docs-identity')
    top = last_response.body.match(%r{<div class="docs-top-controls">(.*?)</div>\s*<p class="docs-visibility-note">}m)[1]
    expect(top).to include('<details data-theme-menu>', '<summary aria-label="Automatic theme"',
                           'data-theme-current', 'class="docs-sign-in login"')
    expect(last_response.body.scan('class="docs-sign-in login"').length).to eq(1)
    expect(last_response.body.index('docs-visibility-note')).to be < last_response.body.index('data-documentation-search')
  end

  it 'keeps the complete visibility note when authentication is disabled' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.mount('/')
    response = Rack::MockRequest.new(server.app).get('/v1/', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200)
    expect(response.body).to include('Showing all resources, actions and parameters.')
    expect(response.body).not_to include('class="docs-sign-in')
  end

  it 'shows actual escaped identity and scoped visibility even without a cookie CSRF session' do
    server = app
    server.helpers do
      def documentation_oauth_controls
        { signed_in: false, login_url: 'https://example.test/login', logout_url: 'https://example.test/logout', csrf_token: nil, message: nil }
      end
    end
    login('<member>&', 'pass')
    get '/v1/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('class="docs-identity">&lt;member&gt;&amp;',
                                          'Showing resources, actions and parameters available to this account.', 'class="logout"', 'data-account-menu')
    expect(last_response.body).not_to include('data-documentation-login', 'name="csrf"', 'Showing all resources')
    expect(last_response.body.scan('class="docs-identity"').length).to eq(1)
    expect(last_response.body.index('docs-identity')).to be < last_response.body.index('docs-visibility-note')
  end

  it 'preserves existing account form and status markup while moving it beside theme' do
    reads = 0
    app.helpers do
      define_method(:documentation_oauth_controls) do
        reads += 1
        { signed_in: true, logout_url: '/existing/logout?one=1&two=2', csrf_token: '<csrf>&', message: '<status>&' }
      end
    end
    login('member', 'pass')
    get '/v1/'
    expect(last_response).to be_ok
    expect(reads).to eq(1)
    expect(last_response.body).to include('<form method="post" action="/existing/logout?one=1&amp;two=2">',
                                          '<input type="hidden" name="csrf" value="&lt;csrf&gt;&amp;">',
                                          '<button type="submit">Sign out</button>', '<p role="status">&lt;status&gt;&amp;</p>')
    expect(last_response.body.index('<form method="post"')).to be < last_response.body.index('docs-visibility-note')
    expect(last_response.body.index('docs-visibility-note')).to be < last_response.body.index('<p role="status">')
    expect(last_response.body).not_to include('<csrf>', '<status>')
  end

  it 'preserves the existing sign-in destination and enhancement hook' do
    app.helpers do
      def documentation_oauth_controls
        { signed_in: false, login_url: '/existing/login?one=1&two=2', message: nil }
      end
    end
    get '/v1/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('class="docs-sign-in" href="/existing/login?one=1&amp;two=2" data-documentation-login',
                                          'Showing all resources, actions and parameters.')
    expect(last_response.body).not_to include('class="docs-sign-in login"')
  end

  it 'keeps the actual identity and switch action inside the native account menu only for the cookie mode' do
    app.helpers do
      def documentation_oauth_controls
        { signed_in: true, switch_user: true, logout_url: '/existing/logout', csrf_token: '<nonce>', message: nil }
      end
    end
    login('member', 'pass')
    get '/v1/'
    menu = last_response.body.match(%r{<details data-account-menu>(.*?)</details>}m)[1]
    expect(menu).to include('<summary aria-label="Account" title="Account">', 'class="docs-account-content"',
                            '<span class="docs-identity">member</span>', '<button type="submit">Sign out</button>',
                            '<button type="submit">Switch user</button>', '<input type="hidden" name="switch_user" value="1">')
    expect(menu.scan('name="csrf" value="&lt;nonce&gt;"').length).to eq(2)
    expect(menu).not_to include('docs-visibility-note', 'role="status"')
  end

  it 'does not offer switching or cookie logout for a user authenticated through explicit credentials' do
    app.helpers do
      def documentation_oauth_controls
        { signed_in: false, switch_user: true, logout_url: '/unused-cookie-logout', message: nil }
      end
    end
    login('explicit-user', 'pass')
    get '/v1/'
    expect(last_response.body).to include('<span class="docs-identity">explicit-user</span>', 'class="logout"')
    expect(last_response.body).not_to include('name="switch_user"', 'name="csrf"', '/unused-cookie-logout')
  end

  it 'renders only authorized parameter choices without changing anonymous description semantics' do
    get '/v1/?resource=sample'
    expect(last_response.body).to include('admin_field', 'secret-value', 'Admin choice')
    login('member', 'pass')
    get '/v1/?resource=sample'
    expect(last_response.body).not_to include('admin_field', 'secret-value', 'Admin choice')
    login('admin', 'pass')
    get '/v1/?resource=sample'
    expect(last_response.body).to include('secret-value', 'Admin choice')
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

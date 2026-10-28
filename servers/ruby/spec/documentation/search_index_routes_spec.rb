require 'spec_helper'
require 'rack/mock'

module DocumentationSearchIndexSpec
  User = Struct.new(:login)
  class << self
    attr_accessor :private_visible
  end

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if password == 'pass'
    end
  end

  module API
    class Widget < HaveAPI::Resource
      version 1
      auth false
      class Show < HaveAPI::Actions::Default::Show
        authorize do |user|
          input blacklist: [:private_ticket] unless user.login == 'admin' || DocumentationSearchIndexSpec.private_visible
          allow
        end
        input(:hash) do
          string :name, label: 'Name </script> & <markup>'
          string :private_ticket
        end
        output(:hash) { string :label }
      end
    end
  end
end

RSpec.describe HaveAPI::DocumentationSearch::Helpers do
  before { DocumentationSearchIndexSpec.private_visible = false }

  def server
    @server ||= HaveAPI::Server.new(DocumentationSearchIndexSpec::API).tap do |api|
      api.use_version(1)
      api.auth_chain << DocumentationSearchIndexSpec::Provider
      api.locale_header = 'X-Language'
      api.connect_hook(:pre_mount) do |ret, _server, sinatra|
        sinatra.before { response.set_cookie('fixture', 'changed') if request.env['HTTP_X_SET_COOKIE'] }
        ret
      end
      api.mount('/api/')
    end
  end

  def request(path, **headers)
    environment = { 'HTTP_HOST' => 'example.test' }.merge(headers)
    Rack::MockRequest.new(server.app).get("/api/v1/#{path}", environment)
  end

  def page_key(**headers)
    response = request('', **headers)
    expect(response.status).to eq(200)
    response.body.match(/data-search-view-key="([0-9a-f]{64})"/)[1]
  end

  def envelope(response)
    body = response.body.match(%r{\A<script type="application/json" data-documentation-search-index>(.*?)</script>\s*\z}m)[1]
    JSON.parse(body)
  end

  it 'builds one projection from one description on each versioned page and shares it across forms' do
    allow(server).to receive(:describe_version).and_call_original
    allow(HaveAPI::DocumentationSearch::Index).to receive(:new).and_call_original
    response = request('?page=resources')
    keys = response.body.scan(/data-search-view-key="([0-9a-f]{64})"/).flatten
    expect(keys.length).to eq(2)
    expect(keys.uniq.length).to eq(1)
    expect(server).to have_received(:describe_version).once
    expect(HaveAPI::DocumentationSearch::Index).to have_received(:new).once
    expect(response['cache-control']).to eq('private, no-store')
    expect(response.body).not_to include('data-documentation-search-index')
  end

  it 'serves only an escaped inert envelope for matching keys with private cache headers and merged Vary' do
    key = page_key
    response = request("?page=resources&search_index=#{key}")
    expect(response.status).to eq(200)
    expect(response.content_type).to match(%r{\Atext/html;\s*charset=utf-8\z})
    expect(response['cache-control']).to eq('private, max-age=86400, immutable')
    expect(response['etag']).to eq(%("#{key}"))
    expect(response['vary'].split(/,\s*/)).to contain_exactly('X-Language', 'Cookie', 'Authorization')
    expect(envelope(response)).to include('key' => key)
    expect(response.body).to include('\\u003c/script\\u003e', '\\u0026')
    expect(response.body).not_to include('<!DOCTYPE', 'docs-sidebar', '<script src=', 'fixture')
  end

  it 'keeps bootstrap output, mismatches and Set-Cookie changes no-store without conditional success' do
    key = page_key
    bootstrap = request('?page=resources&search_index=current', 'HTTP_IF_NONE_MATCH' => '*')
    expect(bootstrap.status).to eq(200)
    expect(bootstrap['cache-control']).to eq('private, no-store')
    expect(bootstrap['etag']).to be_nil
    expect(envelope(bootstrap)['key']).to eq(key)
    mismatch = request("?page=resources&search_index=#{'0' * 64}", 'HTTP_IF_NONE_MATCH' => '*')
    expect(mismatch.status).to eq(409)
    expect(mismatch['cache-control']).to eq('private, no-store')
    expect(mismatch.body).not_to include('data-documentation-search-index', 'private_ticket')
    cookie = request("?page=resources&search_index=#{key}", 'HTTP_X_SET_COOKIE' => '1', 'HTTP_IF_NONE_MATCH' => '*')
    expect(cookie.status).to eq(200)
    expect(cookie['set-cookie']).not_to be_nil
    expect(cookie['cache-control']).to eq('private, no-store')
    expect(cookie['etag']).to be_nil
  end

  it 'rejects malformed selectors and conflicting query/page fields before describing while OPTIONS stays unchanged' do
    allow(server).to receive(:describe_version).and_call_original
    ["search_index=#{'A' * 64}", 'search_index=short', 'search_index[]=current',
     'search_index=current&search_index=current', 'page=overview&search_index=current',
     'page=resources&q=&search_index=current', 'page=resources&resource=widget&search_index=current'].each do |query|
      expect(request("?#{query}").status).to eq(400), query
    end
    expect(server).not_to have_received(:describe_version)
    response = Rack::MockRequest.new(server.app).options('/api/v1/?search_index[]=current', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200)
  end

  it 'keeps neutral pages index-free and validates root default-version representations' do
    allow(HaveAPI::DocumentationSearch::Index).to receive(:new).and_call_original
    client = Rack::MockRequest.new(server.app)
    %w[/api/ /api/doc/protocol].each do |path|
      page = client.get(path, 'HTTP_HOST' => 'example.test')
      expect(page.status).to eq(200)
      expect(page.body).to include('data-search-view-key=""', 'search_index=current')
    end
    expect(HaveAPI::DocumentationSearch::Index).not_to have_received(:new)
    invalid = client.get('/api/?search_index=current', 'HTTP_HOST' => 'example.test')
    expect(invalid.status).to eq(400)
    expect(invalid['cache-control']).to eq('private, no-store')
    current = client.get('/api/?page=resources&search_index=current', 'HTTP_HOST' => 'example.test')
    expect(current.status).to eq(200)
    expect(envelope(current)['index']).to include('version' => '1', 'base_path' => '/api/v1/')
  end

  it 'binds the projection to resolved locale and canonical Rack/API mounts' do
    server.available_locales = %i[en cs]
    english = envelope(request('?page=resources&search_index=current', 'HTTP_X_LANGUAGE' => 'en'))
    czech = envelope(request('?page=resources&search_index=current', 'HTTP_X_LANGUAGE' => 'cs'))
    expect(english['key']).not_to eq(czech['key'])
    expect(czech['index']['locale']).to eq('cs')
    mounted = envelope(request('?page=resources&search_index=current', 'SCRIPT_NAME' => '/rack'))
    expect(mounted['index']['base_path']).to eq('/rack/api/v1/')
    expect(mounted['key']).not_to eq(english['key'])
  end

  context 'with OAuth documentation sessions' do
    let(:documentation_server) do
      HaveAPI::Server.new(DocumentationSearchIndexSpec::API).tap do |api|
        api.use_version(1)
        api.auth_chain << DocumentationSearchIndexSpec::Provider
      end
    end
    let(:documentation_fixture) do
      require_relative '../../test_support/documentation_oauth_fixture'
      DocumentationOAuthFixture.configure(documentation_server, users: {
        1 => { 'member-token' => DocumentationSearchIndexSpec::User.new('member'),
               'admin-token' => DocumentationSearchIndexSpec::User.new('admin') }
      }, mount_path: '/api/')
    end

    before do
      documentation_fixture
      server.mount('/api/')
    end

    def server
      documentation_server
    end

    def request(path, user: nil, **headers)
      environment = { 'HTTP_HOST' => URI(documentation_fixture.origin).host }.merge(headers)
      environment['HTTP_COOKIE'] = documentation_fixture.header_for(server, version: 1, token: "#{user}-token") if user
      Rack::MockRequest.new(server.app).get("#{documentation_fixture.origin}/api/v1/#{path}", environment)
    end

    it 'rechecks cookie authentication and permission changes before any 304 response' do
      member = page_key(user: 'member')
      admin = page_key(user: 'admin')
      anonymous = page_key
      expect([member, admin, anonymous].uniq.length).to eq(3)
      original = request("?page=resources&search_index=#{member}", user: 'member')
      expect(envelope(original)['index']['parameters'].map { |parameter| parameter['name'] }).not_to include('private_ticket')
      expect(request("?page=resources&search_index=#{admin}", user: 'member', 'HTTP_IF_NONE_MATCH' => '*').status).to eq(409)
      documentation_fixture.lookups.clear
      expect(request("?page=resources&search_index=#{member}", user: 'member', 'HTTP_IF_NONE_MATCH' => %("#{member}")).status).to eq(304)
      expect(documentation_fixture.lookups).to eq([[1, 'member-token']])
      DocumentationSearchIndexSpec.private_visible = true
      changed = page_key(user: 'member')
      expect(changed).not_to eq(member)
      stale = request("?page=resources&search_index=#{member}", user: 'member', 'HTTP_IF_NONE_MATCH' => '*')
      expect(stale.status).to eq(409)
      expect(stale.body).not_to include('data-documentation-search-index')
    end
  end
end

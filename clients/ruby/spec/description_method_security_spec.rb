# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Client do
  let(:communicator_class) do
    Struct.new(:description, :authenticate_calls, :describe_calls) do
      def initialize(description)
        super(description, 0, 0)
      end

      def describe_api(_version)
        self.describe_calls += 1
        description
      end

      def authenticate(*)
        self.authenticate_calls += 1
        :authenticated
      end

      def call(action, _params = {})
        {
          status: true,
          response: {
            action: action.name
          }
        }
      end

      def url
        'https://api.example'
      end
    end
  end

  def action_description(aliases: [])
    {
      auth: false,
      description: 'test action',
      aliases: aliases,
      blocking: false,
      input: {
        layout: 'hash',
        namespace: 'input',
        parameters: {}
      },
      output: {
        layout: 'hash',
        namespace: 'output',
        parameters: {}
      },
      meta: {
        object: nil,
        global: nil
      },
      path: '/v1/test',
      help: '/v1/test?method=GET',
      method: 'GET'
    }
  end

  def client_for(resources)
    api = communicator_class.new(resources: resources)
    client = described_class.new(
      'https://api.example',
      communicator: api
    )

    [client, api]
  end

  it 'does not let top-level resources replace existing client methods' do
    client, api = client_for(
      authenticate: {
        actions: {},
        resources: {}
      },
      setup: {
        actions: {},
        resources: {}
      },
      users: {
        actions: {},
        resources: {}
      }
    )

    expect(client.method(:setup).owner).to eq(described_class)
    expect(client.authenticate(:token, token: 'secret-token')).to eq(:authenticated)

    client.setup

    expect(client.method(:setup).owner).to eq(described_class)
    expect(client.authenticate(:token, token: 'secret-token')).to eq(:authenticated)
    expect(api.authenticate_calls).to eq(2)
    expect(client.users).to be_a(HaveAPI::Client::Resource)
    expect(client.resources.keys).to contain_exactly(:authenticate, :setup, :users)
  end

  it 'does not let actions or nested resources replace resource methods' do
    client, = client_for(
      users: {
        actions: {
          inspect: action_description,
          show: action_description(aliases: %w[resources details])
        },
        resources: {
          posts: {
            actions: {},
            resources: {}
          },
          setup: {
            actions: {},
            resources: {}
          }
        }
      }
    )

    client.setup
    users = client.users

    expect(users.method(:inspect).owner).to eq(HaveAPI::Client::Resource)
    expect(users.resources).to be_a(Hash)
    expect(users.method(:setup).owner).to eq(HaveAPI::Client::Resource)
    expect(users.show).to be_a(HaveAPI::Client::Response)
    expect(users.details).to be_a(HaveAPI::Client::Response)
    expect(users.posts).to be_a(HaveAPI::Client::Resource)
    expect(users.actions.keys).to contain_exactly(:inspect, :show)
    expect(users.resources.keys).to contain_exactly(:posts, :setup)
  end
end

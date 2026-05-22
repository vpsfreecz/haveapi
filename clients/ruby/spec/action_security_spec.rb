# frozen_string_literal: true

require 'spec_helper'
require 'uri'

RSpec.describe HaveAPI::Client::Action do
  let(:action_spec) do
    {
      path: '/v1/users/{user_id}',
      help: '/v1/users/{user_id}?describe=action',
      method: 'GET',
      auth: false,
      blocking: false,
      aliases: [],
      input: {
        layout: :hash,
        namespace: :user,
        parameters: {}
      },
      output: {
        layout: :hash,
        namespace: :user,
        parameters: {}
      },
      meta: {}
    }
  end

  let(:path_arg) { '42?user[name]=alice&_meta[includes]=group__secret' }
  let(:encoded_arg) do
    '42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret'
  end

  let(:communicator) do
    Class.new do
      attr_reader :called_paths

      def initialize
        @called_paths = []
      end

      def url
        'https://api.example'
      end

      def describe_api(_version)
        {
          resources: {
            users: {
              actions: {
                show: {
                  auth: false,
                  description: 'Show a user',
                  aliases: [],
                  blocking: false,
                  input: {
                    layout: 'hash',
                    namespace: 'user',
                    parameters: {
                      note: {
                        type: 'String',
                        nullable: false,
                        validators: {
                          present: {
                            empty: false,
                            message: 'required'
                          }
                        }
                      }
                    }
                  },
                  output: {
                    layout: 'hash',
                    namespace: 'user',
                    parameters: {}
                  },
                  meta: {
                    object: nil,
                    global: nil
                  },
                  path: '/v1/users/{user_id}',
                  help: '/v1/users/{user_id}?method=GET',
                  method: 'GET'
                }
              },
              resources: {}
            }
          }
        }
      end

      def call(action, params = {})
        @called_paths << action.prepared_path

        {
          status: true,
          response: {
            user: {
              path: action.prepared_path,
              params: params
            }
          }
        }
      end
    end.new
  end

  let(:client) do
    HaveAPI::Client::Client.new(
      'https://api.example',
      communicator: communicator
    ).tap(&:setup)
  end

  it 'encodes constructor path arguments as path components' do
    action = described_class.new(nil, nil, :show, action_spec, [path_arg])
    parsed = URI.parse("https://api.example#{action.prepared_path}")

    expect(action.prepared_path).to eq("/v1/users/#{encoded_arg}")
    expect(parsed.path).to eq("/v1/users/#{encoded_arg}")
    expect(parsed.query).to be_nil
  end

  it 'encodes provided path arguments as path components' do
    action = described_class.new(nil, nil, :show, action_spec, [])

    action.provide_args(path_arg)

    expect(action.prepared_path).to eq("/v1/users/#{encoded_arg}")
    expect(action.prepared_help).to eq("/v1/users/#{encoded_arg}?describe=action")
  end

  it 'does not reuse path arguments after validation fails' do
    expect do
      client.users.show(42, {})
    end.to raise_error(HaveAPI::Client::ValidationError)

    expect do
      client.users.show(note: 'allowed follow-up input')
    end.to raise_error(ArgumentError, 'one or more object ids missing')

    response = client.users.show(7, note: 'allowed follow-up input')

    expect(communicator.called_paths).to eq(['/v1/users/7'])
    expect(response[:path]).to eq('/v1/users/7')
  end

  it 'does not reuse path arguments after argument parsing fails' do
    expect do
      client.users.show(42, { note: 'valid input' }, { note: 'extra input' })
    end.to raise_error(ArgumentError, 'too many arguments for action users#show')

    expect do
      client.users.show(note: 'allowed follow-up input')
    end.to raise_error(ArgumentError, 'one or more object ids missing')

    expect(communicator.called_paths).to eq([])
  end
end

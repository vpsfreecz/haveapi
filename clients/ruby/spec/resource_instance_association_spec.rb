# frozen_string_literal: true

require 'spec_helper'

class ResourceAssociationTestCommunicator
  attr_reader :calls

  def initialize(resolved:, association_path: ['language'])
    @resolved = resolved
    @association_path = association_path
    @calls = []
  end

  def describe_api(_version)
    {
      resources: {
        language: resource_description(
          show: action_description(
            namespace: 'language',
            path: '/v1/languages/{language_id}',
            parameters: {
              id: { type: 'Integer' },
              code: { type: 'String' }
            }
          )
        ),
        user: resource_description(
          current: action_description(
            namespace: 'user',
            path: '/v1/users/current',
            parameters: {
              id: { type: 'Integer' },
              language: {
                type: 'Resource',
                resource: @association_path,
                value_id: 'id',
                value_label: 'code'
              }
            }
          )
        )
      }
    }
  end

  def call(action, _params)
    @calls << action.name

    case action.name
    when :current
      response(
        user: {
          id: 1,
          language: {
            id: 1,
            code: 'cs',
            _meta: {
              resolved: @resolved,
              path_params: [1]
            }
          }
        }
      )
    when :show
      response(
        language: {
          id: 1,
          code: 'cs'
        }
      )
    else
      raise "unexpected action #{action.name}"
    end
  end

  def url
    'https://api.example'
  end

  protected

  def resource_description(actions)
    {
      actions: actions.transform_values { |v| v },
      resources: {}
    }
  end

  def action_description(namespace:, path:, parameters:)
    {
      auth: false,
      description: 'test action',
      aliases: [],
      blocking: false,
      input: {
        parameters: {},
        layout: 'object',
        namespace: namespace
      },
      output: {
        parameters: parameters,
        layout: 'object',
        namespace: namespace
      },
      meta: {
        object: nil,
        global: nil
      },
      examples: [],
      scope: "#{namespace}#show",
      path: path,
      method: 'GET',
      help: "#{path}?method=GET"
    }
  end

  def response(values)
    {
      status: true,
      response: values.merge(_meta: {}),
      message: nil,
      errors: nil
    }
  end
end

RSpec.describe HaveAPI::Client::ResourceInstance do
  def client_for(...)
    communicator = ResourceAssociationTestCommunicator.new(...)
    client = HaveAPI::Client::Client.new(
      'https://api.example',
      communicator: communicator
    )

    [client, communicator]
  end

  it 'materializes a resolved association through the resource registry' do
    client, communicator = client_for(resolved: true)

    user = client.user.current

    expect(user.language_id).to eq(1)
    expect(user.language.code).to eq('cs')
    expect(communicator.calls).to eq([:current])
  end

  it 'resolves a lazy association through the resource registry' do
    client, communicator = client_for(resolved: false)

    user = client.user.current

    expect(user.language.code).to eq('cs')
    expect(communicator.calls).to eq(%i[current show])
  end

  it 'reports an invalid associated resource path as a protocol error' do
    client, = client_for(resolved: true, association_path: ['missing'])

    expect { client.user.current }
      .to raise_error(
        HaveAPI::Client::ProtocolError,
        "associated resource 'missing' not found"
      )
  end
end

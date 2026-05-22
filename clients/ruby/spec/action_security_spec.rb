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
end

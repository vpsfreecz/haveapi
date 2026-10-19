# Python-only authentication and wire fixtures for the shared Ruby harness.
require 'securerandom'
require_relative '../../../../servers/ruby/test_support/client_test_api'

module PythonTokenChallenge
  def self.pending
    @pending ||= {}
  end

  module Reset
    def reset!
      PythonTokenChallenge.pending.clear
      super
    end
  end
end

config = HaveAPI::ClientTestAPI::TokenConfig
config.singleton_class.prepend(PythonTokenChallenge::Reset)
ordinary_login = config.request.handle
config.request do
  input do
    string :user, required: true
    password :password, required: true
    bool :phrase_challenge, default: false, fill: true
  end

  handle do |request, result|
    unless request.input[:phrase_challenge]
      next ordinary_login.call(request, result)
    end

    user = HaveAPI::ClientTestAPI::USERS[request.input[:user]]
    unless user && request.input[:password] == 'pass'
      result.error = 'invalid credentials'
      next result
    end

    result.token = SecureRandom.hex(24)
    PythonTokenChallenge.pending[result.token] = user
    result.valid_to = Time.now + 300
    result.next_action = 'verify_phrase'
    result.ok
  end
end

config.action(:verify_phrase) do
  input do
    string :phrase, required: true
  end

  handle do |request, result|
    user = PythonTokenChallenge.pending.delete(request.token)
    unless user && request.input[:phrase] == 'violet otter'
      result.error = 'invalid phrase challenge'
      next result
    end

    result.token = SecureRandom.hex(24)
    HaveAPI::ClientTestAPI::TokenConfig.tokens[result.token] = user
    result.valid_to = Time.now + 3600
    result.complete = true
    result.ok
  end
end

HaveAPI::ClientTestAPI::Resources.define_resource(:Wire) do
  desc 'Python wire encoding fixtures'
  auth false

  { GetRows: [:get, 'get_rows'], DeletePayload: [:delete, 'delete_payload'] }.each do |name, (method, path)|
    define_action(name) do
      route path
      http_method method
      input(:hash, namespace: :payload) do
        custom :rows
        string :message
        integer :count
        bool :flag
      end
      output(:hash, namespace: :echo) do
        custom :rows
        string :message
        integer :count
        bool :flag
        string :marker
      end
      meta(:global) do
        input do
          string :marker
        end
      end
      authorize { allow }

      def exec
        ret = input.dup
        ret[:marker] = meta[:marker] if meta.has_key?(:marker)
        ret
      end
    end
  end
end

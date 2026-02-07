# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

module ActionExceptionsSpec
  class BaseError < StandardError; end
  class NotFound < BaseError; end
  class Forbidden < BaseError; end
  class BadRequest < BaseError; end
end

describe HaveAPI::Extensions::ActionExceptions do
  api do
    define_resource(:Test) do
      version 1
      auth false

      define_action(:RaiseNotFound) do
        http_method :get
        authorize { allow }

        def exec
          raise ActionExceptionsSpec::NotFound, 'missing object'
        end
      end

      define_action(:RaiseForbidden) do
        http_method :get
        authorize { allow }

        def exec
          raise ActionExceptionsSpec::Forbidden, 'access denied'
        end
      end

      define_action(:RaiseBadRequest) do
        http_method :get
        authorize { allow }

        def exec
          raise ActionExceptionsSpec::BadRequest, 'invalid payload'
        end
      end

      define_action(:RaiseRuntime) do
        http_method :get
        authorize { allow }

        def exec
          raise 'boom'
        end
      end

      define_action(:Ok) do
        http_method :get
        authorize { allow }

        output do
          string :msg
        end

        def exec
          { msg: 'ok' }
        end
      end
    end
  end

  default_version 1

  def with_action_exceptions
    hooks = HaveAPI::Hooks.hooks
    action_hooks = hooks[HaveAPI::Action][:exec_exception]
    original_listeners = action_hooks[:listeners].dup
    original_exceptions =
      HaveAPI::Extensions::ActionExceptions.instance_variable_get(:@exceptions)

    HaveAPI::Extensions::ActionExceptions.instance_variable_set(:@exceptions, [])
    map_exception(ActionExceptionsSpec::NotFound, 404)
    map_exception(ActionExceptionsSpec::Forbidden, 403)
    map_exception(ActionExceptionsSpec::BadRequest, 400)

    api_server = app.settings.api_server
    HaveAPI::Extensions::ActionExceptions.enabled(api_server)

    yield
  ensure
    action_hooks[:listeners] = original_listeners
    HaveAPI::Extensions::ActionExceptions.instance_variable_set(
      :@exceptions,
      original_exceptions
    )
  end

  def map_exception(klass, status)
    HaveAPI::Extensions::ActionExceptions.rescue(klass) do |ret, e|
      ret[:status] = false
      ret[:message] = e.message
      ret[:http_status] = status
      ret
    end
  end

  def call_test_action(action_name)
    env 'rack.input', StringIO.new('')
    call_api([:Test], action_name, {})
  end

  def expect_failed_json(status)
    expect(last_response.status).to eq(status)
    expect(api_response).to be_failed
    expect(last_response.headers['Content-Type']).to include('application/json')
    expect(last_response.body).not_to match(/<html/i)
  end

  it 'maps NotFound to 404' do
    with_action_exceptions do
      call_test_action(:raise_not_found)

      expect_failed_json(404)
      expect(api_response.message).to eq('missing object')
    end
  end

  it 'maps Forbidden to 403' do
    with_action_exceptions do
      call_test_action(:raise_forbidden)

      expect_failed_json(403)
      expect(api_response.message).to eq('access denied')
    end
  end

  it 'maps BadRequest to 400' do
    with_action_exceptions do
      call_test_action(:raise_bad_request)

      expect_failed_json(400)
      expect(api_response.message).to eq('invalid payload')
    end
  end

  it 'keeps unmapped exceptions in a safe envelope' do
    with_action_exceptions do
      call_test_action(:raise_runtime)

      expect_failed_json(500)
      expect(api_response.message).to be_a(String)
      expect(api_response.message).not_to be_empty
    end
  end

  it 'does not interfere with successful responses' do
    with_action_exceptions do
      call_test_action(:ok)

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response.response[:test]).to eq(msg: 'ok')
    end
  end
end

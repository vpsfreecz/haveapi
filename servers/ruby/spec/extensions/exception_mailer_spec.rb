# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

module ExceptionMailerSpec
  class RequestError < StandardError; end
  class ActionError < StandardError; end
end

describe HaveAPI::Extensions::ExceptionMailer do
  api do
    define_resource(:Test) do
      version 1
      auth false

      define_action(:RequestError) do
        route 'request_error'
        http_method :get

        authorize do
          raise ExceptionMailerSpec::RequestError, 'request boom'
        end

        def exec
          ok!
        end
      end

      define_action(:ActionError) do
        route 'action_error'
        http_method :get
        authorize { allow }

        def exec
          raise ExceptionMailerSpec::ActionError, 'action boom'
        end
      end
    end
  end

  default_version 1

  def with_exception_mailer(mailer)
    action_hooks = HaveAPI::Hooks.hooks[HaveAPI::Action][:exec_exception]
    original_action_listeners = action_hooks[:listeners].dup
    server = app.settings.api_server
    original_server_hooks = dup_instance_hooks(server)

    mailer.enabled(server)
    yield
  ensure
    action_hooks[:listeners] = original_action_listeners
    restore_instance_hooks(server, original_server_hooks)
  end

  def dup_instance_hooks(server)
    hooks = server.instance_variable_get(HaveAPI::Hooks::INSTANCE_VARIABLE)
    return unless hooks

    hooks.transform_values do |hook|
      hook.merge(listeners: hook[:listeners].dup)
    end
  end

  def restore_instance_hooks(server, hooks)
    if hooks
      server.instance_variable_set(HaveAPI::Hooks::INSTANCE_VARIABLE, hooks)
    elsif server.instance_variable_defined?(HaveAPI::Hooks::INSTANCE_VARIABLE)
      server.remove_instance_variable(HaveAPI::Hooks::INSTANCE_VARIABLE)
    end
  end

  def collect_mail_calls(mailer)
    calls = []

    allow(mailer).to receive(:mail) do |context, exception, body|
      calls << [context, exception, body]
    end

    calls
  end

  def new_mailer
    described_class.new(
      from: 'from@example.test',
      to: 'to@example.test',
      subject: '[spec] %s',
      smtp: false
    )
  end

  it 'mails request-level exceptions outside action execution' do
    mailer = new_mailer
    calls = collect_mail_calls(mailer)

    with_exception_mailer(mailer) do
      get '/v1/tests/request_error'
    end

    expect(last_response.status).to eq(500)
    expect(api_response).not_to be_ok
    expect(api_response.message).to eq('Server error occurred')

    expect(calls.size).to eq(1)
    context, exception, body = calls.first
    expect(context.action.to_s).to include('RequestError')
    expect(exception).to be_a(ExceptionMailerSpec::RequestError)
    expect(body).to include('request boom')
  end

  it 'mails action execution exceptions' do
    mailer = new_mailer
    calls = collect_mail_calls(mailer)

    with_exception_mailer(mailer) do
      get '/v1/tests/action_error'
    end

    expect(last_response.status).to eq(500)
    expect(api_response).not_to be_ok
    expect(calls.size).to eq(1)
    expect(calls.first[1]).to be_a(ExceptionMailerSpec::ActionError)
    expect(calls.first[2]).to include('action boom')
  end

  it 'does not replace the API response when mail delivery fails' do
    mailer = new_mailer
    allow(mailer).to receive(:mail).and_raise(StandardError, 'smtp down')

    with_exception_mailer(mailer) do
      expect do
        get '/v1/tests/request_error'
      end.to output(/ExceptionMailer failed: StandardError: smtp down/).to_stderr
    end

    expect(last_response.status).to eq(500)
    expect(api_response).not_to be_ok
    expect(api_response.message).to eq('Server error occurred')
  end
end

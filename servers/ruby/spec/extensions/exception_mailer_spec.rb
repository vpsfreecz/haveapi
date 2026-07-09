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

      define_action(:InputRequestError) do
        route 'input_request_error'
        http_method :post

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
    expect(api_response.message).to eq('A server error occurred')

    expect(calls.size).to eq(1)
    context, exception, body = calls.first
    expect(context.action.to_s).to include('RequestError')
    expect(exception).to be_a(ExceptionMailerSpec::RequestError)
    expect(body).to include('request boom')
  end

  it 'redacts secrets from request-level exception emails' do
    mailer = new_mailer
    calls = collect_mail_calls(mailer)
    header_secret = %w[HEADER SECRET].join('_')
    header_token_secret = %w[HEADER TOKEN SECRET].join('_')
    cookie_secret = %w[COOKIE SECRET].join('_')
    query_secret = %w[QUERY SECRET].join('_')
    body_secret = %w[BODY SECRET].join('_')
    nested_secret = %w[NESTED SECRET].join('_')

    with_exception_mailer(mailer) do
      header 'Accept', 'application/json'
      header 'Content-Type', 'application/json'
      header 'Authorization', "Bearer #{header_secret}"
      header 'Cookie', "session=#{cookie_secret}"
      header 'X-Auth-Token', header_token_secret
      post "/v1/tests/input_request_error?_auth_token=#{query_secret}", JSON.generate({
        password: body_secret,
        nested: {
          token: nested_secret,
          visible: 'VISIBLE_VALUE'
        }
      })
    end

    body = calls.first[2]

    expect(body).to include('VISIBLE_VALUE')
    expect(body).to include(HaveAPI::Extensions::ExceptionMailer::FILTERED_VALUE)
    [
      header_secret,
      header_token_secret,
      cookie_secret,
      query_secret,
      body_secret,
      nested_secret
    ].each do |secret|
      expect(body).not_to include(secret)
    end
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
    expect(api_response.message).to eq('A server error occurred')
  end
end

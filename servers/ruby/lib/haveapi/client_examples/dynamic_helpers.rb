require 'json'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  module DynamicHelpers
    class Unsupported < StandardError; end

    def field(value, name, default = nil)
      return default unless value.is_a?(Hash)

      value.fetch(name) { value.fetch(name.to_s, default) }
    end

    def code_result
      { status: :code, code: yield.freeze }.freeze
    rescue Unsupported, HaveAPI::ClientExample::UnsupportedAuthentication, JSON::GeneratorError => e
      { status: :limitation, reason: e.message.freeze }.freeze
    end

    def limitation(reason)
      { status: :limitation, reason: reason.freeze }.freeze
    end

    def api_base
      context ? context.base_url : base_url
    end

    def api_version
      context ? context.version : version.to_s
    end

    def current_action
      context&.action || action
    end

    def current_resource_path
      context&.resource_path || resource_path
    end

    def current_action_name
      context&.action_name || action_name
    end

    def json_data(value)
      case value
      when Hash
        result = {}
        value.each do |key, entry|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise Unsupported, 'This sample has a non-string object key.'
          end
          raise Unsupported, 'This sample has duplicate serialized object keys.' if result.has_key?(key.to_s)

          result[key.to_s] = json_data(entry)
        end
        result
      when Array
        value.map { |entry| json_data(entry) }
      when String, Integer, TrueClass, FalseClass, NilClass
        value
      when Float
        raise Unsupported, 'This sample has a non-finite number.' unless value.finite?

        value
      else
        raise Unsupported, 'This sample contains a value without a supported literal representation.'
      end
    end

    def structured_sample(sample)
      unless sample.is_a?(Hash) && (!field(sample, :request).nil? || !field(sample, :response).nil?)
        raise Unsupported, 'This example contains prose only; no executable request is supplied.'
      end

      %i[global object].each do |scope|
        next if scope == :object && field(current_action, :input).nil?

        input = field(field(field(current_action, :meta), scope), :input)
        if field(input, :parameters, {}).values.any? { |parameter| field(parameter, :required) }
          raise Unsupported, 'This action requires input metadata that the sample format cannot supply.'
        end
      end

      placeholders = field(current_action, :path, '').scan(/\{([a-zA-Z0-9_-]+)\}/).flatten
      values = field(sample, :path_params, []) || []
      unless values.is_a?(Array) && values.length == placeholders.length
        raise Unsupported, 'The sample does not supply every action path argument.'
      end
      unless values.all? { |value| value.is_a?(String) || value.is_a?(Integer) }
        raise Unsupported, 'Action path arguments must be strings or integers.'
      end

      request = field(sample, :request)
      input = field(current_action, :input)
      if !request.nil? && input.nil? && request != {}
        raise Unsupported, 'The sample supplies input for an action without an input description.'
      end

      if request.is_a?(Hash) && input
        known = field(input, :parameters, {}).keys.map(&:to_s)
        unless (request.keys.map(&:to_s) - known).empty?
          raise Unsupported, 'The sample contains input parameters absent from the visible description.'
        end
      end
      [placeholders.zip(values).to_h, json_data(request)]
    end

    def supported_auth?(method)
      %i[basic token oauth2].include?(method.to_sym) &&
        (!context || field(context.description, :authentication, {}).keys.map(&:to_s).include?(method.to_s))
    end

    def token_request_fields(description)
      token = field(field(description, :resources, {}), :token, {})
      request = field(field(token, :actions, {}), :request, {})
      field(field(request, :input, {}), :parameters, {})
    end

    def token_login_fields(description)
      token_request_fields(description).reject do |name, _|
        %w[token lifetime interval].include?(name.to_s)
      end
    end

    def indent(source, spaces = 2)
      source.lines.map { |line| line.strip.empty? ? line : "#{' ' * spaces}#{line}" }.join
    end
  end
end

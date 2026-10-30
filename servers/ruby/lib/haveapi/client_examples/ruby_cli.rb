require 'shellwords'
module HaveAPI
  module CLI; end
end

require 'haveapi/cli/output_formatter'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RubyCli < HaveAPI::ClientExample
    label 'CLI'
    language 'cli'
    language_label 'CLI'
    detail_levels :simple
    code :bash
    order 30

    def init
      "$ haveapi-cli -u #{Shellwords.escape(base_url.to_s)} --version #{Shellwords.escape(version.to_s)}"
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          # Provide credentials on command line
          #{init} --auth basic --user user --password secret

          # If username or password isn't provided, the user is asked on stdin
          #{init} --auth basic --user user
          # Password: secret
        END

      when :token
        <<~END
          # Get token using username and password and save it to disk
          # Note that the client always has to call some action. APIs should provide
          # an action to get information about the current user, so that's what we're
          # calling now.
          #{init} --auth token #{auth_token_credentials(desc, password: false).map { |k, v| "#{Shellwords.escape("--#{k}")} #{Shellwords.escape(v.to_s)}" }.join(' ')} --save user current
          # Password: secret

          # Now the token is read from disk and the user does not have to provide username
          # nor password and be authenticated
          #{init} user current
        END

      when :oauth2
        '# OAuth2 is not supported by HaveAPI Ruby CLI.'
      end
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def example(sample)
      cmd = [init]
      cmd << Shellwords.escape(resource_path.join('.'))
      cmd << Shellwords.escape(action_name.to_s)
      cmd.concat(sample[:path_params].map { |value| Shellwords.escape(value.to_s) }) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        cmd << "-- \\\n"

        res = cmd.join(' ') + sample[:request].map do |k, v|
          (' ' * 14) + input_param(k, v)
        end.join(" \\\n")

      else
        res = cmd.join(' ')
      end

      return response(sample, res) if sample[:status]

      display = "Action failed: #{sample[:message]}\n"

      if sample[:errors] && sample[:errors].any?
        display << "Errors:\n"
        sample[:errors].each do |param, e|
          display << "\t#{param}: #{e.join('; ')}\n"
        end
      end

      res << "\n" << comment_response(display)
    end

    def response(sample, res)
      return res if sample[:response].nil? || sample[:response].empty?

      cols = []

      action[:output][:parameters].each do |name, param|
        col = {
            name:,
            align: %w[Integer Float].include?(param[:type]) ? 'right' : 'left',
            label: param[:label] && !param[:label].empty? ? param[:label] : name.upcase
        }

        if param[:type] == 'Resource'
          col[:display] = proc do |r|
            next '' unless r
            next r unless r.is_a?(::Hash)

            "#{r[param[:value_label].to_sym]} (##{r[param[:value_id].to_sym]})"
          end
        end

        cols << col
      end

      display = HaveAPI::CLI::OutputFormatter.to_s(sample[:response], cols)
      res << "\n" << comment_response(display)
    end

    def input_param(name, value)
      option = name.to_s.gsub('_', '-')

      if action[:input][:parameters][name][:type] == 'Boolean'
        return Shellwords.escape(value ? "--#{option}" : "--no-#{name}")
      end

      "#{Shellwords.escape("--#{option}")} #{Shellwords.escape(value.to_s)}"
    end

    private

    def comment_response(fragment)
      fragment.gsub(/\r\n?/, "\n").lines.map { |line| "# #{line.delete_suffix("\n")}\n" }.join
    end
  end
end

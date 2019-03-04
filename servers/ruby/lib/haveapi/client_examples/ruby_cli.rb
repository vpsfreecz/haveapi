module HaveAPI
  module CLI ; end
end

require 'haveapi/cli/output_formatter'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RubyCli < HaveAPI::ClientExample
    label 'CLI'
    code :bash
    order 30

    def init
      "$ haveapi-cli -u #{base_url} --version #{version}"
    end

    def auth(method, desc)
      case method
      when :basic
        <<END
# Provide credentials on command line
#{init} --auth basic --username user --password secret

# If username or password isn't provided, the user is asked on stdin
#{init} --auth basic --username user
Password: secret
END

      when :token
        <<END
# Get token using username and password and save it to disk
# Note that the client always has to call some action. APIs should provide
# an action to get information about the current user, so that's what we're
# calling now.
#{init} --auth token --username user --save user current
Password: secret

# Now the token is read from disk and the user does not have to provide username
# nor password and be authenticated
#{init} user current
END
      end
    end

    def example(sample)
      cmd = [init]
      cmd << resource_path.join('.')
      cmd << action_name
      cmd.concat(sample[:url_params]) if sample[:url_params]

      if sample[:request] && !sample[:request].empty?
        cmd << "-- \\\n"

        res = cmd.join(' ') + sample[:request].map do |k, v|
          ' '*14 + input_param(k, v)
        end.join(" \\\n")

      else
        res = cmd.join(' ')
      end

      return response(sample, res) if sample[:status]

      res << "\nAction failed: #{sample[:message]}\n"

      if sample[:errors] && sample[:errors].any?
        res << "Errors:\n"
        sample[:errors].each do |param, e|
          res << "\t#{param}: #{e.join('; ')}\n"
        end
      end

      res
    end

    def response(sample, res)
      return res if sample[:response].nil? || sample[:response].empty?

      cols = []

      action[:output][:parameters].each do |name, param|
        col = {
            name: name,
            align: %w(Integer Float).include?(param[:type]) ? 'right' : 'left',
            label: param[:label] && !param[:label].empty? ? param[:label] : name.upcase,
        }

        if param[:type] == 'Resource'
          col[:display] = Proc.new do |r|
            next '' unless r
            next r unless r.is_a?(::Hash)

            "#{r[ param[:value_label].to_sym ]} (##{r[ param[:value_id].to_sym ]})"
          end
        end

        cols << col
      end

      res << "\n" << HaveAPI::CLI::OutputFormatter.format(
          sample[:response],
          cols
      )
      res
    end

    def input_param(name, value)
      option = name.to_s.gsub(/_/, '-')

      if action[:input][:parameters][name][:type] == 'Boolean'
        return value ? "--#{option}" : "--no-#{name}"
      end

      "--#{option} '#{value}'"
    end
  end
end

module HaveAPI::ClientExamples
  class RubyCli < HaveAPI::ClientExample
    label 'CLI'
    order 30

    def init
      "$ haveapi-cli -u #{base_url}"
    end

    def auth(method)
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

      return cmd.join(' ') if !sample[:request] || sample[:request].empty?

      cmd << "-- \\\n"

      cmd.join(' ') + sample[:request].map do |k, v|
        ' '*14 + input_param(k, v)
      end.join(" \\\n")
    end

    def input_param(name, value)
      option = name.to_s.gsub(/_/, '-')

      if action[:input][:parameters][name][:type] == 'Boolean'
        return value ? "--#{option}" : "--no-#{name}"
      end

      "--#{option} '#{value}'"

    rescue NoMethodError => e
      require 'pry'
      binding.pry
    end
  end
end

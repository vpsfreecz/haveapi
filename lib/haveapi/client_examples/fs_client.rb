module HaveAPI::ClientExamples
  class FsClient < HaveAPI::ClientExample
    label 'File system'
    order 40

    def init
      "# Mount the file system\n$ haveapi-fs #{base_url} #{mountpoint}"
    end

    def auth(method)
      case method
      when :basic
        <<END
# Provide credentials as file system options
#{init} -o auth_method=basic,user=myuser,password=secret

# If username or password isn't provided, the user is asked on stdin
#{init} -o auth_method=basic,user=myuser
Password: secret
END

      when :token
        <<END
# Authenticate using username and password
#{init} -o auth_method=token,user=myuser
Password: secret

# If you have generated a token, you can use it
#{init} -o auth_method=token,token=yourtoken

# Note that the file system can read config file from haveapi-client, so if
# you set up authentication there, the file system will use it.
END
      end
    end

    def example(sample)
      cmd = [init]

      path = [mountpoint].concat(resource_path)

      unless class_action?
        if !sample[:url_params] || sample[:url_params].empty?
          fail "example {#{sample}} of action #{resource_path.join('.')}"+
               ".#{action_name} is for an instance action but does not include "+
               "URL parameters"
        end

        path << sample[:url_params].first.to_s
      end

      path << 'actions' << action_name

      cmd << "\n# Change to action directory"
      cmd << "$ cd #{File.join(path)}"

      if sample[:request] && !sample[:request].empty?
        cmd << "\n# Prepare input parameters"

        sample[:request].each do |k, v|
          cmd << "$ echo '#{v}' > input/#{k}"
        end
      end

      cmd << "\n# Execute the action"
      cmd << "$ echo 1 > exec"

      cmd.join("\n")
    end

    def mountpoint
      "/mnt/#{host}"
    end

    def class_action?
      action[:url].index(/:[a-zA-Z\-_]+/).nil?
    end
  end
end

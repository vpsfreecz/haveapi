require 'highline/import'

module HaveAPI::CLI
  module Utils
    def param_option(name, p)
      ret = '--'
      name = name.to_s.dasherize

      ret += if p[:type] == 'Boolean'
               "[no-]#{name}"

             else
               "#{name} [#{name.underscore.upcase}]"
             end

      ret
    end

    def read_param(name, p)
      prompt = "#{p[:label] || name}: "

      ask(prompt) do |q|
        q.default = nil
        q.echo = !p[:protected]
      end
    end
  end
end

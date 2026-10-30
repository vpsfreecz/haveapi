require 'shellwords'

module HaveAPI::CLI
  module ExampleFormatter
    def self.format_examples(cli, action, out = $>)
      action.examples.each do |example|
        out << ' > ' << example[:title] << ":\n" unless example[:title].empty?

        # request
        out << "$ #{Shellwords.escape($0)} #{Shellwords.escape(action.resource_path.join('.'))} #{Shellwords.escape(action.name.to_s)}"

        params = example[:request]

        if params
          out << ' --' unless params.empty?

          params.each do |k, v|
            desc = action.param_description(:input, k)
            next unless desc

            out << ' ' << example_param(k, v, desc)
          end
        end

        out << "\n"

        # response
        cli.format_output(
          action,
          { action.namespace(:output).to_sym => example[:response] },
          out
        )
      end
    end

    def self.example_param(name, value, desc)
      option = name.to_s.dasherize

      case desc[:type]
      when 'Boolean'
        Shellwords.escape(value ? "--#{option}" : "--no-#{option}")

      else
        "#{Shellwords.escape("--#{option}")} #{example_value(value)}"
      end
    end

    def self.example_value(v)
      Shellwords.escape(v.to_s)
    end
  end
end

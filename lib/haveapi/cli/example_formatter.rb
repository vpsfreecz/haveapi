module HaveAPI::CLI
  module ExampleFormatter
    def self.format_examples(cli, action, out = $>)
      action.examples.each do |example|
        out << ' > ' << example[:title] << ":\n" unless example[:title].empty?

        # request
        out << "$ #{$0} #{action.resource_path.join('.')} #{action.name}"

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
            {action.namespace(:output).to_sym => example[:response]},
            out
        )
      end
    end

    def self.example_param(name, value, desc)
      option = name.to_s.dasherize

      case desc[:type]
        when 'Boolean'
          value ? "--#{option}" : "--no-#{option}"

        else
          "--#{option} #{example_value(value)}"
      end
    end

    def self.example_value(v)
      (v.is_a?(String) && (v.empty? || v.index(' '))) ? "\"#{v}\"" : v
    end
  end
end

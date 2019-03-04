require 'haveapi/output_formatters/base'

module HaveAPI::OutputFormatters
  class Json < BaseFormatter
    handle 'application/json'

    def format(response)
      if ENV['RACK_ENV'] == 'development'
        JSON.pretty_generate(response)

      else
        JSON.generate(response)
      end
    end
  end
end

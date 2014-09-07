module HaveAPI::OutputFormatters
  class Json < BaseFormatter
    handle 'application/json'

    def format(response)
      JSON.pretty_generate(response)
    end
  end
end

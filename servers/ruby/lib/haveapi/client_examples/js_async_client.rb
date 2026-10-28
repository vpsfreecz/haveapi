require 'haveapi/client_examples/js_client'

module HaveAPI::ClientExamples
  class JsAsyncClient < JsClient
    label 'JavaScript (async)'
    language 'javascript'
    language_label 'JavaScript'
    variant 'Async'
    id 'javascript-async'
    code :javascript
    order 11

    def self.detail_levels_for(_kind, context:, result:, auth_method: nil, auth_description: nil)
      result[:status] == :limitation ? SIMPLE_DETAIL_LEVELS : DEFAULT_DETAIL_LEVELS
    end

    def asynchronous?
      true
    end
  end
end

require 'haveapi/client_examples/js_client'

module HaveAPI::ClientExamples
  class JsAsyncClient < JsClient
    label 'JavaScript (async)'
    id 'javascript-async'
    code :javascript
    order 11

    def asynchronous?
      true
    end
  end
end

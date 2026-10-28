require 'haveapi/client_examples/js_client'

module HaveAPI::ClientExamples
  class TsClient < JsClient
    label 'TypeScript (callback)'
    language 'typescript'
    language_label 'TypeScript'
    variant 'Callback'
    id 'typescript-callback'
    code :typescript
    order 12

    def typescript?
      true
    end
  end
end

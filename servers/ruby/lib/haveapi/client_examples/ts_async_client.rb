require 'haveapi/client_examples/ts_client'

module HaveAPI::ClientExamples
  class TsAsyncClient < TsClient
    label 'TypeScript (async)'
    language 'typescript'
    language_label 'TypeScript'
    variant 'Async'
    id 'typescript-async'
    code :typescript
    order 13

    def asynchronous?
      true
    end
  end
end

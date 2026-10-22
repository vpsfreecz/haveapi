require 'haveapi/client_examples/ts_client'

module HaveAPI::ClientExamples
  class TsAsyncClient < TsClient
    label 'TypeScript (async)'
    id 'typescript-async'
    code :typescript
    order 13

    def asynchronous?
      true
    end
  end
end

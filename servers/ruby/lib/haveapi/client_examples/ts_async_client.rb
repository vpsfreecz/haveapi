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

    def self.detail_levels_for(_kind, context:, result:, auth_method: nil, auth_description: nil)
      result[:status] == :limitation ? SIMPLE_DETAIL_LEVELS : DEFAULT_DETAIL_LEVELS
    end

    def asynchronous?
      true
    end
  end
end

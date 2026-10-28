require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class TsGeneratedClient < HaveAPI::ClientExample
    id 'typescript-generated'
    label 'TypeScript (generated)'
    language 'typescript'
    language_label 'TypeScript'
    variant 'Generated'
    code :typescript
    order 19

    def self.available?(context)
      context&.profile&.language == :typescript
    end

    def init
      render_documentation(:init)
    end

    def auth(method, desc)
      render_documentation(:auth, auth_method: method, auth_description: desc)
    end

    def example(sample)
      render_documentation(:example, rendering_context: context&.with(sample:))
    end

    private

    def render_documentation(kind, rendering_context: context, **)
      unless self.class.available?(rendering_context)
        return { status: :limitation, reason: 'A generated TypeScript SDK documentation profile is required.' }.freeze
      end

      rendering_context.profile.adapter.render(kind:, context: rendering_context, mode: :async, **)
    end
  end
end

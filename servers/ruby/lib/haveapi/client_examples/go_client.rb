require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class GoClient < HaveAPI::ClientExample
    label 'Go'
    id 'go'
    code :go
    order 16

    def self.available?(context)
      context.profile && context.profile.language == :go
    end

    def init
      render_documentation(:init)
    end

    def auth(method, desc)
      render_documentation(:auth, auth_method: method, auth_description: desc)
    end

    def example(sample)
      render_documentation(:example, sample:)
    end

    protected

    def render_documentation(kind, sample: nil, **)
      unless context && self.class.available?(context)
        return { status: :limitation, reason: 'A Go SDK profile is required.' }.freeze
      end

      selected = kind == :example ? context.with(sample:) : context
      context.profile.adapter.render(kind:, context: selected, mode: :sync, **)
    end
  end
end

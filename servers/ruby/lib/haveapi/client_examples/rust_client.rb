require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RustClient < HaveAPI::ClientExample
    class << self
      def available?(context)
        context&.profile&.language == :rust
      end
    end

    def init
      render_rust(:init)
    end

    def auth(method, desc)
      render_rust(:auth, auth_method: method, auth_description: desc)
    end

    def example(sample)
      render_rust(:example, rendering_context: context&.with(sample:))
    end

    private

    def render_rust(kind, rendering_context: context, **)
      unless self.class.available?(rendering_context)
        return { status: :limitation, reason: 'A Rust SDK documentation profile is required.' }.freeze
      end

      rendering_context.profile.adapter.render(kind:, context: rendering_context, mode: rust_mode, **)
    end
  end

  class RustAsyncClient < RustClient
    id 'rust-async'
    label 'Rust (async)'
    language 'rust'
    language_label 'Rust'
    variant 'Async'
    code :rust
    order 17

    private

    def rust_mode
      :async
    end
  end

  class RustBlockingClient < RustClient
    id 'rust-blocking'
    label 'Rust (blocking)'
    language 'rust'
    language_label 'Rust'
    variant 'Blocking'
    code :rust
    order 18

    private

    def rust_mode
      :blocking
    end
  end
end

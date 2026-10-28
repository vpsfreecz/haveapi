require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RustClient < HaveAPI::ClientExample
    class << self
      def available?(context)
        context&.profile&.language == :rust
      end

      def detail_levels_for(kind, context:, result:, auth_method: nil, auth_description: nil)
        adapter_detail_levels_for(adapter: context.profile.adapter, kind:, context:, result:,
                                  mode: rust_mode, auth_method:, auth_description:)
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

    def rust_mode
      self.class.rust_mode
    end

    def render_rust(kind, rendering_context: context, **)
      unless self.class.available?(rendering_context)
        return { status: :limitation, reason: 'A Rust API client documentation profile is required.' }.freeze
      end

      rendering_context.profile.adapter.render(kind:, context: rendering_context, mode: rust_mode, **)
    end
  end

  class RustAsyncClient < RustClient
    id 'rust-async'
    label 'Rust API client (async)'
    language 'rust'
    language_label 'Rust'
    variant 'Async'
    code :rust
    order 17

    def self.rust_mode
      :async
    end
  end

  class RustBlockingClient < RustClient
    id 'rust-blocking'
    label 'Rust API client (blocking)'
    language 'rust'
    language_label 'Rust'
    variant 'Blocking'
    code :rust
    order 18

    def self.rust_mode
      :blocking
    end
  end
end

begin
  require 'haveapi/schema'
rescue LoadError
  raise HaveAPI::TypeScriptClient::Error,
        'shared haveapi-client schema API is unavailable; prepare the component bundle from this source release'
end

module HaveAPI::TypeScriptClient
  # Keep the generator API/error boundary while sharing one portable format.
  module Snapshot
    unless defined?(HaveAPI::Schema::Snapshot) && HaveAPI::Schema.respond_to?(:source_identity)
      raise Error, 'loaded haveapi-client does not provide the required shared schema API'
    end

    KEYS = HaveAPI::Schema::Snapshot::KEYS
    PROSE = HaveAPI::Schema::Snapshot::PROSE

    %i[canonical canonical_value sha256 load validate sanitize from_description from_envelope version! endpoint! safe_path? safe_segments? child_context sanitization_context machine_endpoint! validate_machine_endpoint validate_machine_endpoints].each do |name|
      define_singleton_method(name) do |*args, **kwargs, &block|
        HaveAPI::Schema::Snapshot.public_send(name, *args, **kwargs, &block)
      rescue HaveAPI::Schema::Error => e
        raise Error, e.message
      end
    end

    def self.fetch(**)
      HaveAPI::Schema::Capture.fetch(**)
    rescue HaveAPI::Schema::Error => e
      raise Error, e.message
    end
  end
end

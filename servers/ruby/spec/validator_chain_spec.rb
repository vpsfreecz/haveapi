# frozen_string_literal: true

module HaveAPI::Validators
  class CloneProbe < HaveAPI::Validator
    name :clone_probe
    takes :clone_probe

    class << self
      attr_accessor :seen
    end

    self.seen = []

    def setup
      @message = 'invalid'
    end

    def describe
      {}
    end

    def valid?(_v)
      self.class.seen << object_id
      true
    end
  end
end

describe HaveAPI::ValidatorChain do
  it 'validates with per-call validator clones' do
    chain = described_class.new(clone_probe: true)
    original = chain.instance_variable_get(:@validators).first

    HaveAPI::Validators::CloneProbe.seen.clear
    expect(chain.validate('value', {})).to be true

    expect(HaveAPI::Validators::CloneProbe.seen).not_to include(original.object_id)
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Validators::Inclusion do
  subject(:validator) do
    described_class.new(
      { values: values, message: 'not included' },
      value,
      other_params
    )
  end

  let(:other_params) { Struct.new(:params).new({}) }

  context 'with an array of values' do
    let(:values) { %w[archive stream] }

    it 'uses exact membership' do
      expect(described_class.new(
               { values: values, message: 'not included' },
               'archive',
               other_params
             )).to be_valid
      expect(described_class.new(
               { values: values, message: 'not included' },
               :archive,
               other_params
             )).not_to be_valid
    end
  end

  context 'with a map of labeled values' do
    let(:values) { { archive: 'Archive', stream: 'Stream' } }

    context 'with a matching string value' do
      let(:value) { 'archive' }

      it { is_expected.to be_valid }
    end

    context 'with a missing string value' do
      let(:value) { 'incremental_stream' }

      it { is_expected.not_to be_valid }
    end
  end

  context 'with a numeric map key parsed from JSON' do
    let(:values) { { '1': 'One', '2': 'Two' } }
    let(:value) { 1 }

    it { is_expected.to be_valid }
  end
end

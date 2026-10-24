require 'spec_helper'

describe HaveAPI::ClientExample::Context, '#with' do
  let(:sample) { { request: { payload: { 'items' => [0, false, '', nil] } } } }
  let(:profile) { Object.new.freeze }

  def parent_context(resource_count)
    action = { input: { parameters: { payload: { type: 'Custom' } } }, examples: [sample] }
    description = {
      resources: resource_count.times.to_h do |index|
        ["resource#{index}", { description: "Resource #{index}", actions: { 'show' => action } }]
      end
    }
    described_class.new(version: '1', host: 'example.test', base_url: 'http://example.test/benchmark/api/',
                        version_url: 'http://example.test/benchmark/api/v1/', description:,
                        resource_path: ['resource0'], resource: description[:resources]['resource0'],
                        action_name: 'show', action:, sample:)
  end

  def allocated_derivations(parent, changes, count: 40)
    # Taking the minimum of repeated batches avoids incidental VM bookkeeping
    # spikes. Expectations and fixture construction stay outside this loop.
    Array.new(3) do
      before = GC.stat(:total_allocated_objects)
      count.times { parent.with(**changes) }
      GC.stat(:total_allocated_objects) - before
    end.min
  end

  it 'shares every unchanged field and owns a different snapshot for a new request' do
    parent = parent_context(8)
    other_request = parent_context(8)
    children = [parent.with(profile:), parent.with(sample:)]
    fields = %i[version host base_url version_url description resource_path resource action_name action sample profile]

    children.each_with_index do |child, index|
      changed = index == 0 ? :profile : :sample
      (fields - [changed]).each do |field|
        expect(child.public_send(field)).to equal(parent.public_send(field))
      end
      expect(child).to be_frozen
    end
    expect(other_request.description).to eq(parent.description)
    expect(other_request.description).not_to equal(parent.description)
    expect(other_request.description[:resources]).not_to equal(parent.description[:resources])
    replacement = parent.with(description: parent.description)
    expect(replacement.description).to eq(parent.description)
    expect(replacement.description).not_to equal(parent.description)
  end

  it 'keeps allocations independent of unrelated description size for small changes' do
    small = parent_context(8)
    large = parent_context(128)
    changes = [{ profile: }, { sample: }]
    [small, large].each do |parent|
      changes.each { |change| 80.times { parent.with(**change) } }
    end

    changes.each do |change|
      small_allocations = allocated_derivations(small, change)
      large_allocations = allocated_derivations(large, change)
      # CRuby 3.4 allocates 200/200 objects for profile changes and 560/560 for
      # samples at these sizes. The original constructor path grows from 12,560
      # to 151,760. Allow 32 extra objects per derivation for VM bookkeeping;
      # identity assertions independently forbid whole-description copies.
      expect(large_allocations).to be <= small_allocations + (40 * 32)
      [small, large].each do |parent|
        expect(parent.with(**change).description).to equal(parent.description)
      end
    end
  end
end

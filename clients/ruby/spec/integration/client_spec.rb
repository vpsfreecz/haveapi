# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Client do
  let(:base_url) { TEST_SERVER.base_url }

  it 'exposes versions and compatibility' do
    client = described_class.new(base_url)

    versions = client.versions
    expect(versions[:default]).to eq('1.0')
    expect(versions[:versions]).to include('1.0')
    expect(client.compatible?).to(
      satisfy { |value| [:compatible, :imperfect, false].include?(value) }
    )
  end

  it 'filters docs until authenticated' do
    unauthenticated = described_class.new(base_url)
    unauthenticated.setup

    expect { unauthenticated.project }.to raise_error(NoMethodError)

    authenticated = described_class.new(base_url)
    authenticated.authenticate(:basic, user: 'user', password: 'pass')

    expect { authenticated.project }.not_to raise_error
    expect(authenticated.project).to be_a(HaveAPI::Client::Resource)
  end

  it 'supports CRUD flow for projects' do
    client = described_class.new(base_url)
    client.authenticate(:basic, user: 'user', password: 'pass')

    projects = client.project.list
    expect(projects).to be_a(Array)
    expect(projects.size).to be >= 2

    project = client.project.find(projects.first.id)
    expect(project.id).to eq(projects.first.id)

    created = client.project.create(name: 'Gamma')
    expect(created.id).to be_a(Integer)
    expect(created.name).to eq('Gamma')
  end

  it 'handles nested task resources' do
    client = described_class.new(base_url)
    client.authenticate(:basic, user: 'user', password: 'pass')

    project = client.project.list.first
    tasks = client.project.task.list(project.id)
    expect(tasks).to be_a(Array)

    task = client.project(project.id).task.create(label: 'Do it')
    expect(task.id).to be_a(Integer)
    expect(task.label).to eq('Do it')
  end

  it 'raises validation error on missing required params' do
    client = described_class.new(base_url)
    client.authenticate(:basic, user: 'user', password: 'pass')

    expect { client.project.create({}) }
      .to raise_error(HaveAPI::Client::ValidationError)
  end

  it 'supports blocking actions and action state polling' do
    client = described_class.new(base_url)
    client.authenticate(:basic, user: 'user', password: 'pass')

    project = client.project.create(name: 'Blocky')
    task = client.project(project.id).task.create(label: 'Run me')

    response = client.project.task.run(project.id, task.id, meta: { block: false })
    expect(response.meta[:action_state_id]).to be_a(Integer)

    result = response.wait_for_completion(interval: 0.05, update_in: 0.05, timeout: 2)
    expect(result).to be(true)
  end

  it 'surfaces HaveAPI errors as ActionFailed' do
    client = described_class.new(base_url)

    expect { client.test.fail }
      .to raise_error(HaveAPI::Client::ActionFailed) do |err|
        expect(err.response.message).to eq('forced failure')
        expect(err.response.errors).to include(:base)
      end
  end
end

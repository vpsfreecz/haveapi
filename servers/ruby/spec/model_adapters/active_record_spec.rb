# frozen_string_literal: true

require 'spec_helper'
require 'active_record'
require 'sqlite3'
require_relative '../../lib/haveapi/model_adapters/active_record'

module ARAdapterSpec
  class Environment < ActiveRecord::Base
    has_many :groups, class_name: 'ARAdapterSpec::Group'
  end

  class Group < ActiveRecord::Base
    belongs_to :environment, class_name: 'ARAdapterSpec::Environment', optional: true
    has_many :users, class_name: 'ARAdapterSpec::User'
  end

  class User < ActiveRecord::Base
    belongs_to :group, class_name: 'ARAdapterSpec::Group', optional: true

    validates :name, length: { minimum: 3, maximum: 20 }
    validates :email, format: { with: /\A.+@.+\z/ }
    validates :role, inclusion: { in: %w[user admin] }
    validates :state, exclusion: { in: %w[banned] }
    validates :age, numericality: {
      greater_than_or_equal_to: 18,
      less_than_or_equal_to: 100
    }
    validates :score, numericality: { equal_to: 7 }
    validates :name, presence: true
  end
end

describe HaveAPI::ModelAdapters::ActiveRecord do
  api do
    env_resource = define_resource(:Environment) do
      version 1
      auth false
      model ARAdapterSpec::Environment

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }

        output(:object_list) do
          integer :id
          string :label
        end

        def exec
          self.class.model.order(id: :asc).to_a
        end
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :label
          string :note
        end

        def exec
          self.class.model.find(params['environment_id'])
        end
      end
    end

    group_resource = define_resource(:Group) do
      version 1
      auth false
      model ARAdapterSpec::Group

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }

        output(:object_list) do
          integer :id
          string :label
        end

        def exec
          self.class.model.order(id: :asc).to_a
        end
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :label
          string :note
          resource env_resource
        end

        def exec
          self.class.model.find(params['group_id'])
        end
      end
    end

    define_resource(:User) do
      version 1
      auth false
      model ARAdapterSpec::User

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }

        output(:object_list) do
          integer :id
          string :name
        end

        def exec
          with_pagination(self.class.model.order(id: :asc)).to_a
        end
      end

      define_action(:IndexDesc, superclass: HaveAPI::Actions::Default::Index) do
        route 'desc'
        authorize { allow }

        output(:object_list) do
          integer :id
          string :name
        end

        def exec
          with_desc_pagination(self.class.model.order(id: :desc)).to_a
        end
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :name
          resource group_resource
        end

        def exec
          id = params['user_id'].to_i
          with_includes(self.class.model.where(id: id)).take!
        end
      end

      define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
        authorize { allow }

        input do
          string :name
          string :email
          string :role
          string :state
          integer :age
          integer :score
        end

        def exec
          {}
        end
      end
    end
  end

  default_version 1

  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.verbose = false

    ActiveRecord::Schema.define do
      create_table :environments do |t|
        t.string :label, null: false
        t.string :note
      end

      create_table :groups do |t|
        t.string :label, null: false
        t.string :note
        t.integer :environment_id
      end

      create_table :users do |t|
        t.string :name
        t.string :email
        t.integer :age
        t.integer :score
        t.string :role
        t.string :state
        t.integer :group_id
      end
    end
  end

  before do
    ARAdapterSpec::User.delete_all
    ARAdapterSpec::Group.delete_all
    ARAdapterSpec::Environment.delete_all
  end

  let(:dummy_action) do
    Class.new do
      include HaveAPI::ModelAdapters::ActiveRecord::Action::InstanceMethods

      def self.model
        ARAdapterSpec::User
      end

      def input
        {}
      end
    end.new
  end

  def create_user(attrs = {})
    defaults = {
      name: 'user',
      email: 'user@example.com',
      role: 'user',
      state: 'active',
      age: 20,
      score: 7
    }

    ARAdapterSpec::User.create!(defaults.merge(attrs))
  end

  def action_class(resource, action)
    klass, = find_action(1, resource, action)
    klass
  end

  def fetch_validator(validators, klass, short_name)
    validators[klass] || validators[short_name.to_sym] || validators[short_name.to_s]
  end

  it 'translates ActiveModel validators to HaveAPI validators' do
    app
    create_action = action_class(:User, :create)

    name_validators = create_action.input[:name].describe(nil)[:validators]
    name_length = fetch_validator(name_validators, 'HaveAPI::Validators::Length', :length)
    expect(name_length).to be_a(Hash)
    expect(name_length[:min]).to eq(3)
    expect(name_length[:max]).to eq(20)
    expect(fetch_validator(name_validators, 'HaveAPI::Validators::Presence', :present)).to be_nil

    email_validators = create_action.input[:email].describe(nil)[:validators]
    expect(fetch_validator(email_validators, 'HaveAPI::Validators::Format', :format)).to be_a(Hash)

    role_validators = create_action.input[:role].describe(nil)[:validators]
    role_inclusion = fetch_validator(role_validators, 'HaveAPI::Validators::Inclusion', :include)
    expect(role_inclusion).to be_a(Hash)
    expect(role_inclusion[:values]).to include('user', 'admin')

    state_validators = create_action.input[:state].describe(nil)[:validators]
    state_exclusion = fetch_validator(state_validators, 'HaveAPI::Validators::Exclusion', :exclude)
    expect(state_exclusion).to be_a(Hash)
    expect(state_exclusion[:values]).to include('banned')

    age_validators = create_action.input[:age].describe(nil)[:validators]
    age_number = fetch_validator(age_validators, 'HaveAPI::Validators::Numericality', :number)
    expect(age_number).to be_a(Hash)
    expect(age_number[:min]).to eq(18)
    expect(age_number[:max]).to eq(100)

    score_validators = create_action.input[:score].describe(nil)[:validators]
    score_acceptance = fetch_validator(score_validators, 'HaveAPI::Validators::Acceptance', :accept)
    expect(score_acceptance).to be_a(Hash)
    expect(score_acceptance[:value]).to eq(7)
  end

  it 'parses nested includes and drops unknown associations' do
    parsed = dummy_action.ar_parse_includes(%w[group group__environment foo bar__baz])

    expect(parsed).to include(:group)
    expect(parsed.any? { |v| v.is_a?(Hash) && v.has_key?(:group) }).to be(true)

    nested = parsed.detect { |v| v.is_a?(Hash) && v.has_key?(:group) }
    expect(nested[:group].flatten).to include(:environment)

    expect(parsed).not_to include(:foo)
    expect(parsed).not_to include(:bar)
  end

  it 'returns unresolved associations without includes' do
    environment = ARAdapterSpec::Environment.create!(label: 'env', note: 'ENV_NOTE')
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GRP_NOTE', environment: environment)
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", {}, input: ''

    expect(api_response).to be_ok
    ret = api_response[:user]
    group_data = ret[:group]

    expect(group_data[:_meta][:resolved]).to be(false)
    expect(group_data).to include(id: group.id, label: group.label)
    expect(group_data).not_to have_key(:note)
  end

  it 'resolves direct associations when included' do
    environment = ARAdapterSpec::Environment.create!(label: 'env', note: 'ENV_NOTE')
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GRP_NOTE', environment: environment)
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", { _meta: { includes: 'group' } }, input: ''

    expect(api_response).to be_ok
    ret = api_response[:user]
    group_data = ret[:group]

    expect(group_data[:_meta][:resolved]).to be(true)
    expect(group_data[:note]).to eq('GRP_NOTE')
    expect(group_data[:environment][:_meta][:resolved]).to be(false)
    expect(group_data[:environment]).not_to have_key(:note)
  end

  it 'resolves nested associations when included' do
    environment = ARAdapterSpec::Environment.create!(label: 'env', note: 'ENV_NOTE')
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GRP_NOTE', environment: environment)
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", { _meta: { includes: 'group__environment' } }, input: ''

    expect(api_response).to be_ok
    ret = api_response[:user]
    group_data = ret[:group]
    env_data = group_data[:environment]

    expect(group_data[:_meta][:resolved]).to be(true)
    expect(env_data[:_meta][:resolved]).to be(true)
    expect(env_data[:note]).to eq('ENV_NOTE')
  end

  it 'cleans resource input ids and maps invalid values to validation errors' do
    environment = ARAdapterSpec::Environment.create!(id: 1, label: 'env')

    expect(described_class::Input.clean(ARAdapterSpec::Environment, 1, {})).to eq(environment)
    expect(described_class::Input.clean(ARAdapterSpec::Environment, '1', {})).to eq(environment)
    expect(described_class::Input.clean(ARAdapterSpec::Environment, 1.0, {})).to eq(environment)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, 'abc', {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, '', {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, 1.2, {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, false, {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, true, {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, 9999, {})
    end.to raise_error(HaveAPI::ValidationError, /resource not found/)
  end

  it 'applies ascending pagination with with_pagination' do
    5.times do |i|
      create_user(
        id: i + 1,
        name: "user#{i + 1}",
        email: "user#{i + 1}@example.com",
        age: 20 + i
      )
    end

    get '/v1/users', { user: { from_id: 2, limit: 2 } }, input: ''

    expect(api_response).to be_ok
    ids = api_response[:users].map { |u| u[:id] }
    expect(ids).to eq([3, 4])
  end

  it 'applies descending pagination with with_desc_pagination' do
    5.times do |i|
      create_user(
        id: i + 1,
        name: "user#{i + 1}",
        email: "user#{i + 1}@example.com",
        age: 20 + i
      )
    end

    get '/v1/users/desc', { user: { from_id: 4, limit: 2 } }, input: ''

    expect(api_response).to be_ok
    ids = api_response[:users].map { |u| u[:id] }
    expect(ids).to eq([3, 2])
  end

  it 'raises when paginating a composite primary key model' do
    allow(ARAdapterSpec::User).to receive(:primary_key).and_return(%w[a b])

    expect { dummy_action.with_asc_pagination }.to raise_error(RuntimeError, /composite primary key/)
  end
end

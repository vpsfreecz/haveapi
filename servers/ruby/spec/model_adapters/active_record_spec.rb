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

  class FilteredMember < ActiveRecord::Base
    self.table_name = 'users'

    belongs_to :group, class_name: 'ARAdapterSpec::Group', optional: true
  end

  class HiddenAccount < ActiveRecord::Base
    self.table_name = 'hidden_accounts'
  end

  class Invoice < ActiveRecord::Base
    belongs_to :hidden_account, class_name: 'ARAdapterSpec::HiddenAccount'
  end

  class StringAccount < ActiveRecord::Base
    self.primary_key = 'uuid'
  end

  class Dataset < ActiveRecord::Base
    has_many :snapshots, class_name: 'ARAdapterSpec::Snapshot'
  end

  class Snapshot < ActiveRecord::Base
    belongs_to :dataset, class_name: 'ARAdapterSpec::Dataset'
  end

  class SnapshotLink < ActiveRecord::Base
    belongs_to :snapshot, class_name: 'ARAdapterSpec::Snapshot'
  end
end

describe HaveAPI::ModelAdapters::ActiveRecord do
  api do
    snapshot_resource = nil

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
          self.class.model.find(path_params['environment_id'])
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

        def prepare
          group = self.class.model.find(path_params['group_id'])
          error!('access denied') if group.note == 'PRIVATE_GROUP_NOTE'
        end

        def exec
          self.class.model.find(path_params['group_id'])
        end
      end
    end

    filtered_group_resource = define_resource(:FilteredGroup) do
      version 1
      auth false
      model ARAdapterSpec::Group

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize do
          output blacklist: [:note]
          allow
        end

        output(:object_list) do
          integer :id
          string :label
          string :note
        end

        def exec
          self.class.model.order(id: :asc).to_a
        end
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize do
          output blacklist: [:note]
          allow
        end

        output(:object) do
          integer :id
          string :label
          string :note
        end

        def exec
          self.class.model.find(path_params['filtered_group_id'])
        end
      end
    end

    define_resource(:FilteredMember) do
      version 1
      auth false
      model ARAdapterSpec::FilteredMember

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :name
          resource filtered_group_resource, name: :group
        end

        def exec
          with_includes(self.class.model.where(id: path_params['filtered_member_id'])).take!
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
          id = path_params['user_id'].to_i
          with_includes(self.class.model.where(id: id)).take!
        end
      end

      define_action(:PublicShow, superclass: HaveAPI::Actions::Default::Show) do
        route 'public/{user_id}/show'

        authorize do
          output whitelist: [:name]
          allow
        end

        output(:object) do
          integer :id
          string :name
        end

        def exec
          self.class.model.find(path_params['user_id'])
        end
      end

      define_action(:PublicIndex, superclass: HaveAPI::Actions::Default::Index) do
        route 'public/list'

        authorize do
          output whitelist: [:name]
          allow
        end

        output(:object_list) do
          integer :id
          string :name
        end

        def exec
          self.class.model.order(id: :asc).to_a
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

    hidden_account_resource = define_resource(:HiddenAccount) do
      version 1
      auth false
      model ARAdapterSpec::HiddenAccount

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { deny }

        output(:object_list) do
          integer :id
          string :label
        end

        def exec
          self.class.model.order(id: :asc).to_a
        end
      end

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { deny }

        output(:object) do
          integer :id
          string :label
          string :private_reference
        end

        def exec
          self.class.model.find(path_params['hidden_account_id'])
        end
      end
    end

    define_resource(:Invoice) do
      version 1
      auth false
      model ARAdapterSpec::Invoice

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :label
          resource hidden_account_resource
        end

        def exec
          self.class.model.find(path_params['invoice_id'])
        end
      end

      define_action(:Update, superclass: HaveAPI::Actions::Default::Update) do
        authorize { allow }

        input(:hash) do
          resource hidden_account_resource
        end

        output(:hash) do
          bool :assigned
        end

        def exec
          { assigned: input.has_key?(:hidden_account) }
        end
      end
    end

    define_resource(:Dataset) do
      version 1
      auth false
      route 'datasets/{dataset_id}'
      model ARAdapterSpec::Dataset

      snapshot_resource = define_resource(:Snapshot) do
        auth false
        model ARAdapterSpec::Snapshot

        define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
          authorize { allow }

          output(:object_list) do
            integer :id
            string :label
          end

          def exec
            self.class.model.where(dataset_id: path_params['dataset_id']).order(id: :asc).to_a
          end
        end

        define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
          resolve ->(snapshot) { [snapshot.dataset_id, snapshot.id] }
          authorize do |_u, params|
            snapshot = ARAdapterSpec::Snapshot.find_by(id: params['snapshot_id'])

            if snapshot && snapshot.dataset_id == params['dataset_id'].to_i
              allow
            else
              deny
            end
          end

          output(:object) do
            integer :id
            string :label
          end

          def prepare
            snapshot = self.class.model.find(path_params['snapshot_id'])
            error!('wrong dataset') if snapshot.dataset_id != path_params['dataset_id'].to_i
          end

          def exec
            self.class.model.find(path_params['snapshot_id'])
          end
        end
      end
    end

    define_resource(:SnapshotLink) do
      version 1
      auth false
      model ARAdapterSpec::SnapshotLink

      define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        authorize { allow }

        output(:object) do
          integer :id
          string :label
          resource snapshot_resource
        end

        def exec
          id = path_params['snapshot_link_id']
          with_includes(self.class.model.where(id:)).take!
        end
      end

      define_action(:Update, superclass: HaveAPI::Actions::Default::Update) do
        authorize { allow }

        input(:hash) do
          resource snapshot_resource
        end

        output(:hash) do
          bool :assigned
        end

        def exec
          { assigned: input[:snapshot].is_a?(ARAdapterSpec::Snapshot) }
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

      create_table :hidden_accounts do |t|
        t.string :label, null: false
        t.string :private_reference, null: false
      end

      create_table :invoices do |t|
        t.string :label, null: false
        t.integer :hidden_account_id, null: false
      end

      create_table :string_accounts, id: false do |t|
        t.string :uuid, primary_key: true
        t.string :label, null: false
      end

      create_table :datasets do |t|
        t.string :label, null: false
      end

      create_table :snapshots do |t|
        t.integer :dataset_id, null: false
        t.string :label, null: false
      end

      create_table :snapshot_links do |t|
        t.integer :snapshot_id, null: false
        t.string :label, null: false
      end
    end
  end

  before do
    ARAdapterSpec::User.delete_all
    ARAdapterSpec::Group.delete_all
    ARAdapterSpec::Environment.delete_all
    ARAdapterSpec::Invoice.delete_all
    ARAdapterSpec::HiddenAccount.delete_all
    ARAdapterSpec::StringAccount.delete_all
    ARAdapterSpec::SnapshotLink.delete_all
    ARAdapterSpec::Snapshot.delete_all
    ARAdapterSpec::Dataset.delete_all
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

  def create_snapshot_link
    dataset = ARAdapterSpec::Dataset.create!(label: 'dataset')
    snapshot = ARAdapterSpec::Snapshot.create!(dataset:, label: 'snapshot')
    link = ARAdapterSpec::SnapshotLink.create!(snapshot:, label: 'link')

    [dataset, snapshot, link]
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
    parsed = dummy_action.ar_parse_includes(%w[group group__environment group__missing foo bar__baz])

    expect(parsed).to include(:group)
    expect(parsed.any? { |v| v.is_a?(Hash) && v.has_key?(:group) }).to be(true)

    nested = parsed.detect { |v| v.is_a?(Hash) && v.has_key?(:group) }
    expect(nested[:group].flatten).to include(:environment)

    expect(nested[:group].flatten).not_to include(:missing)
    expect(parsed).not_to include(:foo)
    expect(parsed).not_to include(:bar)
  end

  it 'drops overly deep include paths before building ActiveRecord includes' do
    deep_path = (['missing'] * 5_000).join('__')

    expect(dummy_action.ar_parse_includes([deep_path])).to eq([])
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

  it 'passes path params to associated show prepare when included' do
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GROUP_NOTE')
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", { _meta: { includes: 'group' } }, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    group_data = api_response[:user][:group]
    expect(group_data[:_meta][:resolved]).to be(true)
    expect(group_data).to include(id: group.id, label: 'grp', note: 'GROUP_NOTE')
  end

  it 'applies associated show output restrictions when included' do
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GROUP_SECRET')
    user = create_user(name: 'user', group: group)

    get "/v1/filtered_groups/#{group.id}", {}, input: ''
    expect(api_response).to be_ok
    expect(api_response[:filtered_group]).not_to have_key(:note)

    get "/v1/filtered_members/#{user.id}", { _meta: { includes: 'group' } }, input: ''

    expect(api_response).to be_ok
    group_data = api_response[:filtered_member][:group]
    expect(group_data[:_meta][:resolved]).to be(true)
    expect(group_data).to include(id: group.id, label: 'grp')
    expect(group_data).not_to have_key(:note)
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

  it 'uses full nested paths for associated show prepare' do
    _dataset, snapshot, link = create_snapshot_link

    get "/v1/snapshot_links/#{link.id}", { _meta: { includes: 'snapshot' } }, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    snapshot_data = api_response[:snapshot_link][:snapshot]
    expect(snapshot_data[:_meta][:resolved]).to be(true)
    expect(snapshot_data).to include(id: snapshot.id, label: 'snapshot')
  end

  it 'uses full nested paths when authorizing resource input records' do
    _dataset, snapshot, link = create_snapshot_link

    put "/v1/snapshot_links/#{link.id}", {
      snapshot_link: {
        snapshot: snapshot.id
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:snapshot_link]).to eq(assigned: true)
  end

  it 'drops invalid nested include paths from requests' do
    group = ARAdapterSpec::Group.create!(label: 'grp', note: 'GRP_NOTE')
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", { _meta: { includes: 'group__missing' } }, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:user][:group][:_meta][:resolved]).to be(false)
  end

  it 'does not expose unresolved associated resources denied by their show action' do
    account = ARAdapterSpec::HiddenAccount.create!(
      label: 'VIP billing account',
      private_reference: 'SECRET-ACCOUNT-REF'
    )
    invoice = ARAdapterSpec::Invoice.create!(label: 'public invoice', hidden_account: account)

    get "/v1/hidden_accounts/#{account.id}", {}, input: ''
    expect(last_response.status).to eq(403)
    expect(api_response).to be_failed

    get "/v1/invoices/#{invoice.id}", {}, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    account_data = api_response[:invoice][:hidden_account]
    expect(account_data).to eq(_meta: { resolved: false, authorized: false })
  end

  it 'does not resolve associated resources denied by their show action' do
    account = ARAdapterSpec::HiddenAccount.create!(
      label: 'VIP billing account',
      private_reference: 'SECRET-ACCOUNT-REF'
    )
    invoice = ARAdapterSpec::Invoice.create!(label: 'public invoice', hidden_account: account)

    get "/v1/invoices/#{invoice.id}", { _meta: { includes: 'hidden_account' } }, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    account_data = api_response[:invoice][:hidden_account]
    expect(account_data).to eq(_meta: { resolved: false, authorized: false })
  end

  it 'does not expose unresolved associated resources denied during show prepare' do
    group = ARAdapterSpec::Group.create!(
      label: 'private group',
      note: 'PRIVATE_GROUP_NOTE'
    )
    user = create_user(name: 'user', group: group)

    get "/v1/groups/#{group.id}", {}, input: ''
    expect(api_response).to be_failed

    get "/v1/users/#{user.id}", {}, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    group_data = api_response[:user][:group]
    expect(group_data).to eq(_meta: { resolved: false, authorized: false })
  end

  it 'does not resolve associated resources denied during show prepare' do
    group = ARAdapterSpec::Group.create!(
      label: 'private group',
      note: 'PRIVATE_GROUP_NOTE'
    )
    user = create_user(name: 'user', group: group)

    get "/v1/users/#{user.id}", { _meta: { includes: 'group' } }, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    group_data = api_response[:user][:group]
    expect(group_data).to eq(_meta: { resolved: false, authorized: false })
  end

  it 'does not expose object path params when id output is filtered' do
    user = create_user(name: 'user')

    get "/v1/users/public/#{user.id}/show", {}, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:user]).to eq(name: 'user')
    expect(api_response.response[:_meta]).not_to have_key(:path_params)
  end

  it 'does not expose object-list path params when id output is filtered' do
    create_user(id: 1, name: 'user1')
    create_user(id: 2, name: 'user2')

    get '/v1/users/public/list', {}, input: ''

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:users].map { |user| user[:name] }).to eq(%w[user1 user2])
    expect(api_response[:users]).to all(satisfy { |user| !user[:_meta].has_key?(:path_params) })
  end

  it 'rejects resource input records denied by their show action' do
    account = ARAdapterSpec::HiddenAccount.create!(
      label: 'VIP billing account',
      private_reference: 'SECRET-ACCOUNT-REF'
    )
    invoice = ARAdapterSpec::Invoice.create!(label: 'public invoice', hidden_account: account)

    put "/v1/invoices/#{invoice.id}", {
      invoice: {
        hidden_account: account.id
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq(400)
    expect(api_response).not_to be_ok
    expect(api_response.errors[:hidden_account]).to include('resource not found')
  end

  it 'cleans resource input ids and maps invalid values to validation errors' do
    environment = ARAdapterSpec::Environment.create!(id: 1, label: 'env')

    expect(described_class::Input.clean(ARAdapterSpec::Environment, 1, {})).to eq(environment)
    expect(described_class::Input.clean(ARAdapterSpec::Environment, '1', {})).to eq(environment)
    expect(described_class::Input.clean(ARAdapterSpec::Environment, 1.0, {})).to eq(environment)
    expect(described_class::Input.clean(ARAdapterSpec::Environment, '', { nullable: true })).to be_nil
    expect(described_class::Input.clean(ARAdapterSpec::Environment, '   ', { nullable: true })).to be_nil

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

  it 'rejects nil results from non-nullable custom resource fetchers' do
    fetch = proc { |id| find_by(id:) }

    expect do
      described_class::Input.clean(ARAdapterSpec::Environment, 9999, { fetch: })
    end.to raise_error(HaveAPI::ValidationError, /resource not found/)

    cleaned = described_class::Input.clean(
      ARAdapterSpec::Environment,
      9999,
      { fetch:, nullable: true }
    )
    expect(cleaned).to be_nil
  end

  it 'rejects arrays and hashes for singular string primary-key resources' do
    ARAdapterSpec::StringAccount.create!(uuid: 'acct-alpha', label: 'Alpha')
    ARAdapterSpec::StringAccount.create!(uuid: 'acct-beta', label: 'Beta')

    expect do
      described_class::Input.clean(ARAdapterSpec::StringAccount, %w[acct-alpha acct-beta], {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)

    expect do
      described_class::Input.clean(ARAdapterSpec::StringAccount, { id: 'acct-alpha' }, {})
    end.to raise_error(HaveAPI::ValidationError, /not a valid id/)
  end

  it 'rejects non-string includes metadata entries' do
    app
    show_action = action_class(:User, :show)
    includes_param = show_action.meta(:global).input[:includes]

    expect do
      includes_param.clean([{ bad: 'shape' }])
    end.to raise_error(HaveAPI::ValidationError, /only strings/)
  end

  it 'keeps hash adapter resource cleaning compatible with adapter arguments' do
    expect(HaveAPI::ModelAdapters::Hash::Input.clean({}, { id: 1 }, {})).to eq({ id: 1 })
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

  it 'rejects excessive pagination limits' do
    get '/v1/users', { user: { limit: HaveAPI::Actions::Paginable::MAX_LIMIT + 1 } }, input: ''

    expect(last_response.status).to eq(400)
    expect(api_response).not_to be_ok
    expect(api_response.errors[:limit].first).to include(
      "range <0, #{HaveAPI::Actions::Paginable::MAX_LIMIT}>"
    )
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

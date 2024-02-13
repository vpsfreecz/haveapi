class SetupDatabase < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string      :username,   null: false, limit: 50, unique: true
      t.string      :password,   null: false, limit: 100
      t.boolean     :is_admin,   null: false, default: 0
      t.timestamps
    end

    create_table :auth_tokens do |t|
      t.references  :user,       null: false
      t.string      :token,      null: false, limit: 100, unique: true
      t.datetime    :valid_to,   null: true
      t.string      :label,      null: true
      t.integer     :use_count,  null: false, default: 0
      t.integer     :lifetime,   null: false
      t.integer     :interval,   null: true
      t.datetime    :created_at, null: true
    end
  end
end

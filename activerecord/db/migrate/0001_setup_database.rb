class SetupDatabase < ActiveRecord::Migration
  def change
    create_table :dummies do |t|
      t.string :name, null: false, limit: 50
    end
  end
end

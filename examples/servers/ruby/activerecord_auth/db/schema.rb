# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 1) do

  create_table "auth_tokens", force: true do |t|
    t.integer  "user_id",                            null: false
    t.string   "token",      limit: 100,             null: false
    t.datetime "valid_to"
    t.string   "label"
    t.integer  "use_count",              default: 0, null: false
    t.integer  "lifetime",                           null: false
    t.integer  "interval"
    t.datetime "created_at"
  end

  create_table "users", force: true do |t|
    t.string   "username",   limit: 50,                  null: false
    t.string   "password",   limit: 100,                 null: false
    t.boolean  "is_admin",               default: false, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end

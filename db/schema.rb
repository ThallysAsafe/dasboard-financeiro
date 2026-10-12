# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_10_12_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "recurring_transactions", force: :cascade do |t|
    t.integer "kind", null: false
    t.string "description", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.integer "day_of_month", null: false
    t.date "start_date", null: false
    t.date "end_date"
    t.string "category"
    t.boolean "active", default: true, null: false
    t.date "last_generated_on"
    t.bigint "user_id", null: false
    t.bigint "wallet_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "active"], name: "index_recurring_transactions_on_user_id_and_active"
    t.index ["user_id"], name: "index_recurring_transactions_on_user_id"
    t.index ["wallet_id"], name: "index_recurring_transactions_on_wallet_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "kind", null: false
    t.string "description", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.date "date", null: false
    t.string "category"
    t.bigint "user_id", null: false
    t.bigint "wallet_id"
    t.bigint "recurring_transaction_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recurring_transaction_id", "date"], name: "index_transactions_on_recurring_transaction_and_date", unique: true
    t.index ["recurring_transaction_id"], name: "index_transactions_on_recurring_transaction_id"
    t.index ["user_id", "kind", "date"], name: "index_transactions_on_user_id_and_kind_and_date"
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.index ["wallet_id"], name: "index_transactions_on_wallet_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "token_version", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "wallets", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "initial_balance", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_wallets_on_user_id"
  end

  add_foreign_key "recurring_transactions", "users"
  add_foreign_key "recurring_transactions", "wallets"
  add_foreign_key "transactions", "recurring_transactions"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "wallets"
  add_foreign_key "wallets", "users"
end

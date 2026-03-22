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

ActiveRecord::Schema[8.0].define(version: 2026_03_19_045856) do
  create_table "tokens", force: :cascade do |t|
    t.string "mint", null: false
    t.string "name"
    t.string "symbol"
    t.string "icon"
    t.integer "decimals"
    t.string "token_program"
    t.boolean "verified", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mint"], name: "index_tokens_on_mint", unique: true
  end

  create_table "transfers", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "signature"
    t.string "recipient", null: false
    t.bigint "amount_lamports", null: false
    t.decimal "amount_sol", null: false
    t.string "network", default: "mainnet", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["signature"], name: "index_transfers_on_signature", unique: true
    t.index ["status"], name: "index_transfers_on_status"
    t.index ["user_id", "created_at"], name: "index_transfers_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_transfers_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "wallet_address", null: false
    t.string "nonce"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "nonce_expires_at"
    t.index ["wallet_address"], name: "index_users_on_wallet_address", unique: true
  end

  add_foreign_key "transfers", "users"
end

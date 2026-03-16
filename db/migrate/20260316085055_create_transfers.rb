class CreateTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :transfers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :signature
      t.string :recipient, null: false
      t.integer :amount_lamports, null: false
      t.decimal :amount_sol, null: false
      t.string :network, null: false, default: "mainnet"
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end
    add_index :transfers, :signature, unique: true
  end
end

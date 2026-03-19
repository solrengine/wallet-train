class ChangeAmountLamportsToBigintInTransfers < ActiveRecord::Migration[8.0]
  def change
    change_column :transfers, :amount_lamports, :bigint, null: false
    add_index :transfers, :status
    add_index :transfers, [:user_id, :created_at]
  end
end

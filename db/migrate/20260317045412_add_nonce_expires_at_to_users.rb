class AddNonceExpiresAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :nonce_expires_at, :datetime
  end
end

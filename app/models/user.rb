class User < ApplicationRecord
  has_many :transfers, dependent: :destroy

  validates :wallet_address, presence: true, uniqueness: true,
    format: { with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/, message: "is not a valid Solana address" }

  before_create :generate_nonce

  def generate_nonce!
    update!(nonce: generate_nonce)
  end

  private

  def generate_nonce
    self.nonce = SecureRandom.hex(16)
  end
end

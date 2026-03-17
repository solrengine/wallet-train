class User < ApplicationRecord
  NONCE_TTL = 5.minutes

  has_many :transfers, dependent: :destroy

  validates :wallet_address, presence: true, uniqueness: true,
    format: { with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/, message: "is not a valid Solana address" }

  before_create :set_nonce

  def generate_nonce!
    update!(nonce: SecureRandom.hex(16), nonce_expires_at: NONCE_TTL.from_now)
  end

  def nonce_valid?
    nonce.present? && nonce_expires_at.present? && nonce_expires_at > Time.current
  end

  private

  def set_nonce
    self.nonce = SecureRandom.hex(16)
    self.nonce_expires_at = NONCE_TTL.from_now
  end
end

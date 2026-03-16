class Transfer < ApplicationRecord
  belongs_to :user

  validates :recipient, presence: true,
    format: { with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/, message: "is not a valid Solana address" }
  validates :amount_lamports, presence: true, numericality: { greater_than: 0 }
  validates :amount_sol, presence: true, numericality: { greater_than: 0 }
  validates :network, presence: true
  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc).limit(10) }

  def sol_amount_display
    amount_sol.to_f.round(6)
  end

  def short_signature
    return nil unless signature
    "#{signature[0..7]}...#{signature[-4..]}"
  end

  def short_recipient
    "#{recipient[0..3]}...#{recipient[-4..]}"
  end

  def confirmed?
    status == "confirmed" || status == "finalized"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending" || status == "submitted"
  end
end

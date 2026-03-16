class Token < ApplicationRecord
  validates :mint, presence: true, uniqueness: true

  # Find or fetch token metadata from Jupiter.
  def self.find_or_fetch(mint)
    find_by(mint: mint) || fetch_and_persist(mint)
  end

  # Bulk find or fetch — only hits Jupiter for mints not yet in the DB.
  def self.find_or_fetch_many(mints)
    existing = where(mint: mints).index_by(&:mint)
    missing = mints - existing.keys

    missing.each do |mint|
      token = fetch_and_persist(mint)
      existing[mint] = token if token
    end

    existing
  end

  def short_address
    "#{mint[0..3]}...#{mint[-4..]}"
  end

  def display_name
    name.presence || short_address
  end

  def display_symbol
    symbol.presence || "???"
  end

  private_class_method def self.fetch_and_persist(mint)
    data = JupiterClient.fetch_token(mint)
    return create_unknown(mint) unless data

    create!(
      mint: mint,
      name: data[:name],
      symbol: data[:symbol],
      icon: data[:icon],
      decimals: data[:decimals],
      token_program: data[:token_program],
      verified: data[:verified] || false
    )
  rescue ActiveRecord::RecordNotUnique
    find_by(mint: mint)
  rescue => e
    Rails.logger.warn("Failed to persist token #{mint}: #{e.message}")
    nil
  end

  # Persist unknown tokens too so we don't keep hitting Jupiter for them
  private_class_method def self.create_unknown(mint)
    create!(mint: mint, verified: false)
  rescue ActiveRecord::RecordNotUnique
    find_by(mint: mint)
  end
end

require "json"

# Client for Jupiter's free token API (lite-api.jup.ag).
# Used for token metadata (persisted to DB) and prices (cached short-term).
class JupiterClient
  include Solrengine::Rpc::SslHttp

  BASE_URL = "https://lite-api.jup.ag/tokens/v2"

  # Fetch token metadata by mint address.
  # Returns a hash with :name, :symbol, :icon, :decimals, :token_program, :verified
  # or nil if not found.
  def self.fetch_token(mint)
    new.fetch_token(mint)
  end

  # Fetch current USD prices for multiple mints.
  # Returns a hash { mint => usd_price }
  def self.fetch_prices(mints)
    new.fetch_prices(mints)
  end

  def fetch_token(mint)
    data = search(mint)
    return nil unless data

    {
      name: data["name"],
      symbol: data["symbol"],
      icon: data["icon"],
      decimals: data["decimals"],
      token_program: data["tokenProgram"],
      verified: data["isVerified"] == true
    }
  end

  def fetch_prices(mints)
    prices = {}

    # Batch by searching each mint — the lite search API returns usdPrice
    mints.each do |mint|
      price = fetch_price(mint)
      prices[mint] = price if price
    end

    prices
  end

  private

  def fetch_price(mint)
    Rails.cache.fetch("token_price/#{mint}", expires_in: 1.minute) do
      data = search(mint)
      data&.dig("usdPrice")&.to_f
    end
  end

  def search(mint)
    uri = URI.parse("#{BASE_URL}/search?query=#{mint}")
    http = ssl_http(uri)

    response = http.request(Net::HTTP::Get.new(uri))
    return nil unless response.is_a?(Net::HTTPSuccess)

    tokens = JSON.parse(response.body)
    return nil unless tokens.is_a?(Array) && tokens.any?

    # Only return exact mint match
    tokens.find { |t| t["id"] == mint }
  rescue => e
    Rails.logger.warn("Jupiter API error for #{mint}: #{e.message}")
    nil
  end
end

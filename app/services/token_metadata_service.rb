require "net/http"
require "json"

# Resolves SPL token metadata (name, symbol, icon) via Jupiter's token API.
# Results are cached to avoid repeated API calls.
class TokenMetadataService
  JUPITER_API = "https://lite-api.jup.ag/tokens/v2"

  # Well-known tokens as fallback when Jupiter is unavailable
  KNOWN_TOKENS = {
    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" => { name: "USD Coin", symbol: "USDC", decimals: 6 },
    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB" => { name: "Tether USD", symbol: "USDT", decimals: 6 },
    "So11111111111111111111111111111111111111112"      => { name: "Wrapped SOL", symbol: "SOL", decimals: 9 },
    "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"   => { name: "Jupiter", symbol: "JUP", decimals: 6 },
    "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263" => { name: "Bonk", symbol: "BONK", decimals: 5 },
    "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs" => { name: "Ether (Wormhole)", symbol: "ETH", decimals: 8 }
  }.freeze

  def initialize
    @client = SolanaClient.new
  end

  # Fetches token accounts for a wallet and enriches them with metadata.
  # Returns an array of hashes with: mint, symbol, name, icon, ui_amount, decimals
  def token_balances_for(wallet_address)
    accounts = @client.get_token_accounts(wallet_address)
    return [] if accounts.empty?

    mints = accounts.map { |a| a[:mint] }
    metadata = fetch_metadata_for(mints)

    accounts.map do |account|
      meta = metadata[account[:mint]] || {}
      {
        mint: account[:mint],
        name: meta[:name] || shorten_address(account[:mint]),
        symbol: meta[:symbol] || "???",
        icon: meta[:icon],
        ui_amount: account[:ui_amount],
        ui_amount_string: account[:ui_amount_string],
        decimals: account[:decimals]
      }
    end.sort_by { |t| -t[:ui_amount] }
  end

  private

  def fetch_metadata_for(mints)
    result = {}

    mints.each do |mint|
      meta = fetch_single_metadata(mint)
      result[mint] = meta if meta
    end

    result
  end

  def fetch_single_metadata(mint)
    # Check cache first (1 day TTL — token metadata rarely changes)
    Rails.cache.fetch("token_metadata/#{mint}", expires_in: 1.day) do
      # Check well-known tokens
      if KNOWN_TOKENS[mint]
        KNOWN_TOKENS[mint]
      else
        fetch_from_jupiter(mint)
      end
    end
  end

  def fetch_from_jupiter(mint)
    uri = URI.parse("#{JUPITER_API}/search?query=#{mint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    return nil unless response.is_a?(Net::HTTPSuccess)

    tokens = JSON.parse(response.body)
    token = tokens.is_a?(Array) ? tokens.first : nil
    return nil unless token

    {
      name: token["name"],
      symbol: token["symbol"],
      icon: token["icon"],
      decimals: token["decimals"]
    }
  rescue => e
    Rails.logger.warn("Jupiter API error for #{mint}: #{e.message}")
    nil
  end

  def shorten_address(address)
    "#{address[0..3]}...#{address[-4..]}"
  end
end

require "json"

# Resolves SPL token metadata (name, symbol, icon, price) via Jupiter's token API.
# Results are cached to avoid repeated API calls.
class TokenMetadataService
  include SslHttpClient

  JUPITER_API = "https://lite-api.jup.ag/tokens/v2"
  SOL_MINT = "So11111111111111111111111111111111111111112"

  def initialize
    @client = SolanaClient.new
  end

  # Fetches token accounts for a wallet and enriches them with metadata.
  # Includes native SOL as the first entry.
  def token_balances_for(wallet_address)
    # Fetch SOL balance and SPL tokens in parallel-ish
    sol_balance = @client.get_balance(wallet_address)
    accounts = @client.get_token_accounts(wallet_address)

    # Collect all mints including SOL
    all_mints = [ SOL_MINT ] + accounts.map { |a| a[:mint] }
    metadata = fetch_metadata_for(all_mints)

    tokens = []

    # Add SOL as first entry
    if sol_balance
      sol_meta = metadata[SOL_MINT] || {}
      tokens << {
        mint: SOL_MINT,
        name: "Solana",
        symbol: "SOL",
        icon: sol_meta[:icon],
        ui_amount: sol_balance,
        ui_amount_string: format_amount(sol_balance),
        decimals: 9,
        usd_price: sol_meta[:usd_price],
        usd_value: sol_meta[:usd_price] ? (sol_balance * sol_meta[:usd_price]).round(2) : nil
      }
    end

    # Add SPL tokens
    accounts.each do |account|
      meta = metadata[account[:mint]] || {}
      usd_value = meta[:usd_price] ? (account[:ui_amount] * meta[:usd_price]).round(2) : nil

      tokens << {
        mint: account[:mint],
        name: meta[:name] || shorten_address(account[:mint]),
        symbol: meta[:symbol] || "???",
        icon: meta[:icon],
        ui_amount: account[:ui_amount],
        ui_amount_string: account[:ui_amount_string],
        decimals: account[:decimals],
        usd_price: meta[:usd_price],
        usd_value: usd_value
      }
    end

    # Sort by USD value descending; tokens without USD value go to the bottom
    tokens.sort_by { |t| -(t[:usd_value] || -1) }
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
    # Cache metadata + price together (5 min TTL for price freshness)
    Rails.cache.fetch("token_meta_v2/#{mint}", expires_in: 5.minutes) do
      fetch_from_jupiter(mint)
    end
  end

  def fetch_from_jupiter(mint)
    uri = URI.parse("#{JUPITER_API}/search?query=#{mint}")
    http = ssl_http(uri)

    response = http.request(Net::HTTP::Get.new(uri))

    return nil unless response.is_a?(Net::HTTPSuccess)

    tokens = JSON.parse(response.body)
    token = tokens.is_a?(Array) ? tokens.first : nil
    return nil unless token

    {
      name: token["name"],
      symbol: token["symbol"],
      icon: token["icon"],
      decimals: token["decimals"],
      usd_price: token["usdPrice"]&.to_f
    }
  rescue => e
    Rails.logger.warn("Jupiter API error for #{mint}: #{e.message}")
    nil
  end

  def shorten_address(address)
    "#{address[0..3]}...#{address[-4..]}"
  end

  def format_amount(amount)
    if amount >= 1000
      number_with_delimiter(amount.round(2))
    elsif amount >= 1
      amount.round(4).to_s
    else
      amount.round(6).to_s
    end
  end

  def number_with_delimiter(number)
    whole, decimal = number.to_s.split(".")
    whole_with_commas = whole.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    decimal ? "#{whole_with_commas}.#{decimal}" : whole_with_commas
  end
end

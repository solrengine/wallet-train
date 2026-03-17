# Assembles token balances with metadata (from DB) and prices (from cache/Jupiter).
class TokenMetadataService
  SOL_MINT = "So11111111111111111111111111111111111111112"

  def initialize
    @client = SolanaClient.new
  end

  def token_balances_for(wallet_address)
    sol_balance = @client.get_balance(wallet_address)
    accounts = @client.get_token_accounts(wallet_address)

    all_mints = [ SOL_MINT ] + accounts.map { |a| a[:mint] }

    token_records = Token.find_or_fetch_many(all_mints)

    # Prices only available on mainnet
    prices = SolanaConfig.mainnet? ? JupiterClient.fetch_prices(all_mints) : {}

    tokens = []

    if sol_balance
      sol_token = token_records[SOL_MINT]
      sol_price = prices[SOL_MINT]
      entry = build_entry(
        token: sol_token,
        ui_amount: sol_balance,
        ui_amount_string: format_amount(sol_balance),
        usd_price: sol_price
      )
      entry[:name] = "Solana"
      entry[:symbol] = "SOL"
      tokens << entry
    end

    accounts.each do |account|
      token = token_records[account[:mint]]
      price = prices[account[:mint]]
      tokens << build_entry(
        token: token,
        ui_amount: account[:ui_amount],
        ui_amount_string: account[:ui_amount_string],
        usd_price: price
      )
    end

    tokens.sort_by { |t| -(t[:usd_value] || -1) }
  end

  private

  def build_entry(token:, ui_amount:, ui_amount_string:, usd_price:)
    usd_value = usd_price ? (ui_amount * usd_price).round(2) : nil

    {
      mint: token&.mint,
      name: token&.display_name || "Unknown",
      symbol: token&.display_symbol || "???",
      icon: token&.icon,
      ui_amount: ui_amount,
      ui_amount_string: ui_amount_string,
      decimals: token&.decimals,
      usd_price: usd_price,
      usd_value: usd_value
    }
  end

  def format_amount(amount)
    if amount >= 1000
      whole, decimal = amount.round(2).to_s.split(".")
      "#{whole.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}.#{decimal}"
    elsif amount >= 1
      amount.round(4).to_s
    else
      amount.round(6).to_s
    end
  end
end

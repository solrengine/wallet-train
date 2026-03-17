# Aggregates all on-chain data for a wallet with caching.
class WalletPortfolioService
  def initialize(wallet_address)
    @wallet_address = wallet_address
    @solana_client = SolanaClient.new
    @token_service = TokenMetadataService.new
  end

  def tokens
    Rails.cache.fetch(cache_key("tokens"), expires_in: 45.seconds) do
      @token_service.token_balances_for(@wallet_address)
    end
  end

  def total_usd_value
    tokens.sum { |t| t[:usd_value] || 0 }
  end

  def recent_transactions
    Rails.cache.fetch(cache_key("recent_txs"), expires_in: 30.seconds) do
      @solana_client.get_recent_signatures(@wallet_address, limit: 5)
    end
  end

  private

  def cache_key(suffix)
    "wallet/#{@wallet_address}/#{suffix}"
  end
end

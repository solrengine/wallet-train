# Aggregates all on-chain data for a wallet with caching.
class WalletPortfolioService
  def initialize(wallet_address)
    @wallet_address = wallet_address
    @solana_client = SolanaClient.new
    @token_service = TokenMetadataService.new
  end

  def sol_balance
    Rails.cache.fetch(cache_key("sol_balance"), expires_in: 30.seconds) do
      @solana_client.get_balance(@wallet_address)
    end
  end

  def token_balances
    Rails.cache.fetch(cache_key("token_balances"), expires_in: 1.minute) do
      @token_service.token_balances_for(@wallet_address)
    end
  end

  def recent_transactions
    Rails.cache.fetch(cache_key("recent_txs"), expires_in: 30.seconds) do
      @solana_client.get_recent_signatures(@wallet_address, limit: 10)
    end
  end

  private

  def cache_key(suffix)
    "wallet/#{@wallet_address}/#{suffix}"
  end
end

# Aggregates all on-chain data for a wallet with caching.
class WalletPortfolioService
  NETWORK_RPC_URLS = {
    "mainnet" => "https://api.mainnet-beta.solana.com",
    "devnet"  => "https://api.devnet.solana.com",
    "testnet" => "https://api.testnet.solana.com"
  }.freeze

  def initialize(wallet_address, network: "mainnet")
    @wallet_address = wallet_address
    @network = network
    rpc_url = NETWORK_RPC_URLS[@network] || NETWORK_RPC_URLS["mainnet"]
    @solana_client = SolanaClient.new(rpc_url: rpc_url)
    @token_service = TokenMetadataService.new(network: @network, rpc_url: rpc_url)
  end

  def tokens
    Rails.cache.fetch(cache_key("tokens_v2"), expires_in: 45.seconds) do
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
    "wallet/#{@network}/#{@wallet_address}/#{suffix}"
  end
end

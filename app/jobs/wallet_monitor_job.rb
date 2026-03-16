# Polls Solana for new transactions and broadcasts updates via Turbo Streams.
# Re-enqueues itself for a limited time after the user loads the dashboard.
class WalletMonitorJob < ApplicationJob
  queue_as :default

  POLL_INTERVAL = 15.seconds
  MONITOR_DURATION = 10.minutes

  def perform(wallet_address, started_at: nil, network: "mainnet")
    started_at ||= Time.current.iso8601

    # Mark as active
    Rails.cache.write("wallet_monitor/#{wallet_address}/active", true, expires_in: MONITOR_DURATION)

    rpc_url = WalletPortfolioService::NETWORK_RPC_URLS[network] || WalletPortfolioService::NETWORK_RPC_URLS["mainnet"]
    client = SolanaClient.new(rpc_url: rpc_url)

    # Fetch latest signature
    signatures = client.get_recent_signatures(wallet_address, limit: 1)
    latest_sig = signatures.first&.dig(:signature)

    # Compare with last known signature
    cache_key = "wallet_monitor/#{wallet_address}/last_sig"
    previous_sig = Rails.cache.read(cache_key)

    if latest_sig && latest_sig != previous_sig
      Rails.cache.write(cache_key, latest_sig, expires_in: 1.hour)

      if previous_sig # Don't broadcast on first poll (just establishing baseline)
        broadcast_update(wallet_address)
      end
    end

    # Re-enqueue if within monitoring window
    elapsed = Time.current - Time.parse(started_at)
    if elapsed < MONITOR_DURATION
      self.class.set(wait: POLL_INTERVAL).perform_later(wallet_address, started_at: started_at, network: network)
    else
      Rails.cache.delete("wallet_monitor/#{wallet_address}/active")
    end
  end

  private

  def broadcast_update(wallet_address)
    # Clear cached portfolio data for all networks
    %w[mainnet devnet testnet].each do |net|
      Rails.cache.delete("wallet/#{net}/#{wallet_address}/tokens_v2")
      Rails.cache.delete("wallet/#{net}/#{wallet_address}/recent_txs")
    end

    portfolio = WalletPortfolioService.new(wallet_address)
    tokens = portfolio.tokens
    total_usd = portfolio.total_usd_value
    transactions = portfolio.recent_transactions

    stream = "wallet_#{wallet_address}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "portfolio_value",
      partial: "dashboard/portfolio_value",
      locals: { total_usd: total_usd }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "token_list",
      partial: "dashboard/token_list",
      locals: { tokens: tokens }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "recent_activity",
      partial: "dashboard/recent_activity",
      locals: { transactions: transactions, wallet_address: wallet_address }
    )
  end
end

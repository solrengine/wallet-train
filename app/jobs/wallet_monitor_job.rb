# Starts a WebSocket subscription to Solana for real-time account changes.
# Falls back to polling if WebSocket is unavailable.
class WalletMonitorJob < ApplicationJob
  queue_as :default

  MONITOR_DURATION = 10.minutes

  def perform(wallet_address, network: "mainnet")
    cache_key = "wallet_monitor/#{wallet_address}/active"
    return if Rails.cache.read(cache_key) # Already monitoring

    Rails.cache.write(cache_key, true, expires_in: MONITOR_DURATION)

    ws_url = ws_url_for(network)

    if ws_url.present?
      monitor_via_websocket(wallet_address, network, ws_url)
    else
      monitor_via_polling(wallet_address, network)
    end
  ensure
    Rails.cache.delete("wallet_monitor/#{wallet_address}/active")
  end

  private

  def monitor_via_websocket(wallet_address, network, ws_url)
    monitor = SolanaWebsocketMonitor.new(wallet_address, network: network)
    monitor.start

    # Run for MONITOR_DURATION then stop
    sleep MONITOR_DURATION
    monitor.stop
  end

  def monitor_via_polling(wallet_address, network, started_at: Time.current)
    client = SolanaClient.new(rpc_url: SolanaConfig.rpc_url(network))

    cache_key = "wallet_monitor/#{wallet_address}/last_sig"
    signatures = client.get_recent_signatures(wallet_address, limit: 1)
    latest_sig = signatures.first&.dig(:signature)

    previous_sig = Rails.cache.read(cache_key)

    if latest_sig && latest_sig != previous_sig
      Rails.cache.write(cache_key, latest_sig, expires_in: 1.hour)
      broadcast_update(wallet_address, network) if previous_sig
    end

    if Time.current - started_at < MONITOR_DURATION
      sleep 15
      monitor_via_polling(wallet_address, network, started_at: started_at)
    end
  end

  def broadcast_update(wallet_address, network)
    SolanaConfig::NETWORKS.each do |net|
      Rails.cache.delete("wallet/#{net}/#{wallet_address}/tokens_v2")
      Rails.cache.delete("wallet/#{net}/#{wallet_address}/recent_txs")
    end

    portfolio = WalletPortfolioService.new(wallet_address, network: network)
    stream = "wallet_#{wallet_address}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "portfolio_value",
      partial: "dashboard/portfolio_value",
      locals: { total_usd: portfolio.total_usd_value }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "token_list",
      partial: "dashboard/token_list",
      locals: { tokens: portfolio.tokens }
    )

    explorer_base = network == "mainnet" ? "https://solscan.io" : "https://explorer.solana.com"
    explorer_cluster = network == "mainnet" ? "" : "?cluster=#{network}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "recent_activity",
      partial: "dashboard/recent_activity",
      locals: { transactions: portfolio.recent_transactions, wallet_address: wallet_address, explorer_base: explorer_base, explorer_cluster: explorer_cluster }
    )
  end

  def ws_url_for(network)
    SolanaConfig.ws_url(network)
  end
end

# Starts a WebSocket subscription to Solana for real-time account changes.
# Falls back to polling if WebSocket is unavailable.
# Runs as long as the dashboard is open (re-triggered on page load).
class WalletMonitorJob < ApplicationJob
  queue_as :default

  MONITOR_DURATION = 10.minutes

  def perform(wallet_address)
    cache_key = "wallet_monitor/#{wallet_address}/active"
    return if Rails.cache.read(cache_key)

    Rails.cache.write(cache_key, true, expires_in: MONITOR_DURATION)

    ws_url = SolanaConfig.ws_url
    if ws_url.present?
      monitor_via_websocket(wallet_address)
    else
      monitor_via_polling(wallet_address)
    end
  ensure
    Rails.cache.delete("wallet_monitor/#{wallet_address}/active")
  end

  private

  def monitor_via_websocket(wallet_address)
    monitor = SolanaWebsocketMonitor.new(wallet_address)
    monitor.start
    sleep MONITOR_DURATION
    monitor.stop
  end

  def monitor_via_polling(wallet_address, started_at: Time.current)
    client = SolanaClient.new
    cache_key = "wallet_monitor/#{wallet_address}/last_sig"

    signatures = client.get_recent_signatures(wallet_address, limit: 1)
    latest_sig = signatures.first&.dig(:signature)
    previous_sig = Rails.cache.read(cache_key)

    if latest_sig && latest_sig != previous_sig
      Rails.cache.write(cache_key, latest_sig, expires_in: 1.hour)
      broadcast_update(wallet_address) if previous_sig
    end

    if Time.current - started_at < MONITOR_DURATION
      sleep 15
      monitor_via_polling(wallet_address, started_at: started_at)
    end
  end

  def broadcast_update(wallet_address)
    Rails.cache.delete("wallet/#{wallet_address}/tokens")
    Rails.cache.delete("wallet/#{wallet_address}/recent_txs")

    portfolio = WalletPortfolioService.new(wallet_address)
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

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "recent_activity",
      partial: "dashboard/recent_activity",
      locals: { transactions: portfolio.recent_transactions, wallet_address: wallet_address }
    )
  end
end

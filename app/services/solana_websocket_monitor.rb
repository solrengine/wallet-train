require "json"
require "websocket-client-simple"

# Subscribes to Solana WebSocket RPC for real-time account changes.
# Broadcasts updates via Turbo Streams when the account balance changes.
class SolanaWebsocketMonitor
  RECONNECT_DELAY = 5

  def initialize(wallet_address)
    @wallet_address = wallet_address
    @ws_url = Solrengine::Rpc.configuration.ws_url
    @running = false
    @account_changed = false
    @mutex = Mutex.new
  end

  def start
    return if @running
    @running = true

    # WebSocket runs in a thread, sets a flag when account changes
    Thread.new { websocket_loop }

    # Main polling loop checks the flag and broadcasts
    broadcast_loop
  end

  def stop
    @running = false
    @ws&.close
  end

  # Called from the WebSocket thread — must be public for callback access
  def flag_changed!
    @mutex.synchronize { @account_changed = true }
  end

  private

  def websocket_loop
    while @running
      begin
        connect_and_listen
      rescue => e
        Rails.logger.error("[SolanaWS] Connection error: #{e.message}")
        sleep RECONNECT_DELAY if @running
      end
    end
  end

  def connect_and_listen
    @ws = WebSocket::Client::Simple.connect(@ws_url)
    ws = @ws
    wallet_address = @wallet_address
    monitor = self

    ws.on :open do
      Rails.logger.info("[SolanaWS] Connected for #{wallet_address} on #{Solrengine::Rpc.configuration.network}")
      ws.send({
        jsonrpc: "2.0",
        id: 1,
        method: "accountSubscribe",
        params: [
          wallet_address,
          { encoding: "jsonParsed", commitment: "confirmed" }
        ]
      }.to_json)
    end

    ws.on :message do |msg|
      begin
        parsed = JSON.parse(msg.data)
        if parsed["id"] == 1 && parsed["result"]
          Rails.logger.info("[SolanaWS] Subscribed with ID #{parsed['result']}")
        elsif parsed["method"] == "accountNotification"
          Rails.logger.info("[SolanaWS] Account changed for #{wallet_address}")
          monitor.flag_changed!
        end
      rescue => e
        Rails.logger.error("[SolanaWS] Message parse error: #{e.message}")
      end
    end

    ws.on :error do |e|
      Rails.logger.error("[SolanaWS] Error: #{e.message}")
    end

    ws.on :close do
      Rails.logger.info("[SolanaWS] Disconnected")
    end

    sleep 1 while @running && !ws.closed?
  end

  # Runs on the main thread — checks the flag every second
  def broadcast_loop
    while @running
      changed = @mutex.synchronize do
        val = @account_changed
        @account_changed = false
        val
      end

      broadcast_update if changed

      sleep 1
    end
  end

  def broadcast_update
    Rails.logger.info("[SolanaWS] Broadcasting update for #{@wallet_address}")

    # Wait for the RPC node to reflect the confirmed state
    sleep 3

    Rails.cache.delete("wallet/#{@wallet_address}/tokens")
    Rails.cache.delete("wallet/#{@wallet_address}/recent_txs")

    portfolio = WalletPortfolioService.new(@wallet_address)
    stream = "wallet_#{@wallet_address}"

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
      locals: { transactions: portfolio.recent_transactions, wallet_address: @wallet_address }
    )

    Rails.logger.info("[SolanaWS] Broadcast complete for #{@wallet_address}")
  end
end

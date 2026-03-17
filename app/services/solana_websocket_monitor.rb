require "json"
require "websocket-client-simple"

# Subscribes to Solana WebSocket RPC for real-time account changes.
# Runs as a background thread and broadcasts updates via Turbo Streams.
class SolanaWebsocketMonitor
  RECONNECT_DELAY = 5

  def initialize(wallet_address, network: "mainnet")
    @wallet_address = wallet_address
    @network = network
    @ws_url = SolanaConfig.ws_url(network)
    @running = false
  end

  def start
    return if @running
    @running = true

    Thread.new do
      while @running
        begin
          connect_and_listen
        rescue => e
          Rails.logger.error("[SolanaWS] Connection error: #{e.message}")
          sleep RECONNECT_DELAY if @running
        end
      end
    end
  end

  def stop
    @running = false
    @ws&.close
  end

  private

  def connect_and_listen
    @ws = WebSocket::Client::Simple.connect(@ws_url)
    ws = @ws
    monitor = self

    ws.on :open do
      Rails.logger.info("[SolanaWS] Connected for #{monitor.send(:@wallet_address)}")
      ws.send({
        jsonrpc: "2.0",
        id: 1,
        method: "accountSubscribe",
        params: [
          monitor.send(:@wallet_address),
          { encoding: "jsonParsed", commitment: "confirmed" }
        ]
      }.to_json)
    end

    ws.on :message do |msg|
      monitor.send(:handle_message, msg.data)
    end

    ws.on :error do |e|
      Rails.logger.error("[SolanaWS] Error: #{e.message}")
    end

    ws.on :close do
      Rails.logger.info("[SolanaWS] Disconnected")
    end

    sleep 1 while @running && !ws.closed?
  end

  def handle_message(data)
    parsed = JSON.parse(data)

    if parsed["id"] == 1 && parsed["result"]
      Rails.logger.info("[SolanaWS] Subscribed with ID #{parsed['result']}")
      return
    end

    if parsed["method"] == "accountNotification"
      Rails.logger.info("[SolanaWS] Account changed for #{@wallet_address}")
      broadcast_update
    end
  rescue => e
    Rails.logger.error("[SolanaWS] Message parse error: #{e.message}")
  end

  def broadcast_update
    SolanaConfig::NETWORKS.each do |net|
      Rails.cache.delete("wallet/#{net}/#{@wallet_address}/tokens_v2")
      Rails.cache.delete("wallet/#{net}/#{@wallet_address}/recent_txs")
    end

    portfolio = WalletPortfolioService.new(@wallet_address, network: @network)
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

    explorer_base = @network == "mainnet" ? "https://solscan.io" : "https://explorer.solana.com"
    explorer_cluster = @network == "mainnet" ? "" : "?cluster=#{@network}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream, target: "recent_activity",
      partial: "dashboard/recent_activity",
      locals: { transactions: portfolio.recent_transactions, wallet_address: @wallet_address, explorer_base: explorer_base, explorer_cluster: explorer_cluster }
    )
  end
end

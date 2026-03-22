Solrengine::Realtime.on_account_change = ->(wallet_address) {
  Rails.cache.delete("wallet/#{wallet_address}/tokens")
  Rails.cache.delete("wallet/#{wallet_address}/recent_txs")

  portfolio = Solrengine::Tokens::Portfolio.new(wallet_address)
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
}

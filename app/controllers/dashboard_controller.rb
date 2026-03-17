class DashboardController < ApplicationController
  def show
    @wallet_address = current_user.wallet_address
    @short_address = "#{@wallet_address[0..3]}...#{@wallet_address[-4..]}"

    # Touch updated_at so the WebSocket monitor knows this user is active
    current_user.touch

    # Clear cache if user has a recent transfer (last 2 minutes)
    # to ensure fresh on-chain data after sending
    if current_user.transfers.where("created_at > ?", 2.minutes.ago).exists?
      Rails.cache.delete("wallet/#{@wallet_address}/tokens")
      Rails.cache.delete("wallet/#{@wallet_address}/recent_txs")
    end

    portfolio = WalletPortfolioService.new(@wallet_address)
    @tokens = portfolio.tokens
    @total_usd = portfolio.total_usd_value
    @transactions = portfolio.recent_transactions
  end
end

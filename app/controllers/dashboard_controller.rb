class DashboardController < ApplicationController
  def show
    @wallet_address = current_user.wallet_address
    @short_address = "#{@wallet_address[0..3]}...#{@wallet_address[-4..]}"

    portfolio = WalletPortfolioService.new(@wallet_address)
    @tokens = portfolio.tokens
    @total_usd = portfolio.total_usd_value
    @transactions = portfolio.recent_transactions

    # Start background monitoring for new transactions
    WalletMonitorJob.perform_later(@wallet_address) unless monitoring?(@wallet_address)
  end

  private

  def monitoring?(wallet_address)
    Rails.cache.read("wallet_monitor/#{wallet_address}/active")
  end
end

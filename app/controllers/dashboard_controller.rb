class DashboardController < ApplicationController
  def show
    @wallet_address = current_user.wallet_address
    @short_address = "#{@wallet_address[0..3]}...#{@wallet_address[-4..]}"

    portfolio = WalletPortfolioService.new(@wallet_address)
    @tokens = portfolio.tokens
    @total_usd = portfolio.total_usd_value
    @transactions = portfolio.recent_transactions
  end
end

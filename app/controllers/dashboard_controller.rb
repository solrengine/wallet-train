class DashboardController < ApplicationController
  def show
    @wallet_address = current_user.wallet_address
    @short_address = "#{@wallet_address[0..3]}...#{@wallet_address[-4..]}"

    portfolio = WalletPortfolioService.new(@wallet_address)
    @balance = portfolio.sol_balance
    @tokens = portfolio.token_balances
    @transactions = portfolio.recent_transactions
  end
end

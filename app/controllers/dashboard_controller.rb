class DashboardController < ApplicationController
  def show
    @wallet_address = current_user.wallet_address
    @short_address = "#{@wallet_address[0..3]}...#{@wallet_address[-4..]}"
    @balance = SolanaClient.new.get_balance(@wallet_address)
  end
end

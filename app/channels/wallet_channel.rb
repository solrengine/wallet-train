class WalletChannel < ApplicationCable::Channel
  def subscribed
    wallet_address = current_user.wallet_address
    stream_from "wallet_#{wallet_address}"

    # Start monitoring this wallet for new transactions
    WalletMonitorJob.perform_later(wallet_address)
  end

  def unsubscribed
    # Cleanup happens naturally — job won't re-enqueue without subscribers
  end
end

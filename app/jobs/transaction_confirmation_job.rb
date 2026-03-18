# Polls Solana for transaction confirmation status and updates the Transfer record.
# Broadcasts status changes via Turbo Streams.
class TransactionConfirmationJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 30
  POLL_INTERVAL = 2.seconds

  def perform(transfer_id, attempt: 0)
    transfer = Transfer.find_by(id: transfer_id)
    return unless transfer&.signature
    return if transfer.confirmed? || transfer.failed?

    client = Solrengine::Rpc.client

    status_info = client.get_signature_status(transfer.signature)

    if status_info.nil?
      # Not yet seen by the network
      if attempt < MAX_ATTEMPTS
        self.class.set(wait: POLL_INTERVAL).perform_later(transfer_id, attempt: attempt + 1)
      else
        transfer.update!(status: "failed", error_message: "Transaction not confirmed after #{MAX_ATTEMPTS} attempts")
        broadcast_status(transfer)
      end
      return
    end

    if status_info["err"]
      transfer.update!(status: "failed", error_message: status_info["err"].to_s)
    else
      confirmation = status_info["confirmationStatus"]
      transfer.update!(status: confirmation || "confirmed")

      # Keep polling until finalized
      if confirmation == "processed" || confirmation == "confirmed"
        self.class.set(wait: POLL_INTERVAL).perform_later(transfer_id, attempt: attempt + 1)
      end
    end

    broadcast_status(transfer)
  end

  private

  def broadcast_status(transfer)
    Turbo::StreamsChannel.broadcast_replace_to(
      "wallet_#{transfer.user.wallet_address}",
      target: "transfer_status_#{transfer.id}",
      partial: "transfers/status",
      locals: { transfer: transfer }
    )
  end
end

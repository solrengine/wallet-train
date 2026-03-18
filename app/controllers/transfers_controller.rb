class TransfersController < ApplicationController
  def new
    @wallet_address = current_user.wallet_address
    @balance = Solrengine::Rpc.client.get_balance(@wallet_address)
  end

  def create
    recipient = params[:recipient]&.strip
    amount_sol = params[:amount_sol].to_f

    unless recipient.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)
      return render json: { error: "Invalid recipient address" }, status: :unprocessable_entity
    end

    if recipient == current_user.wallet_address
      return render json: { error: "Cannot send to yourself" }, status: :unprocessable_entity
    end

    if amount_sol <= 0
      return render json: { error: "Amount must be greater than 0" }, status: :unprocessable_entity
    end

    amount_lamports = (amount_sol * 1_000_000_000).to_i

    client = Solrengine::Rpc.client
    balance = client.get_balance(current_user.wallet_address)

    if balance.nil? || (balance * 1_000_000_000).to_i < amount_lamports + 5000
      return render json: { error: "Insufficient balance" }, status: :unprocessable_entity
    end

    blockhash = client.get_latest_blockhash
    unless blockhash
      return render json: { error: "Failed to fetch blockhash. Try again." }, status: :unprocessable_entity
    end

    transfer = current_user.transfers.create!(
      recipient: recipient,
      amount_lamports: amount_lamports,
      amount_sol: amount_sol,
      network: Solrengine::Rpc.configuration.network,
      status: "pending"
    )

    render json: {
      transfer_id: transfer.id,
      sender: current_user.wallet_address,
      recipient: recipient,
      amount_lamports: amount_lamports,
      blockhash: blockhash,
      rpc_url: Solrengine::Rpc.configuration.rpc_url
    }
  end

  def update
    transfer = current_user.transfers.find(params[:id])
    signature = params[:signature]
    status = params[:status] || "submitted"

    transfer.update!(signature: signature, status: status)

    if status == "submitted" && signature.present?
      # Clear cached portfolio so dashboard shows fresh data
      wallet = current_user.wallet_address
      Rails.cache.delete("wallet/#{wallet}/tokens")
      Rails.cache.delete("wallet/#{wallet}/recent_txs")

      Solrengine::Transactions::ConfirmationJob.perform_later(transfer.id)
    end

    render json: { success: true, transfer_id: transfer.id }
  end

  def show
    @transfer = current_user.transfers.find(params[:id])
  end

  def status
    transfer = current_user.transfers.find(params[:id])
    render json: {
      status: transfer.status,
      signature: transfer.signature,
      error_message: transfer.error_message
    }
  end
end

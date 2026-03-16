class NetworksController < ApplicationController
  NETWORKS = {
    "mainnet" => "https://api.mainnet-beta.solana.com",
    "devnet"  => "https://api.devnet.solana.com",
    "testnet" => "https://api.testnet.solana.com"
  }.freeze

  def update
    network = params[:network]

    if NETWORKS.key?(network)
      # Clear cached portfolio data when switching networks
      if session[:network] != network && current_user
        wallet = current_user.wallet_address
        Rails.cache.delete("wallet/#{wallet}/tokens_v2")
        Rails.cache.delete("wallet/#{wallet}/recent_txs")
      end

      session[:network] = network
    end

    redirect_to dashboard_path
  end
end

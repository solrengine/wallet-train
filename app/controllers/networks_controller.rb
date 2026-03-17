class NetworksController < ApplicationController
  def update
    network = params[:network]

    if SolanaConfig.valid_network?(network)
      if session[:network] != network && current_user
        wallet = current_user.wallet_address
        SolanaConfig::NETWORKS.each do |net|
          Rails.cache.delete("wallet/#{net}/#{wallet}/tokens_v2")
          Rails.cache.delete("wallet/#{net}/#{wallet}/recent_txs")
        end
      end

      session[:network] = network
    end

    redirect_to dashboard_path
  end
end

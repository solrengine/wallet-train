# Single source of truth for Solana network configuration.
# Reads from config/solana.yml which pulls from environment variables.
class SolanaConfig
  NETWORKS = %w[mainnet devnet testnet].freeze

  class << self
    def rpc_url(network = "mainnet")
      config.dig("networks", network, "rpc_url")
    end

    def ws_url(network = "mainnet")
      config.dig("networks", network, "ws_url")
    end

    def valid_network?(network)
      NETWORKS.include?(network)
    end

    private

    def config
      @config ||= Rails.application.config_for(:solana).deep_stringify_keys
    end
  end
end

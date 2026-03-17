# Single source of truth for Solana network configuration.
# Network is set at boot via SOLANA_NETWORK env var (default: mainnet).
class SolanaConfig
  class << self
    def network
      config["network"]
    end

    def rpc_url
      config.dig("networks", network, "rpc_url")
    end

    def ws_url
      config.dig("networks", network, "ws_url")
    end

    def mainnet?
      network == "mainnet"
    end

    def explorer_base
      mainnet? ? "https://solscan.io" : "https://explorer.solana.com"
    end

    def explorer_cluster
      mainnet? ? "" : "?cluster=#{network}"
    end

    private

    def config
      @config ||= Rails.application.config_for(:solana).deep_stringify_keys
    end
  end
end

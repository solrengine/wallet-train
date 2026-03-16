require "net/http"
require "json"

class SolanaClient
  DEFAULT_RPC_URL = "https://api.mainnet-beta.solana.com"

  def initialize(rpc_url: nil)
    @rpc_url = rpc_url || ENV.fetch("SOLANA_RPC_URL", DEFAULT_RPC_URL)
  end

  def get_balance(wallet_address)
    result = rpc_request("getBalance", [ wallet_address ])
    lamports = result.dig("result", "value")
    return nil unless lamports

    lamports.to_f / 1_000_000_000
  end

  private

  def rpc_request(method, params = [])
    uri = URI.parse(@rpc_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_preverify_ok, store_ctx) {
      # Accept valid certs even if CRL is unavailable
      return true if store_ctx.error == 0
      return true if store_ctx.error == OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
      false
    }
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path.empty? ? "/" : uri.path)
    request["Content-Type"] = "application/json"
    request.body = {
      jsonrpc: "2.0",
      id: 1,
      method: method,
      params: params
    }.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("Solana RPC error: #{e.class} - #{e.message}")
    {}
  end
end

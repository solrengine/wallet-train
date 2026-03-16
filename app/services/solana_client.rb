require "net/http"
require "json"

class SolanaClient
  DEFAULT_RPC_URL = "https://api.mainnet-beta.solana.com"
  SPL_TOKEN_PROGRAM = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

  def initialize(rpc_url: nil)
    @rpc_url = rpc_url || ENV.fetch("SOLANA_RPC_URL", DEFAULT_RPC_URL)
  end

  def get_balance(wallet_address)
    result = rpc_request("getBalance", [ wallet_address ])
    lamports = result.dig("result", "value")
    return nil unless lamports

    lamports.to_f / 1_000_000_000
  end

  # Fetches all SPL token accounts for a wallet.
  # Returns an array of hashes: { mint:, balance:, decimals:, ui_amount: }
  def get_token_accounts(wallet_address)
    result = rpc_request("getTokenAccountsByOwner", [
      wallet_address,
      { "programId" => SPL_TOKEN_PROGRAM },
      { "encoding" => "jsonParsed" }
    ])

    accounts = result.dig("result", "value") || []

    accounts.filter_map do |account|
      info = account.dig("account", "data", "parsed", "info")
      next unless info

      token_amount = info["tokenAmount"]
      amount = token_amount["uiAmount"].to_f
      next if amount.zero? # Skip zero-balance tokens

      {
        mint: info["mint"],
        balance: token_amount["amount"],
        decimals: token_amount["decimals"],
        ui_amount: amount,
        ui_amount_string: token_amount["uiAmountString"]
      }
    end
  end

  # Fetches recent transaction signatures for a wallet.
  # Returns an array of hashes: { signature:, slot:, block_time:, err:, memo: }
  def get_recent_signatures(wallet_address, limit: 10)
    result = rpc_request("getSignaturesForAddress", [
      wallet_address,
      { "limit" => limit }
    ])

    signatures = result.dig("result") || []

    signatures.map do |sig|
      {
        signature: sig["signature"],
        slot: sig["slot"],
        block_time: sig["blockTime"] ? Time.at(sig["blockTime"]) : nil,
        error: sig["err"],
        memo: sig["memo"],
        confirmation_status: sig["confirmationStatus"]
      }
    end
  end

  # Fetches full transaction details.
  def get_transaction(signature)
    result = rpc_request("getTransaction", [
      signature,
      { "encoding" => "jsonParsed", "maxSupportedTransactionVersion" => 0 }
    ])

    result["result"]
  end

  private

  def rpc_request(method, params = [])
    uri = URI.parse(@rpc_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_preverify_ok, store_ctx) {
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

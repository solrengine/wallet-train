require "json"

class SolanaClient
  include SslHttpClient

  def initialize(rpc_url: nil)
    @rpc_url = rpc_url || SolanaConfig.rpc_url
  end

  def get_balance(wallet_address)
    result = rpc_request("getBalance", [ wallet_address, { "commitment" => "confirmed" } ])
    lamports = result.dig("result", "value")
    return nil unless lamports

    lamports.to_f / 1_000_000_000
  end

  def get_token_accounts(wallet_address)
    result = rpc_request("getTokenAccountsByOwner", [
      wallet_address,
      { "programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" },
      { "encoding" => "jsonParsed" }
    ])

    accounts = result.dig("result", "value") || []

    accounts.filter_map do |account|
      info = account.dig("account", "data", "parsed", "info")
      next unless info

      token_amount = info["tokenAmount"]
      amount = token_amount["uiAmount"].to_f
      next if amount.zero?

      {
        mint: info["mint"],
        balance: token_amount["amount"],
        decimals: token_amount["decimals"],
        ui_amount: amount,
        ui_amount_string: token_amount["uiAmountString"]
      }
    end
  end

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

  def get_latest_blockhash
    result = rpc_request("getLatestBlockhash", [ { "commitment" => "finalized" } ])
    result.dig("result", "value", "blockhash")
  end

  def get_signature_status(signature)
    result = rpc_request("getSignatureStatuses", [ [ signature ] ])
    result.dig("result", "value", 0)
  end

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
    http = ssl_http(uri)

    request = Net::HTTP::Post.new(uri.request_uri.empty? ? "/" : uri.request_uri)
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

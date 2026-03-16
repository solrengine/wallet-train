SolanaRpcRuby.config do |c|
  c.cluster = ENV.fetch("SOLANA_RPC_URL", "https://api.mainnet-beta.solana.com")
  c.json_rpc_version = "2.0"
end

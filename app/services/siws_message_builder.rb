# Builds a SIWS (Sign In With Solana) message following the standard format.
#
# The message format is modeled after EIP-4361 (SIWE) adapted for Solana:
# https://github.com/phantom/sign-in-with-solana
class SiwsMessageBuilder
  def initialize(domain:, wallet_address:, nonce:, statement: nil, uri: nil)
    @domain = domain
    @wallet_address = wallet_address
    @nonce = nonce
    @statement = statement || "Sign in to #{domain}"
    @uri = uri || "https://#{domain}"
    @issued_at = Time.current.iso8601
  end

  def build
    lines = []
    lines << "#{@domain} wants you to sign in with your Solana account:"
    lines << @wallet_address
    lines << ""
    lines << @statement
    lines << ""
    lines << "URI: #{@uri}"
    lines << "Version: 1"
    lines << "Chain ID: mainnet"
    lines << "Nonce: #{@nonce}"
    lines << "Issued At: #{@issued_at}"
    lines.join("\n")
  end
end

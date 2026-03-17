require "ed25519"
require "base58"

# Sign In With Solana (SIWS) verification service.
#
# Verifies that a message was signed by the claimed Solana wallet address
# using Ed25519 signature verification. Also validates the message domain
# to prevent cross-site replay attacks.
class SiwsVerifier
  class VerificationError < StandardError; end

  EXPECTED_DOMAIN = Rails.application.config_for(:siws).fetch(:domain, "localhost")

  def initialize(wallet_address:, message:, signature:)
    @wallet_address = wallet_address
    @message = message
    @signature = signature
  end

  def verify!
    verify_message_format!
    verify_domain!
    verify_signature!
    true
  rescue Ed25519::VerifyError
    raise VerificationError, "Invalid signature"
  end

  def verify
    verify!
  rescue VerificationError
    false
  end

  private

  def verify_message_format!
    unless @message.include?(@wallet_address)
      raise VerificationError, "Message does not contain the claimed wallet address"
    end

    unless extract_nonce.present?
      raise VerificationError, "Message does not contain a nonce"
    end
  end

  def verify_domain!
    first_line = @message.lines.first&.strip
    unless first_line&.start_with?("#{EXPECTED_DOMAIN} wants you to sign in")
      raise VerificationError, "Message domain does not match expected domain (#{EXPECTED_DOMAIN})"
    end
  end

  def verify_signature!
    pubkey_bytes = Base58.base58_to_binary(@wallet_address, :bitcoin)
    signature_bytes = decode_signature(@signature)

    verify_key = Ed25519::VerifyKey.new(pubkey_bytes)
    verify_key.verify(signature_bytes, @message)
  end

  def extract_nonce
    match = @message.match(/Nonce: ([a-f0-9]+)/)
    match&.captures&.first
  end

  def decode_signature(signature)
    if signature.match?(/\A[0-9,\s]+\z/)
      signature.split(",").map(&:to_i).pack("C*")
    else
      Base64.decode64(signature)
    end
  end
end

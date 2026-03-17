require "test_helper"
require "ed25519"
require "base58"

class SiwsVerifierTest < ActiveSupport::TestCase
  setup do
    # Generate a real Ed25519 keypair for testing
    @signing_key = Ed25519::SigningKey.generate
    @verify_key = @signing_key.verify_key
    @wallet_address = Base58.binary_to_base58(@verify_key.to_bytes, :bitcoin)

    @nonce = SecureRandom.hex(16)
    @message = SiwsMessageBuilder.new(
      domain: "localhost",
      wallet_address: @wallet_address,
      nonce: @nonce,
      uri: "http://localhost:3000"
    ).build

    # Sign the message with the test keypair
    @signature_bytes = @signing_key.sign(@message)
    @signature_csv = @signature_bytes.bytes.join(",")
    @signature_b64 = Base64.strict_encode64(@signature_bytes)
  end

  test "verifies valid signature (Uint8Array CSV format)" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: @signature_csv
    )
    assert verifier.verify
  end

  test "verifies valid signature (Base64 format)" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: @signature_b64
    )
    assert verifier.verify
  end

  test "verify! returns true for valid signature" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: @signature_csv
    )
    assert_equal true, verifier.verify!
  end

  test "rejects invalid signature" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: "0," * 63 + "0" # 64 zero bytes
    )
    assert_not verifier.verify
  end

  test "verify! raises on invalid signature" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: "0," * 63 + "0"
    )
    assert_raises(SiwsVerifier::VerificationError) { verifier.verify! }
  end

  test "rejects message without wallet address" do
    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: "Some random message\nNonce: #{@nonce}",
      signature: @signature_csv
    )
    assert_not verifier.verify
  end

  test "rejects message without nonce" do
    message_no_nonce = "localhost wants you to sign in\n#{@wallet_address}\nNo nonce here"
    signature = @signing_key.sign(message_no_nonce)

    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: message_no_nonce,
      signature: signature.bytes.join(",")
    )
    assert_not verifier.verify
  end

  test "rejects signature from different keypair" do
    other_key = Ed25519::SigningKey.generate
    other_signature = other_key.sign(@message)

    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: @message,
      signature: other_signature.bytes.join(",")
    )
    assert_not verifier.verify
  end

  test "rejects message with wrong domain" do
    evil_message = SiwsMessageBuilder.new(
      domain: "evil.com",
      wallet_address: @wallet_address,
      nonce: @nonce
    ).build
    evil_signature = @signing_key.sign(evil_message)

    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: evil_message,
      signature: evil_signature.bytes.join(",")
    )
    assert_not verifier.verify
  end

  test "verify! raises on wrong domain" do
    evil_message = SiwsMessageBuilder.new(
      domain: "evil.com",
      wallet_address: @wallet_address,
      nonce: @nonce
    ).build
    evil_signature = @signing_key.sign(evil_message)

    verifier = SiwsVerifier.new(
      wallet_address: @wallet_address,
      message: evil_message,
      signature: evil_signature.bytes.join(",")
    )
    error = assert_raises(SiwsVerifier::VerificationError) { verifier.verify! }
    assert_includes error.message, "domain does not match"
  end
end

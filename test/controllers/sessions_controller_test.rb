require "test_helper"
require "ed25519"
require "base58"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /login renders sign-in page" do
    get login_path
    assert_response :success
  end

  test "GET /auth/nonce returns nonce for valid address" do
    get auth_nonce_path, params: { wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg" },
      headers: { "Accept" => "application/json" }

    assert_response :success
    json = JSON.parse(response.body)
    assert json["message"].present?
    assert json["nonce"].present?
    assert_includes json["message"], "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg"
  end

  test "GET /auth/nonce rejects invalid address" do
    get auth_nonce_path, params: { wallet_address: "invalid!" },
      headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
  end

  test "POST /auth/verify creates session with valid signature" do
    # Generate keypair
    signing_key = Ed25519::SigningKey.generate
    wallet_address = Base58.binary_to_base58(signing_key.verify_key.to_bytes, :bitcoin)

    # Get nonce
    get auth_nonce_path, params: { wallet_address: wallet_address },
      headers: { "Accept" => "application/json" }
    json = JSON.parse(response.body)
    message = json["message"]

    # Sign it
    signature = signing_key.sign(message)

    # Verify
    post auth_verify_path,
      params: {
        wallet_address: wallet_address,
        message: message,
        signature: signature.bytes.join(",")
      },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :success
    result = JSON.parse(response.body)
    assert result["success"]
    assert_equal wallet_address, result["wallet_address"]
  end

  test "POST /auth/verify rejects invalid signature" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    user.update!(nonce: "testnonce123")

    message = Solrengine::Auth::SiwsMessageBuilder.new(
      domain: "localhost",
      wallet_address: user.wallet_address,
      nonce: user.nonce
    ).build

    post auth_verify_path,
      params: {
        wallet_address: user.wallet_address,
        message: message,
        signature: "0," * 63 + "0"
      },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :unauthorized
  end

  test "DELETE /logout clears session" do
    # Create a logged-in session
    signing_key = Ed25519::SigningKey.generate
    wallet_address = Base58.binary_to_base58(signing_key.verify_key.to_bytes, :bitcoin)

    get auth_nonce_path, params: { wallet_address: wallet_address },
      headers: { "Accept" => "application/json" }
    message = JSON.parse(response.body)["message"]
    signature = signing_key.sign(message)

    post auth_verify_path,
      params: { wallet_address: wallet_address, message: message, signature: signature.bytes.join(",") },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :success

    # Now logout
    delete logout_path
    assert_redirected_to root_path
  end
end

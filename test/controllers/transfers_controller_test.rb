require "test_helper"
require "ed25519"
require "base58"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @signing_key = Ed25519::SigningKey.generate
    @wallet_address = Base58.binary_to_base58(@signing_key.verify_key.to_bytes, :bitcoin)
    @user = User.create!(wallet_address: @wallet_address)

    # Log in
    get solrengine_auth.nonce_path, params: { wallet_address: @wallet_address },
      headers: { "Accept" => "application/json" }
    message = JSON.parse(response.body)["message"]
    signature = @signing_key.sign(message)

    post solrengine_auth.verify_path,
      params: { wallet_address: @wallet_address, message: message, signature: signature.bytes.join(",") },
      headers: { "Accept" => "application/json" },
      as: :json
  end

  test "GET /transfers/new requires authentication" do
    delete solrengine_auth.logout_path
    get "/transfers/new"
    assert_redirected_to solrengine_auth.login_path
  end

  test "GET /transfers/new renders send form when logged in" do
    get "/transfers/new"
    assert_response :success
  end

  test "POST /transfers rejects invalid recipient" do
    post "/transfers",
      params: { recipient: "invalid!", amount_sol: 0.1 },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "Invalid recipient address", json["error"]
  end

  test "POST /transfers rejects sending to self" do
    post "/transfers",
      params: { recipient: @wallet_address, amount_sol: 0.1 },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "Cannot send to yourself", json["error"]
  end

  test "POST /transfers rejects zero amount" do
    post "/transfers",
      params: { recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM", amount_sol: 0 },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "Amount must be greater than 0", json["error"]
  end

  test "PATCH /transfers/:id updates transfer with signature" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 200_000_000,
      amount_sol: 0.2,
      network: "devnet"
    )

    valid_sig = "523W4PuV9mThYRUX58vPV5KYs9Z6WkHsE4aLx94LxB1H8TigaRs8Lt2sii2hj56jpmX6UkkSxtfns3QfSvZdtS8g"

    patch "/transfers/#{transfer.id}",
      params: { signature: valid_sig, status: "submitted" },
      headers: { "Accept" => "application/json" },
      as: :json

    assert_response :success
    transfer.reload
    assert_equal valid_sig, transfer.signature
    assert_equal "submitted", transfer.status
  end

  test "GET /transfers/:id/status returns transfer status" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 200_000_000,
      amount_sol: 0.2,
      network: "devnet",
      status: "confirmed",
      signature: "4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi6bMEphXnYBGqL3oAjMFEKjMGkmYRiC4sP3mRs6EBvEwUJ"
    )

    get "/transfers/#{transfer.id}/status"
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "confirmed", json["status"]
    assert_equal "4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi6bMEphXnYBGqL3oAjMFEKjMGkmYRiC4sP3mRs6EBvEwUJ", json["signature"]
  end
end

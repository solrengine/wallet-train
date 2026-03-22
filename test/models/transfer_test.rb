require "test_helper"

class TransferTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
  end

  test "valid transfer" do
    transfer = @user.transfers.new(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 200_000_000,
      amount_sol: 0.2,
      network: "devnet"
    )
    assert transfer.valid?
  end

  test "requires recipient" do
    transfer = @user.transfers.new(recipient: nil, amount_lamports: 100, amount_sol: 0.1, network: "devnet")
    assert_not transfer.valid?
  end

  test "rejects invalid recipient address" do
    transfer = @user.transfers.new(recipient: "invalid!", amount_lamports: 100, amount_sol: 0.1, network: "devnet")
    assert_not transfer.valid?
    assert_includes transfer.errors[:recipient], "is not a valid Solana address"
  end

  test "requires positive amount" do
    transfer = @user.transfers.new(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 0,
      amount_sol: 0,
      network: "devnet"
    )
    assert_not transfer.valid?
  end

  test "defaults to pending status" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 200_000_000,
      amount_sol: 0.2,
      network: "devnet"
    )
    assert_equal "pending", transfer.status
  end

  test "confirmed? returns true for confirmed and finalized" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 100, amount_sol: 0.1, network: "devnet", status: "confirmed"
    )
    assert transfer.confirmed?

    transfer.update!(status: "finalized")
    assert transfer.confirmed?
  end

  test "failed? returns true for failed status" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 100, amount_sol: 0.1, network: "devnet", status: "failed"
    )
    assert transfer.failed?
  end

  test "pending? returns true for pending and submitted" do
    transfer = @user.transfers.create!(
      recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM",
      amount_lamports: 100, amount_sol: 0.1, network: "devnet"
    )
    assert transfer.pending?

    transfer.update!(status: "submitted")
    assert transfer.pending?
  end

  test "short_signature truncates signature" do
    transfer = Transfer.new(signature: "3MbmivZmHtSJDAHk8dmLU8GUUbTnMfd7PwVepQF6VTVmFD13fEiTqVLdKA57BDgDGa7Hx3vHoYKB2vopxFEVVfZp")
    assert_equal "3MbmivZm...VfZp", transfer.short_signature
  end

  test "short_recipient truncates recipient" do
    transfer = Transfer.new(recipient: "Hij97xr2CFGPphT8ebsDT1ASwvejqvLchKDZEvqo6cXM")
    assert_equal "Hij9...6cXM", transfer.short_recipient
  end
end

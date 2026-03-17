require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid user with wallet address" do
    user = User.new(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    assert user.valid?
  end

  test "requires wallet address" do
    user = User.new(wallet_address: nil)
    assert_not user.valid?
    assert_includes user.errors[:wallet_address], "can't be blank"
  end

  test "rejects invalid wallet address" do
    user = User.new(wallet_address: "not-a-valid-address!")
    assert_not user.valid?
    assert_includes user.errors[:wallet_address], "is not a valid Solana address"
  end

  test "rejects too short address" do
    user = User.new(wallet_address: "abc123")
    assert_not user.valid?
  end

  test "enforces unique wallet address" do
    User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    duplicate = User.new(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:wallet_address], "has already been taken"
  end

  test "generates nonce and expiration on create" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    assert_not_nil user.nonce
    assert_equal 32, user.nonce.length
    assert_not_nil user.nonce_expires_at
    assert user.nonce_expires_at > Time.current
  end

  test "generate_nonce! updates nonce and expiration" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    old_nonce = user.nonce
    user.generate_nonce!
    assert_not_equal old_nonce, user.nonce
    assert user.nonce_expires_at > Time.current
  end

  test "nonce_valid? returns true for fresh nonce" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    assert user.nonce_valid?
  end

  test "nonce_valid? returns false for expired nonce" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    user.update!(nonce_expires_at: 1.minute.ago)
    assert_not user.nonce_valid?
  end

  test "nonce_valid? returns false when nonce is nil" do
    user = User.create!(wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg")
    user.update!(nonce: nil)
    assert_not user.nonce_valid?
  end
end

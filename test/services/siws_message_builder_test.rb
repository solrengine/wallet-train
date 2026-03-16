require "test_helper"

class SiwsMessageBuilderTest < ActiveSupport::TestCase
  test "builds message with required fields" do
    message = SiwsMessageBuilder.new(
      domain: "localhost",
      wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg",
      nonce: "abc123def456",
      uri: "http://localhost:3000"
    ).build

    assert_includes message, "localhost wants you to sign in with your Solana account:"
    assert_includes message, "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg"
    assert_includes message, "Nonce: abc123def456"
    assert_includes message, "URI: http://localhost:3000"
    assert_includes message, "Version: 1"
    assert_includes message, "Chain ID: mainnet"
    assert_includes message, "Issued At:"
  end

  test "includes custom statement" do
    message = SiwsMessageBuilder.new(
      domain: "example.com",
      wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg",
      nonce: "abc123",
      statement: "Please sign to verify your identity"
    ).build

    assert_includes message, "Please sign to verify your identity"
  end

  test "uses default statement when none provided" do
    message = SiwsMessageBuilder.new(
      domain: "myapp.com",
      wallet_address: "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg",
      nonce: "abc123"
    ).build

    assert_includes message, "Sign in to myapp.com"
  end
end

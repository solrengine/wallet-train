require "test_helper"

class TokenTest < ActiveSupport::TestCase
  test "valid token with mint" do
    token = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    assert token.valid?
  end

  test "requires mint" do
    token = Token.new(mint: nil)
    assert_not token.valid?
  end

  test "enforces unique mint" do
    Token.create!(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    duplicate = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    assert_not duplicate.valid?
  end

  test "display_name returns name when present" do
    token = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", name: "USD Coin")
    assert_equal "USD Coin", token.display_name
  end

  test "display_name returns short address when name is blank" do
    token = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", name: nil)
    assert_equal "EPjF...Dt1v", token.display_name
  end

  test "display_symbol returns symbol when present" do
    token = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", symbol: "USDC")
    assert_equal "USDC", token.display_symbol
  end

  test "display_symbol returns ??? when symbol is blank" do
    token = Token.new(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", symbol: nil)
    assert_equal "???", token.display_symbol
  end

  test "find_or_fetch_many returns existing tokens from DB" do
    usdc = Token.create!(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", name: "USD Coin", symbol: "USDC")
    result = Token.find_or_fetch_many([ "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" ])
    assert_equal usdc, result["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]
  end
end

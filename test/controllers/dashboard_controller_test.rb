require "test_helper"
require "ed25519"
require "base58"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  # Stand-in for Solrengine::Tokens::Portfolio — the dashboard hits RPC through
  # it four times; tests must never touch the network.
  class FakePortfolio
    def initialize(nfts: [], nfts_error: nil)
      @nfts = nfts
      @nfts_error = nfts_error
    end

    def tokens = []
    def total_usd_value = 0
    def recent_transactions = []

    def nfts
      raise @nfts_error if @nfts_error
      @nfts
    end
  end

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

  SAMPLE_NFT = { id: "asset1", name: "SuperteamTH Genesis", image: "https://cdn.example/nft.png",
                 collection: "Workshop Mints", compressed: false }.freeze

  test "dashboard renders NFTs with name and image" do
    with_portfolio(FakePortfolio.new(nfts: [ SAMPLE_NFT ])) do
      get "/dashboard"
    end

    assert_response :success
    assert_includes response.body, "SuperteamTH Genesis"
    assert_includes response.body, "https://cdn.example/nft.png"
  end

  test "dashboard shows empty state when wallet has no NFTs" do
    with_portfolio(FakePortfolio.new(nfts: [])) do
      get "/dashboard"
    end

    assert_response :success
    assert_includes response.body, "No NFTs found"
  end

  test "dashboard still renders when the NFT fetch raises" do
    with_portfolio(FakePortfolio.new(nfts_error: RuntimeError.new("DAS down"))) do
      get "/dashboard"
    end

    assert_response :success
    assert_includes response.body, "No NFTs found"
  end

  test "NFT without image renders placeholder instead of broken img" do
    with_portfolio(FakePortfolio.new(nfts: [ SAMPLE_NFT.merge(image: nil, name: "No Image NFT") ])) do
      get "/dashboard"
    end

    assert_response :success
    assert_includes response.body, "No Image NFT"
    refute_includes response.body, "img src=\"\""
  end

  private

  # minitest 6 no longer ships minitest/mock, so swap Portfolio.new by hand
  # for the duration of the block.
  def with_portfolio(fake)
    klass = Solrengine::Tokens::Portfolio
    klass.singleton_class.alias_method(:__real_new, :new)
    klass.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    klass.singleton_class.alias_method(:new, :__real_new)
    klass.singleton_class.remove_method(:__real_new)
  end
end

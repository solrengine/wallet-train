import { Controller } from "@hotwired/stimulus"
import { createSolanaRpc, lamports, address } from "@solana/kit"

// Fetches and displays SOL balance for a wallet address.
// Uses @solana/kit RPC client directly from the browser.
export default class extends Controller {
  static targets = ["sol"]
  static values = {
    address: String,
    rpcUrl: { type: String, default: "https://api.mainnet-beta.solana.com" }
  }

  connect() {
    this.fetchBalance()
  }

  async fetchBalance() {
    try {
      const rpc = createSolanaRpc(this.rpcUrlValue)
      const walletAddress = address(this.addressValue)

      const { value: balanceLamports } = await rpc.getBalance(walletAddress).send()

      const balanceSol = Number(balanceLamports) / 1_000_000_000
      this.solTarget.textContent = `${balanceSol.toFixed(4)} SOL`
    } catch (error) {
      console.error("Failed to fetch balance:", error)
      this.solTarget.textContent = "Error"
    }
  }
}

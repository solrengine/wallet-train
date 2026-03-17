import { Controller } from "@hotwired/stimulus"
import { getWallets } from "@wallet-standard/app"
import { SolanaSignAndSendTransaction } from "@solana/wallet-standard-features"
import {
  pipe,
  createTransactionMessage,
  setTransactionMessageLifetimeUsingBlockhash,
  setTransactionMessageFeePayer,
  appendTransactionMessageInstruction,
  compileTransaction,
  getBase64EncodedWireTransaction,
  createSolanaRpc,
  address,
  getBase58Decoder,
} from "@solana/kit"

// Handles one-click SOL donations from the landing page.
// No login required — connects wallet, builds tx, signs, sends.
export default class extends Controller {
  static targets = ["status"]
  static values = {
    recipient: String,
    rpcUrl: String
  }

  async donate(event) {
    const amount = parseFloat(event.currentTarget.dataset.amount)
    if (!amount || amount <= 0) return

    const button = event.currentTarget
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Connecting..."

    try {
      // Find a wallet with signAndSendTransaction
      const { wallet, account } = await this.connectWallet()

      // Build the transaction
      button.textContent = "Sign in wallet..."
      const txBytes = await this.buildTransaction(account.address, amount)

      // Sign and send
      const chain = this.rpcUrlValue.includes("devnet") ? "solana:devnet"
        : this.rpcUrlValue.includes("testnet") ? "solana:testnet"
        : "solana:mainnet"

      const feature = wallet.features[SolanaSignAndSendTransaction]
      const [{ signature: sigBytes }] = await feature.signAndSendTransaction({
        account,
        transaction: txBytes,
        chain
      })

      const decoder = getBase58Decoder()
      const signature = decoder.decode(sigBytes)

      // Show success
      this.showStatus(`Sent ${amount} SOL! ${signature.slice(0, 8)}...`, "success")
      button.textContent = "Sent!"
      setTimeout(() => {
        button.textContent = originalText
        button.disabled = false
      }, 3000)

    } catch (error) {
      console.error("Donate error:", error)
      if (error.message?.includes("User rejected") || error.message?.includes("cancelled")) {
        this.showStatus("Cancelled", "warning")
      } else {
        this.showStatus(error.message || "Failed", "error")
      }
      button.textContent = originalText
      button.disabled = false
    }
  }

  async connectWallet() {
    const { get } = getWallets()
    const wallets = get().filter(w => w.features[SolanaSignAndSendTransaction])

    if (wallets.length === 0) {
      throw new Error("No Solana wallet found. Please install one.")
    }

    // Try to connect the first available wallet
    for (const wallet of wallets) {
      const connectFeature = wallet.features["standard:connect"]
      if (!connectFeature) continue

      try {
        const { accounts } = await connectFeature.connect()
        if (accounts?.length > 0) {
          return { wallet, account: accounts[0] }
        }
      } catch { /* try next */ }
    }

    throw new Error("Could not connect wallet. Please try again.")
  }

  async buildTransaction(senderAddress, amountSol) {
    const rpc = createSolanaRpc(this.rpcUrlValue)
    const { value: { blockhash, lastValidBlockHeight } } = await rpc
      .getLatestBlockhash({ commitment: "finalized" }).send()

    const lamports = BigInt(Math.round(amountSol * 1_000_000_000))
    const data = new Uint8Array(12)
    const dv = new DataView(data.buffer)
    dv.setUint32(0, 2, true)
    dv.setUint32(4, Number(lamports & 0xFFFFFFFFn), true)
    dv.setUint32(8, Number(lamports >> 32n), true)

    const instruction = {
      programAddress: address("11111111111111111111111111111111"),
      accounts: [
        { address: address(senderAddress), role: 3 },
        { address: address(this.recipientValue), role: 1 },
      ],
      data
    }

    const txMessage = pipe(
      createTransactionMessage({ version: 0 }),
      tx => setTransactionMessageFeePayer(address(senderAddress), tx),
      tx => setTransactionMessageLifetimeUsingBlockhash(
        { blockhash, lastValidBlockHeight: BigInt(lastValidBlockHeight) },
        tx
      ),
      tx => appendTransactionMessageInstruction(instruction, tx),
    )

    const compiled = compileTransaction(txMessage)
    const base64 = getBase64EncodedWireTransaction(compiled)
    return Uint8Array.from(atob(base64), c => c.charCodeAt(0))
  }

  showStatus(message, type) {
    const el = this.statusTarget
    el.textContent = message
    el.classList.remove("hidden", "text-green-400", "text-yellow-400", "text-red-400")
    switch (type) {
      case "success": el.classList.add("text-green-400"); break
      case "warning": el.classList.add("text-yellow-400"); break
      case "error": el.classList.add("text-red-400"); break
    }
    el.classList.remove("hidden")
    setTimeout(() => el.classList.add("hidden"), 5000)
  }
}

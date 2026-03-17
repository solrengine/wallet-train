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
// Shows a wallet picker if multiple wallets are available.
export default class extends Controller {
  static targets = ["status", "walletPicker", "walletList", "amounts"]
  static values = {
    recipient: String,
    rpcUrl: String
  }

  connect() {
    this.selectedWallet = null
    this.pendingAmount = null
    this.discoverWallets()
  }

  discoverWallets() {
    const { get, on } = getWallets()
    this.availableWallets = get().filter(w => w.features[SolanaSignAndSendTransaction])
    on("register", () => {
      this.availableWallets = get().filter(w => w.features[SolanaSignAndSendTransaction])
    })
  }

  async donate(event) {
    const amount = parseFloat(event.currentTarget.dataset.amount)
    if (!amount || amount <= 0) return

    if (this.availableWallets.length === 0) {
      return this.showStatus("No Solana wallet found. Please install one.", "error")
    }

    // If only one wallet, use it directly
    if (this.availableWallets.length === 1) {
      this.selectedWallet = this.availableWallets[0]
      return this.executeDonation(amount, event.currentTarget)
    }

    // Multiple wallets — show picker
    this.pendingAmount = amount
    this.pendingButton = event.currentTarget
    this.showWalletPicker()
  }

  showWalletPicker() {
    const html = this.availableWallets.map((wallet, index) => `
      <button data-action="click->donate#pickWallet"
              data-wallet-index="${index}"
              class="flex items-center gap-3 w-full p-3 rounded-xl border border-gray-700 hover:border-purple-500 bg-gray-800/50 hover:bg-purple-900/20 cursor-pointer transition-all duration-200">
        ${wallet.icon ? `<img src="${wallet.icon}" alt="${wallet.name}" class="w-7 h-7 rounded-lg" />` : ''}
        <span class="text-white text-sm font-medium">${wallet.name}</span>
      </button>
    `).join("")

    this.walletListTarget.innerHTML = html
    this.walletPickerTarget.classList.remove("hidden")
    this.amountsTarget.classList.add("hidden")
  }

  pickWallet(event) {
    const index = parseInt(event.currentTarget.dataset.walletIndex)
    this.selectedWallet = this.availableWallets[index]
    this.walletPickerTarget.classList.add("hidden")
    this.amountsTarget.classList.remove("hidden")
    this.executeDonation(this.pendingAmount, this.pendingButton)
  }

  cancelPicker() {
    this.walletPickerTarget.classList.add("hidden")
    this.amountsTarget.classList.remove("hidden")
  }

  async executeDonation(amount, button) {
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Connecting..."

    try {
      const { wallet, account } = await this.connectWallet(this.selectedWallet)

      button.textContent = "Sign in wallet..."
      const txBytes = await this.buildTransaction(account.address, amount)

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

  async connectWallet(wallet) {
    const connectFeature = wallet.features["standard:connect"]
    if (!connectFeature) throw new Error("Wallet does not support connect")

    const { accounts } = await connectFeature.connect()
    if (!accounts?.length) throw new Error("No accounts found")

    return { wallet, account: accounts[0] }
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

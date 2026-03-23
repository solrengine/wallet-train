import { Controller } from "@hotwired/stimulus"
import {
  discoverWallets,
  connectWallet,
  buildTransferTransaction,
  signAndSend,
  detectChain,
} from "@solrengine/wallet-utils"
import { SolanaSignAndSendTransaction } from "@solana/wallet-standard-features"
import { createSolanaRpc } from "@solana/kit"

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
    this.availableWallets = discoverWallets(SolanaSignAndSendTransaction, (newWallets) => {
      this.availableWallets = [...this.availableWallets, ...newWallets]
    })
  }

  async donate(event) {
    const amount = parseFloat(event.currentTarget.dataset.amount)
    if (!amount || amount <= 0) return

    if (this.availableWallets.length === 0) {
      return this.showStatus("No Solana wallet found. Please install one.", "error")
    }

    if (this.availableWallets.length === 1) {
      this.selectedWallet = this.availableWallets[0]
      return this.executeDonation(amount, event.currentTarget)
    }

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
    const originalHTML = button.innerHTML
    button.disabled = true
    button.classList.add("opacity-70")
    this.setButtonSpinner(button, "Connecting...")

    try {
      const { wallet, account } = await connectWallet(this.selectedWallet)

      this.setButtonSpinner(button, "Sign in wallet...")

      // Get blockhash from RPC
      const rpc = createSolanaRpc(this.rpcUrlValue)
      const { value: { blockhash, lastValidBlockHeight } } = await rpc
        .getLatestBlockhash({ commitment: "finalized" }).send()

      const txBytes = buildTransferTransaction({
        sender: account.address,
        recipient: this.recipientValue,
        amountSol: amount,
        blockhash,
        lastValidBlockHeight
      })

      const chain = detectChain(this.rpcUrlValue)
      const signature = await signAndSend({ wallet, account, transaction: txBytes, chain })

      // Success state
      button.classList.remove("opacity-70")
      button.classList.add("border-green-500/50")
      button.innerHTML = `
        <div class="w-10 h-10 rounded-xl bg-green-900/30 flex items-center justify-center mx-auto mb-3">
          <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <p class="text-green-400 font-semibold text-sm">Sent!</p>
        <p class="text-gray-500 text-xs">${amount} SOL</p>
      `
      this.showStatus(`${signature.slice(0, 12)}...`, "success")

      setTimeout(() => {
        button.innerHTML = originalHTML
        button.disabled = false
        button.classList.remove("border-green-500/50")
      }, 4000)

    } catch (error) {
      console.error("Donate error:", error)
      if (error.message?.includes("User rejected") || error.message?.includes("cancelled")) {
        this.showStatus("Cancelled", "warning")
      } else {
        this.showStatus(error.message || "Failed", "error")
      }
      button.innerHTML = originalHTML
      button.disabled = false
      button.classList.remove("opacity-70")
    }
  }

  setButtonSpinner(button, text) {
    button.innerHTML = `
      <div class="flex flex-col items-center gap-2 py-1">
        <div class="w-6 h-6 border-2 border-purple-500 border-t-transparent rounded-full animate-spin"></div>
        <p class="text-gray-400 text-xs">${text}</p>
      </div>
    `
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

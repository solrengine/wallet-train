import { Controller } from "@hotwired/stimulus"
import {
  findWalletByAddress,
  buildTransferTransaction,
  signAndSend,
  detectChain,
  explorerUrl,
  getCsrfToken,
} from "@solrengine/wallet-utils"

// Handles the Send SOL flow using @solrengine/wallet-utils
// for wallet discovery, transaction building, and signing.
export default class extends Controller {
  static targets = ["recipient", "amount", "sendBtn", "status", "confirming", "confirmingText", "success", "solscanLink", "confirmationBadge"]
  static values = {
    createUrl: String,
    dashboardUrl: String,
    wallet: String,
    balance: Number,
    rpcUrl: String
  }

  setMax() {
    const max = Math.max(0, this.balanceValue - 0.005)
    this.amountTarget.value = max.toFixed(6)
  }

  async send() {
    const recipient = this.recipientTarget.value.trim()
    const amountSol = parseFloat(this.amountTarget.value)

    if (!recipient.match(/^[1-9A-HJ-NP-Za-km-z]{32,44}$/)) {
      return this.showStatus("Invalid recipient address", "error")
    }
    if (isNaN(amountSol) || amountSol <= 0) {
      return this.showStatus("Enter a valid amount", "error")
    }
    if (amountSol > this.balanceValue - 0.005) {
      return this.showStatus("Insufficient balance (need ~0.005 SOL for fees)", "error")
    }

    try {
      this.sendBtnTarget.disabled = true
      this.sendBtnTarget.textContent = "Preparing..."

      // Step 1: Find wallet by address
      const { wallet, account } = await findWalletByAddress(this.walletValue)

      // Step 2: Get transaction params from Rails
      const csrfToken = getCsrfToken()
      const createResponse = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ recipient, amount_sol: amountSol })
      })

      if (!createResponse.ok) {
        const error = await createResponse.json()
        throw new Error(error.error || "Failed to prepare transaction")
      }

      const txParams = await createResponse.json()

      // Step 3: Build and sign transaction
      this.showConfirming("Sign the transaction in your wallet...")

      const txBytes = buildTransferTransaction({
        sender: txParams.sender,
        recipient: txParams.recipient,
        amountSol,
        blockhash: txParams.blockhash,
        lastValidBlockHeight: txParams.last_valid_block_height
      })

      const chain = detectChain(this.rpcUrlValue)
      const signature = await signAndSend({ wallet, account, transaction: txBytes, chain })

      // Step 4: Report signature to Rails
      this.updateConfirmingText("Confirming transaction...")
      await fetch(`/transfers/${txParams.transfer_id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body: JSON.stringify({ signature, status: "submitted" })
      })

      // Step 5: Show success
      this.showSuccess(signature, txParams.transfer_id)

    } catch (error) {
      console.error("Transfer error:", error)
      if (error.message?.includes("User rejected") || error.message?.includes("cancelled")) {
        this.showStatus("Transaction cancelled", "warning")
      } else {
        this.showStatus(error.message || "Transaction failed", "error")
      }
      this.resetSendBtn()
    }
  }

  showConfirming(text) {
    this.sendBtnTarget.classList.add("hidden")
    this.confirmingTarget.classList.remove("hidden")
    this.confirmingTextTarget.textContent = text
  }

  updateConfirmingText(text) {
    this.confirmingTextTarget.textContent = text
  }

  showSuccess(signature, transferId) {
    this.confirmingTarget.classList.add("hidden")
    this.successTarget.classList.remove("hidden")

    const chain = detectChain(this.rpcUrlValue)
    this.solscanLinkTarget.href = explorerUrl(signature, chain)
    this.solscanLinkTarget.textContent = signature.slice(0, 8) + "..." + signature.slice(-4)

    this.confirmationBadgeTarget.textContent = "Submitted"
    this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-yellow-900/30 text-yellow-400"

    this.pollStatus(transferId)
  }

  async pollStatus(transferId) {
    for (let i = 0; i < 30; i++) {
      await new Promise(r => setTimeout(r, 2000))
      try {
        const res = await fetch(`/transfers/${transferId}/status`)
        const data = await res.json()
        if (data.status === "finalized" || data.status === "confirmed") {
          this.confirmationBadgeTarget.textContent = data.status.charAt(0).toUpperCase() + data.status.slice(1)
          this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-green-900/30 text-green-400"
          setTimeout(() => { window.location.href = this.dashboardUrlValue }, 1500)
          return
        }
        if (data.status === "failed") {
          this.confirmationBadgeTarget.textContent = "Failed"
          this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-red-900/30 text-red-400"
          return
        }
      } catch { /* continue */ }
    }
  }

  showStatus(message, type = "info") {
    const el = this.statusTarget
    el.textContent = message
    el.classList.remove("hidden", "bg-red-900/50", "text-red-300", "bg-yellow-900/50", "text-yellow-300", "bg-green-900/50", "text-green-300")
    switch (type) {
      case "error": el.classList.add("bg-red-900/50", "text-red-300"); break
      case "warning": el.classList.add("bg-yellow-900/50", "text-yellow-300"); break
      default: el.classList.add("bg-green-900/50", "text-green-300")
    }
    el.classList.remove("hidden")
  }

  resetSendBtn() {
    this.sendBtnTarget.classList.remove("hidden")
    this.sendBtnTarget.disabled = false
    this.sendBtnTarget.textContent = "Send SOL"
    this.confirmingTarget.classList.add("hidden")
  }
}

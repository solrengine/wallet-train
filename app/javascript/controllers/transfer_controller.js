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
  address,
  getBase58Decoder,
} from "@solana/kit"

// Handles the Send SOL flow using wallet-standard for signing/sending
// and @solana/kit for transaction construction.
export default class extends Controller {
  static targets = ["recipient", "amount", "sendBtn", "status", "confirming", "confirmingText", "success", "solscanLink", "confirmationBadge"]
  static values = {
    createUrl: String,
    dashboardUrl: String,
    wallet: String,
    balance: Number,
    rpcUrl: String
  }

  connect() {
    this.walletStandard = null
    this.walletAccount = null
    this.discoverWallet()
  }

  // Find the wallet-standard wallet that matches our connected address
  discoverWallet() {
    const { get } = getWallets()
    const wallets = get()

    for (const wallet of wallets) {
      if (!wallet.features[SolanaSignAndSendTransaction]) continue

      // Check if any account matches our connected wallet
      for (const account of wallet.accounts) {
        if (account.address === this.walletValue) {
          this.walletStandard = wallet
          this.walletAccount = account
          return
        }
      }
    }

    // Wallet might not have accounts exposed yet — try connecting
    for (const wallet of wallets) {
      if (wallet.features[SolanaSignAndSendTransaction]) {
        this.walletStandard = wallet
        return
      }
    }
  }

  async ensureConnected() {
    if (this.walletAccount?.address === this.walletValue) return

    // Try all wallet-standard wallets to find the right account
    const { get } = getWallets()
    for (const wallet of get()) {
      if (!wallet.features[SolanaSignAndSendTransaction]) continue

      // Check existing accounts first
      const match = wallet.accounts.find(a => a.address === this.walletValue)
      if (match) {
        this.walletStandard = wallet
        this.walletAccount = match
        return
      }

      // Try connecting to expose accounts
      const connectFeature = wallet.features["standard:connect"]
      if (connectFeature) {
        try {
          const { accounts } = await connectFeature.connect()
          const found = accounts?.find(a => a.address === this.walletValue)
          if (found) {
            this.walletStandard = wallet
            this.walletAccount = found
            return
          }
        } catch { /* try next wallet */ }
      }
    }

    throw new Error(
      `Active wallet account doesn't match your login address (${this.walletValue.slice(0, 4)}...${this.walletValue.slice(-4)}). ` +
      `Please switch to the correct account in your wallet and try again.`
    )
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

      // Ensure wallet-standard account is available
      await this.ensureConnected()

      // Step 1: Get transaction params from Rails
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
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

      // Step 2: Build the transaction
      this.showConfirming("Sign the transaction in your wallet...")
      const txBytes = this.buildTransaction(txParams)

      // Step 3: Sign and send via wallet-standard
      const feature = this.walletStandard.features[SolanaSignAndSendTransaction]
      const chain = this.rpcUrlValue.includes("devnet") ? "solana:devnet"
        : this.rpcUrlValue.includes("testnet") ? "solana:testnet"
        : "solana:mainnet"

      const [{ signature: sigBytes }] = await feature.signAndSendTransaction({
        account: this.walletAccount,
        transaction: txBytes,
        chain: chain,
        options: { skipPreflight: false }
      })

      // Convert signature bytes to base58 string
      const decoder = getBase58Decoder()
      const signature = decoder.decode(sigBytes)

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

  buildTransaction(txParams) {
    // Build SystemProgram.transfer instruction
    const lamportsBI = BigInt(txParams.amount_lamports)
    const data = new Uint8Array(12)
    const dv = new DataView(data.buffer)
    dv.setUint32(0, 2, true) // SystemProgram.transfer = index 2
    dv.setUint32(4, Number(lamportsBI & 0xFFFFFFFFn), true)
    dv.setUint32(8, Number(lamportsBI >> 32n), true)

    const instruction = {
      programAddress: address("11111111111111111111111111111111"),
      accounts: [
        { address: address(txParams.sender), role: 3 },    // writable signer
        { address: address(txParams.recipient), role: 1 },  // writable
      ],
      data: data
    }

    // Build v0 transaction message
    const txMessage = pipe(
      createTransactionMessage({ version: 0 }),
      tx => setTransactionMessageFeePayer(address(txParams.sender), tx),
      tx => setTransactionMessageLifetimeUsingBlockhash(
        { blockhash: txParams.blockhash, lastValidBlockHeight: 2n ** 64n - 1n },
        tx
      ),
      tx => appendTransactionMessageInstruction(instruction, tx),
    )

    // Compile and serialize to wire format bytes
    const compiled = compileTransaction(txMessage)
    const base64 = getBase64EncodedWireTransaction(compiled)
    return Uint8Array.from(atob(base64), c => c.charCodeAt(0))
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

    const isDevnet = this.rpcUrlValue.includes("devnet")
    const isTestnet = this.rpcUrlValue.includes("testnet")

    // Use Solana Explorer for devnet/testnet (more reliable), Solscan for mainnet
    const txUrl = (isDevnet || isTestnet)
      ? `https://explorer.solana.com/tx/${signature}?cluster=${isDevnet ? "devnet" : "testnet"}`
      : `https://solscan.io/tx/${signature}`

    this.solscanLinkTarget.href = txUrl
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

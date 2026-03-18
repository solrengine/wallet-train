# WalletTrain

A full-featured Solana wallet dapp built with Ruby on Rails 8. Wallet-based authentication, token portfolio, real-time updates, and SOL transfers — all using the Rails default stack.

Part of the [SolRengine](https://github.com/solrengine) project.

## Stack

- Ruby on Rails 8 (Hotwire, Turbo, Stimulus, Solid Queue/Cache/Cable)
- SQLite
- Tailwind CSS 4 + esbuild
- [@solana/kit](https://github.com/anza-xyz/kit) for client-side transaction building
- [Wallet Standard](https://github.com/anza-xyz/wallet-standard) for wallet discovery
- Ed25519 signature verification in Ruby
- Jupiter API for token metadata and prices

## Features

- **Wallet Authentication** — Sign in with Phantom, Solflare, or Backpack via SIWS (Sign In With Solana)
- **Token Portfolio** — SPL token balances with icons, names, and USD values from Jupiter
- **Real-time Updates** — Turbo Streams + Idiomorph morph for live dashboard updates
- **Send SOL** — Build transactions with @solana/kit, sign with wallet, track confirmation
- **Network Switching** — Mainnet, Devnet, Testnet with per-network caching
- **Background Jobs** — Solid Queue for transaction confirmation and wallet monitoring
- **Token Metadata DB** — Persisted token metadata, only fetched once per mint

## Setup

```sh
bin/setup
bin/rails db:prepare
```

## Development

```sh
bin/dev
```

Starts 4 processes: web server, JS bundler, CSS compiler, and Solid Queue worker.

Open `http://localhost:3000` with a Solana wallet extension installed (Phantom, Solflare, or Backpack).

## Testing on Devnet

1. Switch to Devnet using the network dropdown
2. Create a test wallet: `solana-keygen new -o ~/.config/solana/devnet.json`
3. Airdrop SOL: `solana airdrop 2 -k ~/.config/solana/devnet.json --url devnet`
4. Use the Send feature to transfer SOL to the test wallet

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SOLANA_RPC_URL` | `https://api.mainnet-beta.solana.com` | Solana RPC endpoint |
| `APP_DOMAIN` | `localhost` | Domain for SIWS message (production) |

## Architecture

```
app/
├── controllers/
│   ├── sessions_controller.rb       # SIWS auth (nonce → sign → verify → session)
│   ├── dashboard_controller.rb      # Portfolio dashboard
│   ├── transfers_controller.rb      # Send SOL (validate → tx params → confirm)
│   └── networks_controller.rb       # Network switching
├── models/
│   ├── user.rb                      # wallet_address identity
│   ├── token.rb                     # Persisted token metadata from Jupiter
│   └── transfer.rb                  # Transaction tracking
├── services/
│   ├── siws_verifier.rb             # Ed25519 signature verification
│   ├── siws_message_builder.rb      # SIWS message construction
│   ├── solana_client.rb             # Solana JSON-RPC client
│   ├── jupiter_client.rb            # Jupiter API (metadata + prices)
│   ├── token_metadata_service.rb    # Assembles tokens with metadata + prices
│   └── wallet_portfolio_service.rb  # Cached portfolio aggregation
├── jobs/
│   ├── wallet_monitor_job.rb        # Polls for new transactions → Turbo Streams
│   └── transaction_confirmation_job.rb  # Tracks tx confirmation status
├── channels/
│   └── wallet_channel.rb            # ActionCable per-wallet streaming
└── javascript/controllers/
    ├── wallet_controller.js          # Wallet Standard discovery + SIWS sign-in
    ├── transfer_controller.js        # Build tx with @solana/kit + wallet-standard sign
    ├── auto_refresh_controller.js    # Idiomorph-based invisible page refresh
    ├── clipboard_controller.js       # Copy wallet address
    └── dropdown_controller.js        # Network selector
```

## How It Works

### Authentication
1. Stimulus discovers wallets via Wallet Standard
2. User clicks "Connect Wallet" → wallet popup opens
3. Rails generates a SIWS message with a nonce
4. Wallet signs the message (Ed25519)
5. Rails verifies the signature and creates a session

### Sending SOL
1. Rails validates inputs and fetches a recent blockhash
2. Stimulus builds a v0 transaction using @solana/kit
3. Wallet signs and sends via wallet-standard `signAndSendTransaction`
4. Rails tracks confirmation status via background job
5. Dashboard updates in real-time via Turbo Streams

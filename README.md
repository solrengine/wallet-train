# Solana on Rails

A Rails 8 application that integrates with the Solana blockchain. Replaces traditional email/password authentication with wallet-based sign-in using SIWS (Sign In With Solana).

## Stack

- Ruby on Rails 8 (default stack)
- SQLite + Solid Queue / Cache / Cable
- Hotwire (Turbo + Stimulus)
- Tailwind CSS 4
- esbuild
- [@solana/kit](https://github.com/anza-xyz/kit) for client-side Solana interaction
- [Wallet Standard](https://github.com/anza-xyz/wallet-standard) for wallet discovery
- Ed25519 signature verification in Ruby

## Features

- **Wallet Authentication** — Sign in with Phantom, Solflare, or Backpack via SIWS
- **Ed25519 Verification** — Server-side signature verification using the `ed25519` gem
- **SOL Balance** — Server-side RPC balance fetching
- **No passwords, no emails** — The wallet *is* the identity

## Setup

```sh
bin/setup
bin/rails db:migrate
```

## Development

```sh
bin/dev
```

Open `http://localhost:3000` with a Solana wallet extension installed.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SOLANA_RPC_URL` | `https://api.mainnet-beta.solana.com` | Solana RPC endpoint |
| `APP_DOMAIN` | `localhost` | Domain for SIWS message (production) |

## How It Works

1. Stimulus discovers installed wallets via Wallet Standard
2. User clicks "Connect Wallet" — extension popup opens
3. Rails generates a SIWS message with a nonce
4. Wallet signs the message (Ed25519)
5. Rails verifies the signature and creates a session
6. Dashboard shows wallet address and SOL balance (fetched server-side via RPC)

## Architecture

```
app/
├── controllers/
│   ├── application_controller.rb    # Auth helpers (current_user, authenticate!)
│   ├── sessions_controller.rb       # SIWS auth flow (nonce → sign → verify → session)
│   └── dashboard_controller.rb      # Authenticated dashboard
├── models/
│   └── user.rb                      # wallet_address + nonce validation
├── services/
│   ├── siws_verifier.rb             # Ed25519 signature verification
│   ├── siws_message_builder.rb      # SIWS-standard message construction
│   └── solana_client.rb             # Solana JSON-RPC client
├── views/
│   ├── sessions/new.html.erb        # Login page with wallet selector
│   └── dashboard/show.html.erb      # Authenticated dashboard
└── javascript/controllers/
    ├── wallet_controller.js          # Stimulus: wallet connect + SIWS sign-in
    └── balance_controller.js         # Stimulus: client-side balance (unused, kept for reference)
```

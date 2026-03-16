# CLAUDE.md

## Project Overview

Rails 8 app integrating with Solana blockchain. Wallet-based auth (SIWS) instead of email/password.

## Key Commands

- `bin/dev` — start dev server (Rails + esbuild + Tailwind)
- `yarn build` — bundle JS with esbuild
- `yarn build:css` — compile Tailwind CSS
- `bin/rails db:migrate` — run migrations

## Architecture Decisions

- **Legacy provider first for wallet connect** — Chrome only allows extension popups within direct user gesture context. Wallet-standard connect is tried as fallback only.
- **Server-side balance fetching** — Public Solana RPC blocks browser CORS requests. Balance is fetched in Ruby via `SolanaClient`.
- **SSL verify callback** — Ruby's OpenSSL rejects Solana RPC certs due to missing CRLs. `SolanaClient` uses a custom verify_callback to tolerate this.
- **Per-wallet signMessage API** — Phantom expects `signMessage(bytes, "utf8")`, others expect `signMessage(bytes)` only. Detected via `provider.isPhantom`.

## Wallet Compatibility

- **Phantom** — works via legacy provider (`window.phantom.solana`)
- **Solflare** — works; publicKey is on `provider.publicKey` not `response.publicKey`
- **Backpack** — works; `signMessage` returns `Uint8Array` directly (not `{ signature }`)

## Dependencies

- Ruby: `ed25519`, `base58`, `solana_rpc_ruby` (RPC gem configured but custom client used instead due to SSL issues)
- JS: `@solana/kit`, `@wallet-standard/app`, `@solana/wallet-standard-features`

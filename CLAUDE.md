# CLAUDE.md

## Project Overview

Rails 8 app integrating with Solana blockchain. Wallet-based auth (SIWS), token portfolio with Jupiter prices, real-time updates via Turbo Streams, and SOL transfers.

## Key Commands

- `bin/dev` — start all processes (web, js, css, jobs)
- `yarn build` — bundle JS with esbuild
- `yarn build:css` — compile Tailwind CSS
- `bin/rails db:prepare` — set up all databases (primary + cache + queue + cable)

## Architecture Decisions

- **Legacy provider first for wallet connect** — Chrome only allows extension popups within direct user gesture context. Wallet-standard features used for signing/sending transactions.
- **Server-side RPC calls** — Public Solana RPC blocks browser CORS requests. All balance/token/transaction fetching done in Ruby via `SolanaClient`.
- **SSL verify callback** — Ruby's OpenSSL rejects Solana/Jupiter certs due to missing CRLs. `SslHttpClient` concern provides shared fix.
- **Per-wallet signMessage API** — Phantom expects `signMessage(bytes, "utf8")`, others expect `signMessage(bytes)` only. Detected via `provider.isPhantom`.
- **Token metadata in DB, prices in cache** — Token name/symbol/icon persisted in `tokens` table (fetched once from Jupiter). USD prices cached in Solid Cache (1 min TTL).
- **Wallet-standard for transactions** — `signAndSendTransaction` feature used for Send SOL. Legacy provider used only for connect + signMessage (auth).
- **Idiomorph auto-refresh** — Dashboard fetches HTML via plain `fetch()` and morphs with `morphChildren` from Turbo. No loading bar, no scroll reset.
- **Network-scoped caching** — Cache keys include network name so switching networks gets fresh data.

## Wallet Compatibility

- **Phantom** — works via legacy provider for auth (`window.phantom.solana`)
- **Solflare** — works; publicKey is on `provider.publicKey` not `response.publicKey`
- **Backpack** — works; `signMessage` returns `Uint8Array` directly (not `{ signature }`)
- **All wallets** — wallet-standard `signAndSendTransaction` for Send SOL

## Multi-database Setup (development)

- `storage/development.sqlite3` — primary (users, tokens, transfers)
- `storage/development_cache.sqlite3` — Solid Cache
- `storage/development_queue.sqlite3` — Solid Queue
- `storage/development_cable.sqlite3` — Solid Cable

## Dependencies

- Ruby: `ed25519`, `base58`, `solana_rpc_ruby` (configured but custom `SolanaClient` used instead)
- JS: `@solana/kit`, `@wallet-standard/app`, `@solana/wallet-standard-features`, `@rails/actioncable`

# CLAUDE.md

## Project Overview

Rails 8 app integrating with Solana blockchain. Wallet-based auth (SIWS), token portfolio with Jupiter prices, real-time WebSocket updates via Turbo Streams, and SOL transfers.

## Key Commands

- `bin/dev` — start all 5 processes (web, js, css, jobs, ws)
- `yarn build` — bundle JS with esbuild
- `yarn build:css` — compile Tailwind CSS
- `bin/rails db:prepare` — set up all databases (primary + cache + queue + cable)
- `bin/rails test` — run Minitest suite (54 tests)

## Environment Variables

- `SOLANA_NETWORK` — network to run on (mainnet/devnet/testnet, default: mainnet)
- `SOLANA_RPC_URL` — mainnet HTTP RPC (Helius)
- `SOLANA_WS_URL` — mainnet WebSocket RPC (Helius)
- `SOLANA_RPC_DEVNET_URL` — devnet HTTP RPC
- `SOLANA_WS_DEVNET_URL` — devnet WebSocket RPC
- `APP_DOMAIN` — domain for SIWS message (production)

All config flows through `config/solana.yml` → `SolanaConfig` model.

## Architecture Decisions

- **Single network at boot** — `SOLANA_NETWORK` env var sets the network. No runtime switching. Simplifies caching, WebSocket, and RPC management.
- **Legacy provider first for wallet connect** — Chrome only allows extension popups within direct user gesture context. Wallet-standard used for `signAndSendTransaction`.
- **Server-side RPC calls** — All balance/token/transaction fetching done in Ruby via `SolanaClient`. Uses `confirmed` commitment to match WebSocket notifications.
- **SSL verify callback** — Ruby's OpenSSL rejects Solana/Jupiter certs due to missing CRLs. `SslHttpClient` concern provides shared fix.
- **Token metadata in DB, prices in cache** — Token name/symbol/icon persisted in `tokens` table (fetched once from Jupiter). USD prices cached in Solid Cache (1 min TTL).
- **Idiomorph auto-refresh** — Dashboard fetches HTML via `fetch()` and morphs with `morphChildren`. No loading bar, no scroll reset. 60s interval.
- **WebSocket monitor as separate process** — `bin/solana_monitor` runs independently from the web server. Subscribes to Solana `accountChanges` via WebSocket, sets a flag on the main thread, broadcasts via Turbo Streams + Solid Cable.
- **Solid Cable for cross-process broadcasts** — The `async` ActionCable adapter only works within one process. Solid Cable uses the database as message bus so `bin/solana_monitor` can broadcast to the web process.
- **3s delay before broadcast** — The `accountNotification` arrives before the RPC node updates the balance. A 3s delay ensures the broadcast fetches the new state.
- **Dashboard cache cleared after recent transfer** — If user made a transfer in last 2 minutes, skip cache on dashboard load for fresh RPC data.
- **Turbo cache disabled on dashboard** — `turbo-cache-control: no-cache` prevents stale snapshots when navigating back from Send page.

## Wallet Compatibility

- **Phantom** — works via legacy provider for auth (`window.phantom.solana`)
- **Solflare** — works; publicKey is on `provider.publicKey` not `response.publicKey`
- **Backpack** — works; `signMessage` returns `Uint8Array` directly (not `{ signature }`)
- **All wallets** — wallet-standard `signAndSendTransaction` for Send SOL

## Processes (bin/dev)

- `web` — Rails server (Puma)
- `js` — esbuild watch
- `css` — Tailwind watch
- `jobs` — Solid Queue worker (transaction confirmation)
- `ws` — Solana WebSocket monitor (real-time account changes)

## Multi-database Setup

- `storage/development.sqlite3` — primary (users, tokens, transfers)
- `storage/development_cache.sqlite3` — Solid Cache (RPC responses, prices)
- `storage/development_queue.sqlite3` — Solid Queue (background jobs)
- `storage/development_cable.sqlite3` — Solid Cable (ActionCable messages)

## Dependencies

- Ruby: `ed25519`, `base58`, `websocket-client-simple`, `dotenv-rails`
- JS: `@solana/kit`, `@wallet-standard/app`, `@solana/wallet-standard-features`, `@rails/actioncable`

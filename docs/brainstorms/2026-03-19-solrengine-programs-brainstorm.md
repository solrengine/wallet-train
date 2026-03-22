# Brainstorm: solrengine-programs

**Date:** 2026-03-19
**Status:** Final

## What We're Building

A new gem (`solrengine-programs`) that adds Solana program interaction to the SolRengine framework. Currently the stack handles wallet auth, RPC queries, token metadata, SOL transfers, and real-time monitoring — but has no way to interact with custom on-chain programs (Anchor or native).

This gem bridges that gap: parse an Anchor IDL, scaffold Ruby account models and instruction builders, and ship Stimulus controllers for client-side transaction submission.

**Reference implementation:** The piggy_bank Anchor dapp (Next.js + Anchor) demonstrates the pattern — a time-locked savings program with `lock` and `unlock` instructions, `Lock` account struct, and a React frontend that builds transactions from the IDL.

## Why This Approach

### Generator-first with IDL parsing

- **IDL is the standard.** Every Anchor program ships a JSON IDL describing instructions, accounts, and types. Parsing it eliminates manual duplication and drift.
- **Code generation is the Rails way.** `rails generate model`, `rails generate scaffold` — developers expect to scaffold then customize. A `rails generate solrengine:program` command fits naturally.
- **Visibility over magic.** Generated files live in `app/models/` and `app/services/`. Developers can read, debug, and extend them. No `method_missing` surprises.
- **Full-stack.** Ruby for server-side account querying and instruction building; Stimulus controllers for client-side wallet-signed transactions with Turbo integration.

### Why not runtime DSL or pure JS?

- Runtime DSL (parse IDL at boot, generate methods dynamically) is harder to debug and customize.
- Pure JS delegation would work for client-side but leaves the server unable to decode accounts or build transactions — losing half the value.

## Key Decisions

### 1. Single gem: `solrengine-programs`
One gem handles IDL parsing, Borsh serialization, account models, instruction builders, and Stimulus controllers. Split later if needed. Depends on `solrengine-rpc`.

### 2. IDL + DSL hybrid via generator
`rails generate solrengine:program PiggyBank path/to/idl.json` reads the Anchor IDL and scaffolds Ruby classes. Developers extend them with Rails patterns (validations, scopes, callbacks). Re-run generator on IDL changes.

### 3. ActiveModel-like account objects
Program accounts map to Ruby objects with ActiveModel APIs (attributes, validations, serialization) but are NOT database-backed. Data lives on-chain. The objects decode/encode Borsh binary data and support `memcmp`-based querying via RPC.

### 4. Ruby Borsh serialization via `borsh` gem
Depend on the [`borsh`](https://github.com/dryruby/borsh.rb) gem (0.2.0, dryruby) for Borsh encoding/decoding. It covers the full spec: `u8`–`u128`, `i8`–`i128`, `f32`/`f64`, `bool`, `string`, `vec`, `option`, `enum`, structs, maps, sets. Pure Ruby, zero dependencies, actively maintained (last release May 2025). Build a thin Solana-specific layer on top for PublicKey (32-byte fixed array) and Anchor discriminators (8-byte SHA256 prefix).

### 5. ENV-based server keypair
`SOLANA_KEYPAIR` environment variable for server-side transaction signing. Consistent with the existing solrengine ENV-based config pattern (`SOLANA_RPC_URL`, `SOLANA_NETWORK`, etc.). Loaded via `config/solana.yml`.

### 6. Stimulus controllers for client-side
Ship reusable Stimulus controllers that handle instruction submission (build tx from IDL, wallet signs, submit, poll confirmation) and account list rendering (fetch + decode + render via Turbo). Follows the existing `wallet_controller.js` pattern.

### 7. Program ID in config
Register program IDs in `config/solana.yml` alongside RPC URLs and network config. Supports per-network program IDs (mainnet vs devnet deployments have different addresses).

## What Gets Generated

Running `rails generate solrengine:program PiggyBank path/to/idl.json` would produce:

```
app/
  models/
    piggy_bank/
      lock.rb                    # ActiveModel account (Borsh fields, query methods)
  services/
    piggy_bank/
      lock_instruction.rb        # Server-side: build lock transaction
      unlock_instruction.rb      # Server-side: build unlock transaction
  javascript/
    controllers/
      piggy_bank_controller.js   # Stimulus: client-side instruction submission
config/
  idl/
    piggy_bank.json              # Copy of the IDL for reference
```

### Example: Account Model

```ruby
# app/models/piggy_bank/lock.rb
class PiggyBank::Lock < Solrengine::Programs::Account
  program_id "ZaU8j7XCKSxmmkMvg7NnjrLNK6eiLZbHsJQAc2rFzEN"

  borsh_field :dst, :pubkey
  borsh_field :exp, :u64

  # Query all locks for a destination wallet
  def self.for_wallet(wallet_address)
    query(filters: [
      { memcmp: { offset: 8, bytes: wallet_address } }
    ])
  end

  # Custom Rails-style methods
  def expired?
    exp < Time.now.to_i
  end

  def destination
    dst
  end
end
```

### Example: Instruction Builder

```ruby
# app/services/piggy_bank/lock_instruction.rb
class PiggyBank::LockInstruction < Solrengine::Programs::Instruction
  program_id "ZaU8j7XCKSxmmkMvg7NnjrLNK6eiLZbHsJQAc2rFzEN"

  argument :amt, :u64
  argument :exp, :u64

  account :payer, signer: true, writable: true
  account :dst
  account :lock, signer: true, writable: true
  account :system_program, address: "11111111111111111111111111111111"

  # Server-side: build and sign transaction
  def call
    build_transaction
    sign_and_send
  end
end
```

### Example: Stimulus Controller

```html
<!-- In a Rails view -->
<div data-controller="piggy-bank"
     data-piggy-bank-program-id-value="ZaU8j7XCKSxmmkMvg7NnjrLNK6eiLZbHsJQAc2rFzEN"
     data-piggy-bank-idl-path-value="/idl/piggy_bank.json">

  <form data-action="submit->piggy-bank#lock">
    <input data-piggy-bank-target="amount" type="number" step="0.01">
    <input data-piggy-bank-target="duration" type="number">
    <button type="submit">Lock SOL</button>
  </form>

  <div data-piggy-bank-target="locks">
    <!-- Turbo Stream updates here -->
  </div>
</div>
```

## Technical Considerations

### Anchor Discriminators
Anchor uses 8-byte discriminators to identify accounts and instructions:
- **Account discriminator:** `SHA256("account:<AccountName>")[0..7]`
- **Instruction discriminator:** `SHA256("global:<instruction_name>")[0..7]`

The gem must compute these from the IDL and prepend them when encoding instruction data or skip them when decoding account data. The `borsh_field` DSL should auto-handle the 8-byte offset.

### Transaction Binary Format
Solana transactions have a specific binary layout: signatures array, message header (num signers, read-only counts), account keys, recent blockhash, and compact-u16 encoded instruction arrays. The `transaction_builder.rb` must serialize this correctly. The existing `solrengine-rpc` gem already handles `getLatestBlockhash` and `sendTransaction` (base64-encoded), so the builder focuses on constructing the message bytes and signing with Ed25519.

### PDA Derivation
Most real Anchor programs use Program Derived Addresses (PDAs) — deterministic addresses derived from seeds + program ID. Even though piggy_bank doesn't use them, nearly every production program does. PDA derivation is a `SHA256` + off-curve check — straightforward to implement and essential for account lookups. **Moved to v0.1 scope.**

### Existing Ruby Landscape
- **`borsh` gem (dryruby):** Full Borsh spec. Use as dependency.
- **`solana-ruby-web3js`:** Covers RPC and basic transactions but NOT custom program instructions or Borsh. Overlaps with `solrengine-rpc`. Not worth depending on.
- **`borsh-rb`:** Dead project (2021), built for NEAR. Skip.

## Gem Internal Architecture

```
solrengine-programs/
  lib/
    solrengine/
      programs/
        idl_parser.rb          # Parse Anchor IDL JSON into Ruby structs
        borsh_types.rb         # Solana-specific Borsh layer (PublicKey, discriminators)
        account.rb             # Base class for account models
        instruction.rb         # Base class for instruction builders
        transaction_builder.rb # Build + sign + send Solana transactions
        pda.rb                 # Program Derived Address derivation
        query.rb               # getProgramAccounts with memcmp filters
        configuration.rb       # Program registry, keypair config
    generators/
      solrengine/
        program_generator.rb   # Rails generator: IDL → Ruby + JS files
  app/
    javascript/
      solrengine/
        program_controller.js  # Base Stimulus controller for program interaction
```

## Scope Boundaries

### In scope (v0.1)
- Anchor IDL parsing (instructions, accounts, types, events)
- Borsh serialization via `borsh` gem + Solana-specific types layer
- Anchor discriminator computation (account + instruction)
- ActiveModel account base class with RPC querying (`getProgramAccounts` + `memcmp`)
- Instruction builder base class with Borsh-encoded instruction data
- Server-side transaction building, signing (Ed25519), and submission
- PDA (Program Derived Address) derivation
- Rails generator from IDL (`rails generate solrengine:program`)
- Base Stimulus controller for client-side instruction submission
- Integration with solrengine-rpc for RPC calls
- Integration with solrengine-realtime for account change notifications

### Out of scope (future)
- CPI (Cross-Program Invocation) composition
- Native (non-Anchor) program support
- IDL diff/migration tooling (re-run generator manually for now)
- Account indexing / local DB sync
- Token program (SPL) specific helpers (already in solrengine-tokens)
- Versioned transactions (v0 legacy transactions first)

### Dependencies
- `solrengine-rpc` (~> 0.1) — RPC client, network config, SSL handling
- `borsh` (~> 0.2) — Borsh binary serialization
- `ed25519` — Transaction signing (already used by solrengine-auth)
- `base58` — Address encoding (already used by solrengine-auth)

## Resolved Questions

1. **Generator re-run strategy:** Skip existing files, only generate new ones. Developer manually updates existing files when IDL changes. Safest approach for customized code — no risk of overwriting developer additions.
2. **Versioned vs legacy transactions:** Legacy transactions only for v0.1. Simpler API. Versioned (v0) support added later without breaking changes.
3. **Stimulus controller granularity:** Per-program generated controllers. Generator creates a Stimulus controller per program with typed methods matching each instruction. More explicit, more customizable, consistent with the generator-first philosophy.

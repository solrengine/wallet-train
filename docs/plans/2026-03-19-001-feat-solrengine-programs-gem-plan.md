---
title: "feat: Add solrengine-programs gem for Solana program interaction"
type: feat
status: completed
date: 2026-03-19
origin: docs/brainstorms/2026-03-19-solrengine-programs-brainstorm.md
---

# feat: Add solrengine-programs gem for Solana program interaction

## Overview

New gem (`solrengine-programs`) that adds custom Solana program interaction to the SolRengine framework. Parses Anchor IDL files, scaffolds Ruby account models and instruction builders via a Rails generator, implements Borsh serialization with the `borsh` gem, builds/signs transactions server-side, and ships per-program Stimulus controllers for client-side wallet-signed submissions.

This fills the last major gap in the stack — the existing 5 gems handle auth, RPC, tokens, transfers, and real-time monitoring, but none can interact with arbitrary on-chain programs.

## Problem Statement

Building Rails apps that interact with custom Solana programs (Anchor or otherwise) requires:
- Parsing the program's IDL to understand its interface
- Encoding/decoding Borsh binary data for instruction arguments and account state
- Building Solana transactions with correct account metas, discriminators, and signatures
- Querying program-owned accounts via RPC with efficient filters
- Submitting transactions from both server (automated) and client (wallet-signed)

None of this exists in Ruby. The `borsh` gem provides raw encoding primitives but nothing Solana-specific. The `solana-ruby-web3js` gem handles RPC but not custom program instructions. SolRengine's existing `solrengine-rpc` already covers the RPC layer — this gem builds the program interaction layer on top.

## Proposed Solution

A single gem with four layers:

1. **IDL Parser** — reads Anchor IDL JSON, extracts instructions, accounts, types, errors
2. **Borsh + Solana Types** — thin layer over the `borsh` gem for PublicKey, discriminators, PDA derivation
3. **Runtime Classes** — `Account` base class (ActiveModel, Borsh decode, RPC query) and `Instruction` base class (Borsh encode, transaction build, sign, send)
4. **Rails Generator** — `rails generate solrengine:program PiggyBank path/to/idl.json` scaffolds concrete classes + Stimulus controller

## Technical Approach

### Architecture

```
solrengine-programs/
├── lib/
│   ├── solrengine/programs.rb                    # Entry point, configure block
│   ├── solrengine/programs/
│   │   ├── version.rb
│   │   ├── engine.rb                             # Rails::Engine, isolate_namespace
│   │   ├── configuration.rb                      # Program registry, keypair
│   │   ├── idl_parser.rb                         # Anchor IDL JSON → Ruby structs
│   │   ├── borsh_types.rb                        # Solana Borsh layer (PublicKey, discriminators)
│   │   ├── account.rb                            # Base class for account models
│   │   ├── instruction.rb                        # Base class for instruction builders
│   │   ├── transaction_builder.rb                # Build legacy tx binary, sign, encode
│   │   ├── pda.rb                                # Program Derived Address derivation
│   │   ├── error_mapper.rb                       # Map Anchor error codes → messages
│   │   └── query.rb                              # getProgramAccounts with memcmp
│   └── generators/solrengine/program/
│       ├── program_generator.rb                  # IDL → scaffolded files
│       └── templates/
│           ├── account.rb.erb
│           ├── instruction.rb.erb
│           └── stimulus_controller.js.erb
├── app/
│   └── assets/javascripts/solrengine/programs/
│       └── program_controller.js                 # Base Stimulus controller
├── test/
│   ├── test_helper.rb
│   ├── lib/solrengine/programs/
│   │   ├── idl_parser_test.rb
│   │   ├── borsh_types_test.rb
│   │   ├── account_test.rb
│   │   ├── instruction_test.rb
│   │   ├── transaction_builder_test.rb
│   │   ├── pda_test.rb
│   │   ├── error_mapper_test.rb
│   │   └── query_test.rb
│   └── generators/
│       └── program_generator_test.rb
├── solrengine-programs.gemspec
├── Gemfile
├── Rakefile
└── README.md
```

### Implementation Phases

#### Phase 1: Foundation — Borsh Types + IDL Parser

Build the primitives everything else depends on.

**1a. Borsh Solana Types (`lib/solrengine/programs/borsh_types.rb`)**

Thin wrapper over the `borsh` gem (dryruby, 0.2.0) adding Solana-specific concerns:
- `PublicKey` — read/write 32-byte fixed array, expose as Base58 string
- `Discriminator` — compute 8-byte SHA256 prefix for account (`"account:Name"`) and instruction (`"global:name"`) discriminators
- Type registry mapping IDL type strings (`"u64"`, `"pubkey"`, `"bool"`, `"string"`, `"Vec<u64>"`, `"Option<pubkey>"`) to `borsh` gem read/write calls
- Struct encoding/decoding from IDL field definitions

**1b. IDL Parser (`lib/solrengine/programs/idl_parser.rb`)**

Parse Anchor IDL JSON (spec version 0.1.0, post-Anchor 0.30) into Ruby data structures:
- `IdlParser.parse(json_string)` → `ParsedIdl` struct
- `ParsedIdl#program_id` — program address (Base58)
- `ParsedIdl#instructions` — array of `ParsedInstruction` (name, discriminator, accounts, args)
- `ParsedIdl#accounts` — array of `ParsedAccount` (name, discriminator, fields from types)
- `ParsedIdl#types` — array of `ParsedType` (name, kind, fields)
- `ParsedIdl#errors` — array of `ParsedError` (code, name, message)
- Fail fast with clear message if `metadata.spec` is not `"0.1.0"`

**1c. PDA Derivation (`lib/solrengine/programs/pda.rb`)**

- `Pda.find_program_address(seeds, program_id)` → `[address, bump]`
- Seeds: array of byte strings (developer converts types to bytes)
- SHA256 hash + off-curve check, matching Solana's `createProgramAddress`
- Helper: `Pda.to_seed(value, type)` for common conversions (`:string` → UTF-8 bytes, `:pubkey` → 32 bytes from Base58, `:u32` → 4 little-endian bytes, etc.)

**Deliverables:**
- [x] `borsh_types.rb` with PublicKey, Discriminator, type registry
- [x] `idl_parser.rb` with ParsedIdl, ParsedInstruction, ParsedAccount, ParsedType, ParsedError
- [x] `pda.rb` with find_program_address and seed helpers
- [x] Tests for all three using piggy_bank IDL as fixture
- [x] Verify discriminators match Anchor's computed values from piggy_bank IDL

**Success criteria:** Can parse piggy_bank IDL, compute correct discriminators, encode/decode Lock struct, derive PDAs.

---

#### Phase 2: Runtime — Account + Instruction Base Classes

**2a. Account Base Class (`lib/solrengine/programs/account.rb`)**

```ruby
class Solrengine::Programs::Account
  include ActiveModel::Model
  include ActiveModel::Attributes

  class << self
    def program_id(id = nil)
      id ? @program_id = id : @program_id
    end

    def borsh_field(name, type, **options)
      attribute name
      borsh_fields << { name: name, type: type, **options }
    end

    def borsh_fields
      @borsh_fields ||= []
    end

    # Query via getProgramAccounts
    def query(filters: [], commitment: "confirmed")
      # Prepend dataSize filter (discriminator + sum of field sizes)
      # Prepend discriminator memcmp filter
      # Call Solrengine::Rpc.client.request("getProgramAccounts", ...)
      # Decode each result with from_account_data
    end

    def from_account_data(pubkey, data_base64, lamports:)
      # Base64 decode, skip 8-byte discriminator, Borsh decode fields
    end

    def discriminator
      Solrengine::Programs::BorshTypes::Discriminator.for_account(name.demodulize)
    end
  end

  attr_reader :pubkey, :lamports
end
```

Key behaviors:
- `query(filters:)` calls `getProgramAccounts` with automatic `dataSize` and discriminator filters
- Require at least one user-provided `memcmp` filter to prevent unbounded queries on large programs (see SpecFlow gap)
- `from_account_data` decodes Borsh binary, skipping 8-byte discriminator
- Gracefully handle closed accounts (empty data) — skip with warning, don't crash
- Extra trailing bytes ignored for forward compatibility

**2b. Instruction Base Class (`lib/solrengine/programs/instruction.rb`)**

```ruby
class Solrengine::Programs::Instruction
  include ActiveModel::Validations

  class << self
    def program_id(id = nil)
      id ? @program_id = id : @program_id
    end

    def argument(name, type)
      attr_accessor name
      arguments << { name: name, type: type }
    end

    def account(name, signer: false, writable: false, address: nil)
      attr_accessor name
      accounts << { name: name, signer: signer, writable: writable, address: address }
    end
  end

  def instruction_data
    # 8-byte discriminator + Borsh-encoded arguments
  end

  def to_instruction
    # { program_id:, accounts: [AccountMeta...], data: instruction_data }
  end
end
```

Key behaviors:
- ActiveModel validations on arguments (validate before encoding)
- `instruction_data` computes discriminator + Borsh-encodes args
- `to_instruction` returns a hash suitable for `TransactionBuilder`

**2c. Error Mapper (`lib/solrengine/programs/error_mapper.rb`)**

- `ErrorMapper.new(parsed_errors)` — takes IDL error definitions
- `map(error_code)` → `{ name: "LockNotExpired", message: "The lock has not expired yet", code: 6001 }`
- Parse RPC error responses: extract `Custom` error code from `InstructionError` array
- Raise `Solrengine::Programs::ProgramError` with mapped name + message

**2d. Transaction Builder (`lib/solrengine/programs/transaction_builder.rb`)**

Build, sign, and submit Solana transactions server-side.

```ruby
class Solrengine::Programs::TransactionBuilder
  def initialize
    @instructions = []
    @signers = []
  end

  def add_instruction(instruction)        # from Instruction#to_instruction
  def add_signer(keypair)                 # Ed25519 keypair
  def set_fee_payer(pubkey)
  def set_recent_blockhash(blockhash)     # or fetch automatically

  def build                               # → serialized transaction bytes
  def sign_and_send(commitment: "confirmed")
    # Fetch blockhash, build, sign, base64 encode
    # Submit via Solrengine::Rpc.client.request("sendTransaction", ...)
    # Return signature
  end
end
```

Transaction format: **Legacy** (no version prefix byte). This is simpler and sufficient for v0.1. The existing `transfer_controller.js` uses v0 on the client side — this is fine because server-side and client-side transactions are independent flows.

> **Design note:** Legacy was chosen over v0 for simplicity (see brainstorm: resolved question #2). The builder API (`add_instruction`, `sign_and_send`) is forward-compatible — adding v0 support later means changing the serialization internals, not the public API.

Binary layout:
1. Signatures: compact-u16 count + 64-byte Ed25519 signatures
2. Message: header (3 bytes: num_signers, num_readonly_signed, num_readonly_unsigned) + account keys (32 bytes each) + recent blockhash (32 bytes) + instructions (compact-u16 count, each with program_id_index, account_indices, data)

**Deliverables:**
- [x] `account.rb` with borsh_field DSL, query, from_account_data, discriminator
- [x] `instruction.rb` with argument/account DSL, instruction_data, to_instruction
- [x] `error_mapper.rb` with IDL error → Ruby exception mapping
- [x] `transaction_builder.rb` with build, sign_and_send
- [x] `query.rb` helper for getProgramAccounts with filter building (built into account.rb)
- [x] Tests: account decode with piggy_bank Lock data, instruction encode with lock args, transaction build + sign, error mapping

**Success criteria:** Can decode a piggy_bank Lock account from RPC data, build a lock instruction, construct a signed transaction, and map error code 6001 to "InvalidExpiration".

---

#### Phase 3: Configuration + Engine

**3a. Configuration (`lib/solrengine/programs/configuration.rb`)**

Follow the class-based configuration pattern (like auth/rpc):

```ruby
module Solrengine
  module Programs
    class Configuration
      attr_accessor :keypair_format  # :base58 (default), :json_array, :file_path
      attr_reader :server_keypair

      def initialize
        @keypair_format = :base58
      end

      def server_keypair
        @server_keypair ||= load_keypair
      end

      private

      def load_keypair
        raw = ENV["SOLANA_KEYPAIR"]
        return nil unless raw.present?
        # Parse based on keypair_format
        # Return { secret_key: bytes, public_key: bytes }
      end
    end
  end
end
```

Keypair format: **Base58-encoded 64-byte keypair** (secret + public) by default, matching `solana-keygen` output. Also support JSON byte array (for compatibility with Solana CLI's `id.json`).

> **Security note:** The server keypair controls funds. It should NEVER be logged, committed to source control, or exposed in error messages. The configuration class loads it once at boot and holds it in memory only.

**3b. Engine (`lib/solrengine/programs/engine.rb`)**

```ruby
module Solrengine
  module Programs
    class Engine < ::Rails::Engine
      isolate_namespace Solrengine::Programs

      initializer "solrengine-programs.assets" do |app|
        app.config.assets.paths << root.join("app/assets/javascripts")
      end
    end
  end
end
```

**Deliverables:**
- [x] `configuration.rb` with keypair loading (base58 + JSON array formats)
- [x] `engine.rb` with isolate_namespace and asset paths
- [x] `solrengine/programs.rb` entry point with configure block
- [x] `version.rb` at 0.1.0
- [x] Gemspec with dependencies: `rails >= 7.1`, `solrengine-rpc ~> 0.1`, `borsh ~> 0.2`, `ed25519`, `base58`
- [x] Gemfile with `gem "solrengine-rpc", path: "../solrengine-rpc"` for local dev

**Success criteria:** Gem loads in a Rails app, configuration is accessible, server keypair loads from ENV.

---

#### Phase 4: Rails Generator

**4a. Program Generator (`lib/generators/solrengine/program/program_generator.rb`)**

```bash
rails generate solrengine:program PiggyBank path/to/idl.json
```

Generator flow:
1. Parse IDL with `IdlParser`
2. Validate IDL spec version (fail fast if not 0.1.0)
3. For each account type in IDL → scaffold `app/models/<program_name>/<account_name>.rb`
4. For each instruction in IDL → scaffold `app/services/<program_name>/<instruction_name>_instruction.rb`
5. Scaffold `app/javascript/controllers/<program_name>_controller.js`
6. Copy IDL to `config/idl/<program_name>.json`
7. **Skip existing files** — print message listing skipped files and what new content would have been generated

File naming: program name → snake_case directory, account/instruction names → snake_case files.

**Generated account model template:**

```ruby
# app/models/<program_name>/<account_name>.rb
class <%= program_class %>::<%= account_class %> < Solrengine::Programs::Account
  program_id "<%= program_id %>"

  <% fields.each do |field| %>
  borsh_field :<%= field.name %>, :<%= field.type %>
  <% end %>

  # Add custom query methods, e.g.:
  # def self.for_wallet(wallet_address)
  #   query(filters: [
  #     { memcmp: { offset: 8, bytes: wallet_address } }
  #   ])
  # end
end
```

**Generated instruction builder template:**

```ruby
# app/services/<program_name>/<instruction_name>_instruction.rb
class <%= program_class %>::<%= instruction_class %> < Solrengine::Programs::Instruction
  program_id "<%= program_id %>"

  <% args.each do |arg| %>
  argument :<%= arg.name %>, :<%= arg.type %>
  <% end %>

  <% accounts.each do |acct| %>
  account :<%= acct.name %><%= ", signer: true" if acct.signer %><%= ", writable: true" if acct.writable %><%= ", address: \"#{acct.address}\"" if acct.address %>
  <% end %>
end
```

**Generated Stimulus controller:**

The Stimulus controller handles client-side instruction submission. Rather than doing Borsh encoding in JS, it follows the existing transfer pattern: the server builds the instruction data, the client wraps it in a transaction and has the wallet sign.

Flow:
1. User fills form → Stimulus controller sends params to Rails endpoint
2. Rails controller builds instruction data (Borsh-encoded) + fetches blockhash
3. Returns instruction data + account metas + blockhash to client as JSON
4. Stimulus controller constructs transaction message, calls wallet `signAndSendTransaction`
5. Reports signature back to server for confirmation tracking

This avoids shipping a JS Borsh encoder and keeps the pattern consistent with `transfer_controller.js`.

**Deliverables:**
- [x] `program_generator.rb` with IDL parsing, file scaffolding, skip-existing logic
- [x] `account.rb.erb` template
- [x] `instruction.rb.erb` template
- [x] `stimulus_controller.js.erb` template
- [ ] Generator test with piggy_bank IDL fixture (requires Rails app context)
- [x] Print diff of skipped files when re-running

**Success criteria:** Running `rails generate solrengine:program PiggyBank target/idl/piggy_bank.json` produces correct Lock model, LockInstruction + UnlockInstruction services, and piggy_bank_controller.js.

---

#### Phase 5: Meta-gem Integration + Testing

**5a. Update meta-gem**

In `/home/me/Code/solrengine/`:
- Add `spec.add_dependency "solrengine-programs", "~> 0.1"` to gemspec
- Add `require "solrengine/programs"` to `lib/solrengine.rb`
- No install generator changes needed (programs are installed per-program, not globally)

**5b. End-to-end test with piggy_bank**

Manual validation in the WalletTrain app:
1. Add `solrengine-programs` to Gemfile (path: `../solrengine-programs`)
2. Run `rails generate solrengine:program PiggyBank ~/Cyfrin/Solana/Section5/piggy_bank/target/idl/piggy_bank.json`
3. Verify generated files are correct
4. On devnet: query existing Lock accounts, decode data, verify fields
5. Server-side: build a lock instruction, sign with devnet keypair, submit
6. Client-side: use Stimulus controller to lock SOL via Phantom

**5c. Gem test suite**

Following the transactions gem test pattern (in-memory SQLite, stub RPC):
- IDL parser tests with piggy_bank IDL fixture
- Borsh types tests (PublicKey encode/decode, discriminator computation)
- PDA derivation tests (known seeds → known addresses)
- Account decode tests with real base64 account data from devnet
- Instruction encode tests (verify output matches Anchor's encoding)
- Transaction builder tests (verify binary format, signature)
- Error mapper tests
- Generator tests (verify file output)

**Deliverables:**
- [x] Meta-gem updated with solrengine-programs dependency
- [ ] End-to-end validation on devnet with piggy_bank
- [x] Full test suite (Minitest, 65 tests, 149 assertions)
- [x] README with usage examples

**Success criteria:** All tests pass. Can interact with piggy_bank program from WalletTrain app on devnet — query locks, create lock (server + client), unlock expired lock.

## System-Wide Impact

### Interaction Graph

Generator run → creates files in `app/models/`, `app/services/`, `app/javascript/controllers/`, `config/idl/`. No runtime side effects.

Server-side instruction submission: `Instruction#instruction_data` → `TransactionBuilder#build` → `TransactionBuilder#sign_and_send` → `Solrengine::Rpc.client.request("sendTransaction")` → RPC node. If using confirmation tracking, triggers `Solrengine::Transactions::ConfirmationJob`.

Client-side flow: Stimulus controller → `fetch()` to Rails endpoint → server builds instruction data → returns JSON → Stimulus controller → wallet `signAndSendTransaction` → Turbo Stream broadcast on confirmation.

Realtime: `solrengine-realtime` `AccountMonitor` detects on-chain state change → callback → application decodes account data using generated model → broadcasts via Turbo Streams.

### Error & Failure Propagation

- **IDL parse failure:** `IdlParser::UnsupportedVersionError` raised at generator time. No runtime impact.
- **Borsh decode failure:** `Solrengine::Programs::DeserializationError` raised in `Account.from_account_data`. Query methods rescue and skip malformed accounts with a warning log.
- **RPC failure:** Propagated from `Solrengine::Rpc::Client` (existing error handling). `TransactionBuilder#sign_and_send` surfaces RPC errors with Anchor error mapping when available.
- **Transaction failure:** `Solrengine::Programs::TransactionError` with mapped Anchor error (name + message) if the IDL has error definitions. Falls back to raw RPC error if unmapped.
- **Keypair missing:** `Solrengine::Programs::ConfigurationError` raised on `sign_and_send` if `SOLANA_KEYPAIR` is not set. Clear message: "Server keypair not configured. Set SOLANA_KEYPAIR environment variable."

### State Lifecycle Risks

No local database state — all account data lives on-chain. No orphaned records possible.

The only state risk is a partially-signed transaction that gets submitted but fails — the server has no record of the attempt. For tracked transactions, integrate with `solrengine-transactions` to create a Transfer record before submission.

### API Surface Parity

- **Ruby API:** `Account.query`, `Account.from_account_data`, `Instruction#instruction_data`, `Instruction#to_instruction`, `TransactionBuilder#sign_and_send`, `Pda.find_program_address`
- **JS API:** Stimulus controller with per-instruction action methods (e.g., `lock()`, `unlock()`)
- Both sides share the IDL as source of truth. Server-side Borsh encoding, client-side transaction assembly.

### Integration Test Scenarios

1. **Parse IDL → generate → query accounts → decode:** Full pipeline from IDL to decoded Ruby objects on devnet
2. **Build instruction → sign → send → confirm:** Server-side transaction lifecycle on devnet
3. **Stimulus submit → server builds data → wallet signs → confirm:** Client-side round-trip
4. **Invalid instruction args → validation error before encoding:** Validates at Ruby level, not on-chain
5. **Program error → mapped exception:** Submit instruction that triggers Anchor error, verify Ruby exception has correct name/message

## Acceptance Criteria

### Functional Requirements

- [ ] `IdlParser` correctly parses piggy_bank Anchor IDL (spec 0.1.0)
- [ ] `BorshTypes` encodes/decodes PublicKey, computes correct discriminators
- [ ] `Pda.find_program_address` produces correct addresses for known seeds
- [ ] `Account` subclass decodes base64 account data from RPC into typed Ruby attributes
- [ ] `Account.query` calls `getProgramAccounts` with dataSize + discriminator + user filters
- [ ] `Instruction` subclass encodes discriminator + Borsh arguments
- [ ] `TransactionBuilder` produces valid signed legacy transactions
- [ ] `TransactionBuilder#sign_and_send` submits via RPC and returns signature
- [ ] `ErrorMapper` maps Anchor custom error codes to IDL-defined names/messages
- [ ] Generator scaffolds account models, instruction builders, and Stimulus controller from IDL
- [ ] Generator skips existing files and prints informational message
- [ ] Configuration loads server keypair from `SOLANA_KEYPAIR` ENV (base58 or JSON array)
- [ ] Stimulus controller submits instructions via wallet using server-built instruction data

### Non-Functional Requirements

- [ ] Gem has zero runtime dependencies beyond `rails`, `solrengine-rpc`, `borsh`, `ed25519`, `base58`
- [ ] All Borsh operations work without native extensions (pure Ruby via `borsh` gem)
- [ ] Account queries require at least one memcmp filter (prevent unbounded `getProgramAccounts`)
- [ ] Server keypair is never logged or exposed in error messages

### Quality Gates

- [ ] Minitest suite with 90%+ coverage of `lib/`
- [ ] All tests pass with stubbed RPC (no network dependency in CI)
- [ ] End-to-end validation on devnet with piggy_bank program
- [ ] README with installation, generator usage, account querying, instruction building examples

## Dependencies & Prerequisites

- `borsh` gem (0.2.0, dryruby) — must be released and stable
- `solrengine-rpc` (~> 0.1) — existing, working
- `ed25519` gem — existing dependency of `solrengine-auth`
- `base58` gem — existing dependency of `solrengine-auth`
- Anchor IDL spec 0.1.0 format (post-Anchor 0.30)
- A deployed Anchor program on devnet for testing (piggy_bank)

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `borsh` gem doesn't handle all Solana types | Low | High | Test with piggy_bank IDL early. Fall back to custom encoding for unsupported types |
| Transaction binary format bugs | Medium | High | Compare output byte-for-byte with Anchor.js-built transactions |
| `getProgramAccounts` rate-limited by RPC providers | Medium | Medium | Require memcmp filters. Document provider requirements (Helius recommended) |
| Anchor IDL format changes in future versions | Low | Medium | Version check at parse time. Support one version at a time |
| Server keypair compromise | Low | Critical | Document security practices. Never log. Consider adding keyfile path support |
| Multi-signer transactions needed by users | High | Medium | Out of scope for v0.1. Document as known limitation. Design API to be extensible |

## Known Limitations (v0.1)

- **No multi-signer transactions.** Server signs OR wallet signs, not both. This means programs requiring both admin + user signatures need a workaround (two separate transactions or a different auth model).
- **Legacy transactions only.** No v0 versioned transactions with address lookup tables. The builder API is forward-compatible for adding this later.
- **Anchor IDL 0.1.0 only.** Older Anchor IDL formats (pre-0.30) are not supported.
- **No CPI composition.** Cannot compose multiple program instructions that depend on each other's accounts in a single atomic transaction builder call. (Can still add multiple instructions to one transaction manually.)
- **No account indexing.** All queries hit RPC directly. No local DB sync or caching layer for program accounts.

## Future Considerations

- **Multi-signer transactions:** Server partially signs, sends to client for wallet co-signature. Most common production pattern.
- **Versioned (v0) transactions:** Address lookup tables for programs with many accounts.
- **Account caching:** Integrate with Solid Cache for program account data, invalidated by solrengine-realtime.
- **Realtime program account monitoring:** Extend `solrengine-realtime` with a registration API for program-specific account subscriptions and decode callbacks.
- **Compute budget instructions:** `setComputeUnitLimit` and `setComputeUnitPrice` for complex instructions and mainnet priority fees.
- **Transaction simulation:** `simulateTransaction` before `sendTransaction` for better error messages.
- **Generator `--force` flag:** Overwrite a specific file with the latest IDL-generated version, printing a diff.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-19-solrengine-programs-brainstorm.md](docs/brainstorms/2026-03-19-solrengine-programs-brainstorm.md) — Key decisions: single gem, generator-first with IDL parsing, ActiveModel accounts, `borsh` gem dependency, ENV-based keypair, per-program Stimulus controllers, legacy transactions.

### Internal References

- Gem structure pattern: all 5 existing gems at `/home/me/Code/solrengine-{auth,rpc,tokens,transactions,realtime}/`
- Generator pattern: `/home/me/Code/solrengine-transactions/lib/generators/solrengine/transactions/install_generator.rb`
- Configuration pattern: `/home/me/Code/solrengine-rpc/lib/solrengine/rpc/configuration.rb`
- Concern pattern: `/home/me/Code/solrengine-transactions/app/models/solrengine/transactions/transferable.rb`
- Stimulus pattern: `/home/me/Code/solrengine-transactions/app/assets/javascripts/solrengine/transactions/transfer_controller.js`
- Test pattern: `/home/me/Code/solrengine-transactions/test/test_helper.rb`
- Anchor IDL reference: `/home/me/Cyfrin/Solana/Section5/piggy_bank/target/idl/piggy_bank.json`
- Anchor program reference: `/home/me/Cyfrin/Solana/Section5/piggy_bank/programs/piggy_bank/src/`

### External References

- `borsh` gem: https://github.com/dryruby/borsh.rb
- Anchor IDL spec: https://github.com/coral-xyz/anchor
- Solana transaction format: https://solana.com/docs/core/transactions
- Borsh specification: https://borsh.io/

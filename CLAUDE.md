# CLAUDE.md - Umbra Protocol Build Guide

## PERSONA

You are **ShadowForge**, an elite ZK protocol architect specializing in Aztec Network development. You have deep expertise in:

- **Noir** - Aztec's Rust-like ZK language
- **Aztec.nr** - The private smart contract framework
- **Aztec.js** - TypeScript SDK for Aztec interactions
- **Zero-Knowledge Proofs** - PLONK, private state management, nullifiers
- **DeFi Protocol Design** - AMMs, orderbooks, matching engines, escrows
- **Privacy-Preserving Systems** - Private notes, encrypted state, viewing keys

You are building **Umbra Protocol** - the first production-grade dark pool on Aztec Network.

---

## PROJECT OVERVIEW

### What We're Building

**Umbra Protocol** is a privacy-native dark pool for Aztec Network that enables:
- Private OTC trades with no information leakage
- Hidden order books with encrypted intents
- Atomic settlement with ZK proofs
- Midpoint execution pegged to oracle prices
- Institutional compliance via viewing keys

### Why "Umbra"

Umbra (Latin for "shadow") represents the darkest part of a shadow - perfect for a dark pool. It's also short, memorable, and available.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        UMBRA PROTOCOL                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │   TRADER    │    │   TRADER    │    │   TRADER    │             │
│  │   (Buyer)   │    │  (Seller)   │    │   (Maker)   │             │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘             │
│         │                  │                  │                     │
│         ▼                  ▼                  ▼                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                    PXE (Client-Side)                     │      │
│  │  - Generate ZK proofs locally                            │      │
│  │  - Encrypt order details                                 │      │
│  │  - Manage private notes                                  │      │
│  └──────────────────────────────────────────────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                 UMBRA SMART CONTRACTS                    │      │
│  │                                                          │      │
│  │  ┌─────────────────┐  ┌─────────────────┐               │      │
│  │  │  UmbraVault     │  │  UmbraEscrow    │               │      │
│  │  │  (Deposits)     │  │  (OTC Trades)   │               │      │
│  │  └─────────────────┘  └─────────────────┘               │      │
│  │                                                          │      │
│  │  ┌─────────────────┐  ┌─────────────────┐               │      │
│  │  │  UmbraPool      │  │  UmbraOracle    │               │      │
│  │  │  (Dark Pool)    │  │  (Price Feed)   │               │      │
│  │  └─────────────────┘  └─────────────────┘               │      │
│  │                                                          │      │
│  └──────────────────────────────────────────────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                 ORDERFLOW SERVICE                        │      │
│  │  - REST API for order discovery                          │      │
│  │  - Encrypted order matching                              │      │
│  │  - Trade coordination                                    │      │
│  └──────────────────────────────────────────────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  AZTEC NETWORK                           │      │
│  │  - Private state trees                                   │      │
│  │  - ZK rollup to Ethereum                                 │      │
│  │  - Decentralized sequencers                              │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## BUILD SEQUENCE

Follow these files in order:

1. **`docs/00-SETUP.md`** - Environment setup and tooling
2. **`docs/01-CONTRACTS.md`** - Noir smart contract development
3. **`docs/02-ESCROW.md`** - OTC escrow contract implementation
4. **`docs/03-POOL.md`** - Dark pool matching engine
5. **`docs/04-ORDERFLOW.md`** - Orderflow service API
6. **`docs/05-CLI.md`** - CLI demo and testing
7. **`docs/06-FRONTEND.md`** - Web interface (optional)
8. **`docs/07-DEPLOY.md`** - Testnet deployment

---

## CRITICAL TECHNICAL CONTEXT

### Aztec Private State Model

Aztec uses a **UTXO-like model** for private state:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PRIVATE STATE (Notes)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  A "note" is an encrypted piece of data that only the owner can    │
│  decrypt and spend. When you "spend" a note, you:                  │
│                                                                     │
│  1. Create a NULLIFIER (proves note is spent, prevents double-     │
│     spending, but doesn't reveal which note was spent)             │
│                                                                     │
│  2. Create new NOTE(s) with updated values                         │
│                                                                     │
│  Example: Transfer 100 tokens from Alice to Bob                    │
│                                                                     │
│  BEFORE:                                                           │
│  ┌────────────────────────────────────────┐                        │
│  │ Alice's Note: value=100, owner=Alice  │                        │
│  └────────────────────────────────────────┘                        │
│                                                                     │
│  AFTER:                                                            │
│  ┌────────────────────────────────────────┐                        │
│  │ Nullifier: hash(Alice's Note)          │ (proves spent)        │
│  └────────────────────────────────────────┘                        │
│  ┌────────────────────────────────────────┐                        │
│  │ Bob's Note: value=100, owner=Bob       │ (new note created)    │
│  └────────────────────────────────────────┘                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Function Types in Aztec

```noir
// PRIVATE function - executed client-side, generates ZK proof
#[private]
fn transfer(to: AztecAddress, amount: u64) {
    // Only the caller can see inputs/outputs
    // Proof is submitted to network
}

// PUBLIC function - executed by sequencers, visible to all
#[public]
fn update_price(new_price: u64) {
    // Everyone can see this execution
}

// PRIVATE calling PUBLIC (allowed)
#[private]
fn deposit(amount: u64) {
    // Do private stuff...
    context.call_public_function(
        self.address,
        compute_selector("finalize_deposit"),
        [amount]
    );
}

// PUBLIC calling PRIVATE (NOT allowed - would leak private data)
```

### Key Aztec Patterns

```noir
// 1. STORAGE - Define state variables
#[storage]
struct Storage {
    admin: PrivateImmutable<AztecAddress>,
    balances: Map<AztecAddress, PrivateSet<ValueNote>>,
    total_supply: PublicMutable<U128>,
}

// 2. NOTES - Custom private data structures
#[note]
struct OrderNote {
    owner: AztecAddress,
    sell_token: AztecAddress,
    sell_amount: u64,
    buy_token: AztecAddress,
    buy_amount: u64,
    nonce: Field,
}

// 3. EMITTING ENCRYPTED NOTES
storage.balances.at(to).insert(&mut note).emit(
    encode_and_encrypt_note(&mut context, to, from)
);

// 4. CONSUMING NOTES (with nullifier)
let note = storage.balances.at(from).pop_notes(
    NoteGetterOptions::new().set_limit(1)
)[0];
// Note is automatically nullified when popped
```

---

## REFERENCE IMPLEMENTATION

We are forking and extending the **aztec-pioneers/aztec-otc-desk** prototype:

```bash
# The prototype structure
aztec-otc-desk/
├── packages/
│   ├── contracts/           # Noir contracts
│   │   ├── src/
│   │   │   ├── main.nr     # OTC Escrow Contract
│   │   │   └── types/      # Custom notes
│   │   └── ts/             # TypeScript bindings
│   ├── cli/                # CLI demo
│   └── api/                # Orderflow service
└── deps/
    └── aztec-standards/    # Standard library
```

**Key files to study:**
- `packages/contracts/src/main.nr` - Core escrow logic
- `packages/api/src/index.ts` - Orderflow API
- `packages/cli/scripts/` - Demo workflows

---

## IMPROVEMENTS OVER PROTOTYPE

The prototype is a **proof of concept**. We're building **production-grade** by adding:

| Feature | Prototype | Umbra |
|---------|-----------|-------|
| Matching | Manual fill | Automatic matching engine |
| Pricing | Fixed price | Oracle-pegged midpoint |
| Orders | Single escrow | Order book with priorities |
| Compliance | None | Viewing keys for auditors |
| Liquidity | P2P only | Market makers + P2P |
| UI | CLI only | CLI + Web interface |
| Fees | None | Protocol fees |
| Tokens | Any | Whitelisted + any |

---

## BUILD COMMANDS REFERENCE

```bash
# Environment setup
aztec-up                          # Install Aztec toolchain
aztec start --sandbox            # Start local sandbox

# Contract development
cd packages/contracts
aztec-nargo compile              # Compile Noir contracts
aztec-nargo test                 # Run Noir tests
bun run build                    # Build with TypeScript bindings

# Testing
bun test                         # Run all tests
bun run test:nr                  # Noir TXE tests only

# Orderflow service
cd packages/api
bun run dev                      # Start dev server
bun test                         # API tests

# CLI demo
cd packages/cli
bun run setup:deploy             # Deploy contracts
bun run order:create             # Create order
bun run order:fill               # Fill order
bun run balances                 # Check balances
```

---

## ERROR HANDLING PATTERNS

When you encounter errors, follow this decision tree:

```
ERROR TYPE                         SOLUTION
────────────────────────────────────────────────────────────────
"Cannot find module"              → Check Nargo.toml dependencies
                                  → Verify git tag matches sandbox version
                                  → Run `aztec-up` to update

"Note not found"                  → PXE not synced
                                  → Wrong account registered
                                  → Note already nullified

"Proof generation failed"         → Circuit too complex (simplify)
                                  → Invalid witness
                                  → Memory limit (increase Node memory)

"Transaction reverted"            → Check public function logic
                                  → Verify storage access patterns
                                  → Check msg.sender permissions

"PXE connection refused"          → Start sandbox: `aztec start --sandbox`
                                  → Check port (default 8080)

"Sandbox not ready"               → Wait for "Cannot enqueue vote cast..."
                                  → Docker not running
                                  → Port conflict
```

---

## SUCCESS CRITERIA

The build is complete when:

1. ✅ **Contracts compile** - `aztec-nargo compile` succeeds
2. ✅ **Tests pass** - All Noir and TS tests green
3. ✅ **Escrow works** - Can create and fill OTC orders privately
4. ✅ **Pool works** - Multiple orders match automatically
5. ✅ **API works** - REST endpoints for order management
6. ✅ **CLI works** - Full demo workflow executable
7. ✅ **Deployed** - Running on Aztec testnet

---

## IMPORTANT WARNINGS

⚠️ **VERSION COMPATIBILITY**
- Aztec is rapidly evolving. Pin all versions.
- Current stable: `v1.2.0` (check docs for latest)
- Noir contracts MUST match sandbox version

⚠️ **PRIVATE vs PUBLIC**
- Never leak private data in public functions
- Private → Public calls OK
- Public → Private calls IMPOSSIBLE

⚠️ **NOTE MANAGEMENT**
- Notes are consumed when read (UTXO model)
- Always handle change notes
- PXE must be synced to see notes

⚠️ **DOCKER REQUIREMENTS**
- Sandbox runs in Docker
- Ensure Docker has 8GB+ memory
- Check Docker is running before `aztec start`

---

## NEXT STEPS

1. Read `docs/00-SETUP.md` to set up your environment
2. Follow each doc in sequence
3. Test after each major step
4. Deploy to testnet when all tests pass

**LFG! 🚀**

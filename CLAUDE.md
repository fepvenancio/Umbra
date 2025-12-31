# CLAUDE.md - Umbra Protocol Build Guide

## PROJECT OVERVIEW

**Umbra Protocol** is a dark pool for Aztec Network. It enables OTC trading with atomic settlement and oracle-based pricing.

### Contracts

- **UmbraEscrow** — Bilateral OTC trades between two parties
- **UmbraPool** — Order book with automatic matching at oracle prices
- **SimpleOracle** — Price feed for the pool (testnet only)

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        UMBRA PROTOCOL                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Traders                                                            │
│     │                                                               │
│     ▼                                                               │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                    PXE (Client-Side)                     │      │
│  │  - Generate ZK proofs locally                            │      │
│  │  - Manage private token notes                            │      │
│  └──────────────────────────────────────────────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                 UMBRA CONTRACTS                          │      │
│  │                                                          │      │
│  │  UmbraEscrow     UmbraPool       SimpleOracle           │      │
│  │  (OTC Trades)    (Dark Pool)     (Price Feed)           │      │
│  │                                                          │      │
│  └──────────────────────────────────────────────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  AZTEC NETWORK                           │      │
│  │  - Private state trees                                   │      │
│  │  - ZK rollup to Ethereum                                 │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## BUILD SEQUENCE

1. **`docs/00-SETUP.md`** — Environment setup
2. Compile and test contracts
3. Start orderflow API
4. Run CLI demo

---

## AZTEC TECHNICAL CONTEXT

### Private State Model

Aztec uses a UTXO-like model for private state. A "note" is encrypted data only the owner can decrypt.

When you spend a note:
1. Create a **nullifier** — proves note is spent without revealing which
2. Create new note(s) with updated values

```
Example: Transfer 100 tokens from Alice to Bob

BEFORE:
┌────────────────────────────────────────┐
│ Alice's Note: value=100, owner=Alice  │
└────────────────────────────────────────┘

AFTER:
┌────────────────────────────────────────┐
│ Nullifier: hash(Alice's Note)          │  ← proves spent
└────────────────────────────────────────┘
┌────────────────────────────────────────┐
│ Bob's Note: value=100, owner=Bob       │  ← new note
└────────────────────────────────────────┘
```

### Function Types

```noir
// PRIVATE — executed client-side, generates ZK proof
#[private]
fn transfer(to: AztecAddress, amount: u64) {
    // Only caller sees inputs/outputs
}

// PUBLIC — executed by sequencers, visible to all
#[public]
fn update_price(new_price: u64) {
    // Everyone sees this
}

// PRIVATE calling PUBLIC — allowed
// PUBLIC calling PRIVATE — not allowed (would leak data)
```

### Storage Patterns

```noir
#[storage]
struct Storage {
    admin: PublicImmutable<AztecAddress>,     // Set once, visible
    balances: Map<AztecAddress, PrivateSet<ValueNote>>,  // Encrypted
    total_supply: PublicMutable<U128>,        // Visible, mutable
}
```

---

## PRIVACY MODEL

**Private (hidden from observers):**
- Token balances — stored as encrypted notes in AIP-20 contracts
- Transfer amounts — ZK proofs verify without revealing
- Transaction sender — private function callers are hidden

**Public (visible on-chain):**
- Order metadata — tokens, amounts, owner, limits, deadlines
- Order status — filled, cancelled, partial fill amounts
- Protocol config — fees, admin, oracle address

Orders are public by design. A matcher must read orders to pair them. The privacy comes from Aztec's token layer — balances and transfers stay hidden.

---

## BUILD COMMANDS

```bash
# Environment setup
aztec-up                          # Install Aztec toolchain
aztec start --sandbox            # Start local sandbox

# Contract development
cd packages/contracts
aztec-nargo compile              # Compile Noir contracts
aztec-nargo test                 # Run Noir tests

# Testing
bun test                         # Run all tests

# Orderflow service
cd packages/api
bun run dev                      # Start dev server

# CLI demo
cd packages/cli
bun run scripts/demo.ts          # Run demo
```

---

## ERROR HANDLING

```
ERROR                              SOLUTION
─────────────────────────────────────────────────────────────
"Cannot find module"              → Check Nargo.toml dependencies
                                  → Run `aztec-up` to update

"Note not found"                  → PXE not synced
                                  → Note already nullified

"Proof generation failed"         → Circuit too complex
                                  → Invalid witness

"Transaction reverted"            → Check public function logic
                                  → Verify storage access

"PXE connection refused"          → Start sandbox: `aztec start --sandbox`

"Sandbox not ready"               → Wait for ready message
                                  → Check Docker is running
```

---

## SUCCESS CRITERIA

1. `aztec-nargo compile` succeeds
2. `bun test` passes
3. Escrow: create and fill orders
4. Pool: orders match automatically
5. API: serves orderflow requests
6. CLI: demo runs end-to-end

---

## WARNINGS

**VERSION COMPATIBILITY**
- Aztec evolves rapidly. Pin versions.
- Noir contracts must match sandbox version.

**PRIVATE vs PUBLIC**
- Never leak private data in public functions
- Private → Public calls OK
- Public → Private calls impossible

**NOTE MANAGEMENT**
- Notes are consumed when read (UTXO model)
- PXE must sync to see notes

**DOCKER**
- Sandbox runs in Docker
- Ensure Docker has 8GB+ memory

# Security & Production Readiness

**Status: Testnet Ready**

This document covers security measures and production readiness of Umbra Protocol.

---

## Security Fixes

### Fee Validation
Fees are stored in contract state and validated on every operation. Callers cannot bypass fees by providing fake values.

### Collateral Requirements
Buy orders must lock quote tokens upfront. Prevents order spam and ensures fills can execute.

### Event Emission
All state changes emit events: `OrderCreated`, `OrderFilled`, `OrderCancelled`, `OrderMatched`, `PairAdded`.

### Deadline Enforcement
Orders expire at specified blocks. Validated using `context.block_number()`.

### Price Validation
Limit orders checked against oracle price. Buy limits must be >= oracle, sell limits must be <= oracle.

### AIP-20 Compliance
Token interface uses standard function signatures. Compatible with Aztec Standards tokens.

### Oracle Staleness
Configurable `max_oracle_age_blocks`. Stale prices rejected during matching.

### Reentrancy Guards
All state-modifying internal functions have reentrancy protection (defense in depth).

### Token Whitelist
Both Escrow and Pool support token/pair whitelists. Admin controls which assets can trade.

### Underflow Protection
Order count decrements check for zero before subtracting.

### Refund Tracking
Market buy orders track locked quote amount for accurate partial fill refunds.

### Nonce Handling
Users provide one nonce for their transfer. Contract generates nonces for its own transfers using `random()`.

---

## Why Orders Are Public

Orders use `PublicMutable` storage by design:

1. **Matcher access** — A matcher must read both orders to pair them
2. **Partial fills** — Same order can be filled multiple times
3. **Discovery** — Orders need to be queryable for matching

**Privacy comes from the token layer:**
- Balances are encrypted notes in AIP-20 token contracts
- Transfers execute privately with ZK proofs
- Only order metadata is public, not wallet contents

---

## Access Control

Admin-only functions:
- `set_fee`, `set_fee_recipient`
- `set_oracle`, `set_max_oracle_age`
- `set_taker_fee`, `set_maker_fee`
- `add_pair`, `remove_pair`
- `add_token`, `remove_token`
- `pause`, `unpause`
- `set_price` (Oracle)

**Immutable:** Admin address (set once in constructor)

---

## Fee Caps

All fees capped at 100 bps (1%). Enforced in constructor and setter functions.

---

## Transaction Atomicity

Aztec transactions are atomic. If public validation fails after private execution, the entire transaction reverts. Token transfers roll back automatically.

---

## Testnet vs Mainnet

**Ready now (testnet):**
- Contract logic and security patterns
- Access control and fee management
- Order lifecycle (create, fill, cancel, match)
- Event emission for indexing
- SimpleOracle for price feeds

**Required for mainnet:**
- Formal security audit
- L1 oracle bridge (Chainlink/Pyth)
- Integration tests with Aztec sandbox

---

## Verification

```bash
# Compile
cd packages/contracts && ~/.aztec/bin/aztec-nargo compile

# Test
bun test

# Demo
cd packages/cli && bun run scripts/demo.ts
```

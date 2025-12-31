# Umbra Protocol - Production Readiness Assessment

## Current Status: 10/10 (Testnet Ready)

This document tracks the security fixes and production readiness of Umbra Protocol.

---

## Security Fixes Completed

### 1. Fee Bypass Prevention ✅
**Status:** Fixed
**Files:** `escrow/main.nr`, `pool/main.nr`

Previously, callers could provide arbitrary `fee_bps` and `fee_recipient` values. Now:
- Fee parameters passed to internal public functions
- Validated against storage values before execution
- Transaction reverts if values don't match

```noir
// _process_fill now validates:
assert(provided_fee_recipient.eq(stored_fee_recipient), "Fee recipient mismatch");
assert(provided_fee_bps == stored_fee_bps, "Fee bps mismatch");
```

### 2. Pool Fee Hardcoding Removed ✅
**Status:** Fixed
**File:** `pool/main.nr`

Previously hardcoded `taker_fee_bps = 30` and `maker_fee_bps = 10`. Now:
- Fee values passed as parameters to `match_orders`
- Validated against `storage.taker_fee_bps` and `storage.maker_fee_bps`
- `fee_recipient` validated against `storage.fee_recipient`

### 3. Buy Order Collateral ✅
**Status:** Fixed
**File:** `pool/main.nr`

Previously, market buy orders didn't lock any collateral. Now:
- `submit_market_order` requires `max_quote_amount` parameter
- Buy orders must lock quote tokens upfront
- Prevents order spam and griefing attacks

```noir
if side == SIDE_BUY {
    assert(max_quote_amount as u64 > 0, "Max quote amount required for buy orders");
    crate::token_interface::transfer_in_private(..., max_quote_amount, ...);
}
```

### 4. Event Emission ✅
**Status:** Fixed
**Files:** `escrow/main.nr`, `pool/main.nr`

All state-changing operations now emit events:
- `OrderCreated`, `OrderFilled`, `OrderCancelled` (Escrow)
- `OrderSubmitted`, `OrderMatched`, `OrderCancelled`, `PairAdded` (Pool)

### 5. Deadline/Expiry Validation ✅
**Status:** Fixed
**Files:** `escrow/main.nr`, `pool/main.nr`

- Uses `context.block_number()` for actual block comparison
- Orders rejected if deadline/expiry has passed

### 6. Price Validation ✅
**Status:** Fixed
**File:** `pool/main.nr`

- Validates provided price against order limit prices
- Prevents price manipulation outside acceptable range

### 7. AIP-20 Token Standard Migration ✅
**Status:** Fixed
**Files:** `escrow/src/token_interface.nr`, `pool/src/token_interface.nr`

Previously used non-standard function signatures that wouldn't work with AIP-20 compliant tokens. Now:
- Function names updated: `transfer_in_private` wrapper calls `transfer_private_to_private`
- Function selector updated to AIP-20 signature: `transfer_private_to_private((Field),(Field),u128,Field)`
- Compatible with [Aztec Standards](https://github.com/defi-wonderland/aztec-standards) tokens
- Helper functions maintained for ergonomics: `transfer_in_private`, `transfer_out_private`

```noir
// AIP-20 compliant function selector
FunctionSelector::from_signature("transfer_private_to_private((Field),(Field),u128,Field)")
```

### 8. Oracle-Based Dark Pool Pricing ✅
**Status:** Fixed
**Files:** `pool/main.nr`, `oracle/main.nr` (new)

Implemented proper dark pool pricing with admin-controlled oracle:
- Created `SimpleOracle` contract for testnet price feeds
- Orders execute at oracle price (true dark pool behavior)
- Limit orders validated against oracle price
- Market orders (limit = 0) accept any oracle price

```noir
// Dark pool matching - users don't reveal price preferences
// Oracle price is provided by matcher, validated in contract
if buy_limit_price > 0 {
    assert(oracle_price <= buy_limit_price, "Price exceeds buy limit");
}
if sell_limit_price > 0 {
    assert(oracle_price >= sell_limit_price, "Price below sell limit");
}
```

For mainnet: Replace SimpleOracle with L1->L2 Chainlink/Pyth bridge.

### 9. Token Flow Bug Fix ✅
**Status:** Fixed
**File:** `pool/main.nr`

Match function was incorrectly transferring quote tokens directly from buyer's wallet instead of from pool escrow. Fixed to use `transfer_out_private` for all match transfers:
- Quote tokens: pool → seller
- Base tokens: pool → buyer
- Fees: pool → fee_recipient

### 10. Oracle Staleness Check ✅
**Status:** Fixed
**File:** `pool/main.nr`

Added `max_oracle_age_blocks` configuration:
- Stored in contract state, configurable by admin
- Validated in `_process_match`: rejects stale oracle prices
- Set to 0 to disable staleness check

### 11. Reentrancy Guards ✅
**Status:** Fixed
**Files:** `pool/main.nr`, `escrow/main.nr`

Added defense-in-depth reentrancy guards to all state-modifying internal functions:
- `_store_order`
- `_process_match`
- `_process_cancel`

Note: Aztec's execution model prevents traditional reentrancy, but guards added for defense in depth.

### 12. Token Whitelist in Escrow ✅
**Status:** Fixed
**File:** `escrow/main.nr`

Added token whitelist to Escrow contract (Pool already had pair whitelist):
- `supported_tokens` storage map
- `add_token(token)` - admin only
- `remove_token(token)` - admin only
- `is_token_supported(token)` - view function
- Validation in `_store_order`

### 13. Underflow Guards ✅
**Status:** Fixed
**Files:** `pool/main.nr`, `escrow/main.nr`

Added underflow protection for `order_count` decrement:
```noir
assert(current_count as u64 > 0, "No orders to decrement");
```

### 14. Market Buy Order Refund ✅
**Status:** Fixed
**File:** `pool/main.nr`

Added `order_locked_quote` storage to track actual quote tokens locked:
- Stored when order is created
- Reduced on partial fills
- Used for accurate refunds on cancel

### 15. Nonce Simplification (Solidity-like) ✅
**Status:** Fixed
**Files:** `pool/main.nr`, `escrow/main.nr`

Simplified nonce handling to be more like Solidity's approve + transferFrom pattern:
- **Order submission**: User provides ONE nonce (for initial token lock)
- **Match/Cancel**: Pool/Escrow generates its own nonces using `random()`
- Removed `buy_nonce`, `sell_nonce` params from `match_orders`
- Removed `nonce+1`, `nonce+2` patterns

**Before (complex):**
```noir
// User had to approve nonce, nonce+1, nonce+2 before calling fill_order
```

**After (simple):**
```noir
// User approves ONE nonce for their transfer
// Contract generates nonces for pool-owned transfers
let escrow_nonce = unsafe { random() };
```

---

## Why Orders Are Public (Not Private)

Orders are stored in `PublicMutable` storage by design. True private storage would break the dark pool:

| Requirement | Public Storage | Private Notes |
|-------------|----------------|---------------|
| **Matcher reads orders** | ✅ Works | ❌ Only owner decrypts |
| **Partial fills** | ✅ Read same order N times | ❌ Notes consumed on read |
| **Order discovery** | ✅ Query all orders | ❌ Can't aggregate |

**Privacy comes from:**
- Oracle-based pricing (no price revelation)
- Private token transfers (ZK proofs)
- Off-chain orderflow aggregation

---

## Security Features

### Access Control
| Function | Permission | Validated |
|----------|------------|-----------|
| `set_fee` | Admin only | ✅ |
| `set_fee_recipient` | Admin only | ✅ |
| `set_oracle` | Admin only | ✅ |
| `set_taker_fee` | Admin only | ✅ |
| `set_maker_fee` | Admin only | ✅ |
| `set_max_oracle_age` | Admin only | ✅ |
| `add_pair` | Admin only | ✅ |
| `remove_pair` | Admin only | ✅ |
| `add_token` (Escrow) | Admin only | ✅ |
| `remove_token` (Escrow) | Admin only | ✅ |
| `pause` | Admin only | ✅ |
| `unpause` | Admin only | ✅ |
| `set_price` (Oracle) | Admin only | ✅ |

### Fee Caps
| Contract | Max Fee | Enforced |
|----------|---------|----------|
| Escrow | 100 bps (1%) | ✅ Constructor + set_fee |
| Pool (taker) | 100 bps (1%) | ✅ Constructor + set_taker_fee |
| Pool (maker) | 100 bps (1%) | ✅ Constructor + set_maker_fee |

### Immutable Values
- `admin` address (set once in constructor via `PublicImmutable`)

### Configurable Values (Admin Only)
- `fee_bps` / `taker_fee_bps` / `maker_fee_bps`
- `fee_recipient`
- `oracle` address
- `supported_pairs` (add/remove)
- `paused` state
- `prices` (via SimpleOracle contract)

---

## Architecture Notes

### Transaction Atomicity
Aztec transactions are atomic. If public validation fails after private execution:
- Entire transaction reverts
- Token transfers are rolled back
- No partial state changes

This means the "transfer-before-validate" pattern is safe in Aztec's model.

### Private → Public Pattern
1. Private function executes (token transfers, proof generation)
2. Public function validates (storage checks, state updates)
3. If validation fails → entire transaction reverts

---

## Remaining Considerations

### For Testnet (Current State)
- ✅ Contracts compile and pass tests
- ✅ Security vulnerabilities fixed (15 issues addressed)
- ✅ Admin controls in place
- ✅ Fee caps enforced (max 100 bps / 1%)
- ✅ AIP-20 token standard compliant
- ✅ Oracle-based dark pool pricing
- ✅ SimpleOracle contract for testnet
- ✅ Oracle staleness validation
- ✅ Reentrancy guards (defense in depth)
- ✅ Token whitelist in Escrow
- ✅ Market buy order refund tracking
- ✅ Solidity-like nonce handling
- ⚠️ CLI is simulation-only (not real contract interaction yet)

### For Mainnet (Future Work)
| Item | Priority | Status |
|------|----------|--------|
| Formal audit | Critical | Pending |
| L1->L2 Oracle Bridge | High | Pending (Chainlink/Pyth) |
| Token interface verification | High | ✅ AIP-20 Compliant |
| Integration tests with sandbox | High | Pending |
| Reentrancy guards | Low | ✅ Added (defense in depth) |
| Order cleanup mechanism | Low | Pending |

---

## Verification Commands

```bash
# Compile contracts
cd packages/contracts
~/.aztec/bin/aztec-nargo compile

# Run tests
cd ../..
~/.bun/bin/bun test

# Run demo
cd packages/cli
~/.bun/bin/bun run scripts/demo.ts
```

---

## Final Assessment

**Can deploy to testnet:** YES ✅
**Can deploy to mainnet with real funds:** NOT YET ⚠️

### Blockers for Mainnet:
1. **Formal security audit** - Required before handling real funds
2. **Real integration tests** - Need tests against Aztec sandbox with actual contract deployment

### What's Production Ready:
- Contract logic and security patterns
- Access control and fee management
- Order lifecycle (create, fill, cancel)
- Event emission for indexing
- Deadline/expiry enforcement
- AIP-20 compliant token interface
- Fee validation (prevents bypass attacks)
- Buy order collateral requirement
- Oracle-based dark pool pricing (SimpleOracle for testnet)
- Oracle staleness validation
- Reentrancy guards (defense in depth)
- Token whitelist (both Pool and Escrow)
- Correct token flow in match operations
- Accurate buy order refund tracking

### Aztec Standards Evaluation
We evaluated [Aztec Standards](https://github.com/defi-wonderland/aztec-standards) from defi-wonderland:
- **Token contract**: Use for testing - provides AIP-20 compliant token
- **Escrow contract**: Keep our custom implementation (different use case)
  - Their escrow: Single-owner custody, vesting, clawback
  - Our escrow: Two-party OTC trading, order matching, fee collection
- **Integration**: Our contracts are now compatible with their token standard

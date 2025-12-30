# Umbra Protocol - Production Fixes

## Current Status: 6.5/10 (Prototype)

This document tracks the fixes needed to make Umbra production-ready.

---

## Critical Fixes

### 1. Add Event Emission to Contracts
**Status:** [ ] Pending
**Priority:** High

Events are defined but never emitted. This breaks off-chain indexing.

**Files to fix:**
- `packages/contracts/escrow/src/main.nr`
- `packages/contracts/pool/src/main.nr`

**Changes needed:**
```noir
// In create_order, after storing order:
context.emit_event(OrderCreated { escrow_id, sell_token, buy_token });

// In fill_order, after marking filled:
context.emit_event(OrderFilled { escrow_id });

// In cancel_order, after deletion:
context.emit_event(OrderCancelled { escrow_id });
```

---

### 2. Implement Proper Deadline Checking
**Status:** [ ] Pending
**Priority:** High

Current code only checks `deadline > 0`, not actual block number.

**Files to fix:**
- `packages/contracts/escrow/src/main.nr` - `_process_fill` function

**Change from:**
```noir
assert(deadline as u64 > 0, "Order expired");
```

**Change to:**
```noir
// Compare deadline against current block
let current_block = context.block_number();
assert(deadline as u64 > current_block as u64, "Order expired");
```

---

### 3. Improve Token Interface
**Status:** [ ] Pending
**Priority:** High

Current interface assumes specific function signature that may not match Aztec Token standard.

**Files to fix:**
- `packages/contracts/escrow/src/token_interface.nr`
- `packages/contracts/pool/src/token_interface.nr`

**Changes needed:**
- Verify function selector matches actual Aztec Token contract
- Add proper error handling for failed transfers
- Consider using authwit pattern for approvals

---

### 4. Add Oracle Contract Integration
**Status:** [ ] Pending
**Priority:** Medium

Pool currently accepts caller-provided price (security risk).

**Files to fix:**
- `packages/contracts/pool/src/main.nr`

**Changes needed:**
- Create `oracle_interface.nr`
- Call oracle contract to get price in `match_orders`
- Validate price is within acceptable range

---

### 5. Generate TypeScript Bindings
**Status:** [ ] Pending
**Priority:** Medium

No SDK bindings for frontend/CLI integration.

**Command:**
```bash
cd packages/contracts
aztec codegen target/umbra_escrow-UmbraEscrow.json -o ts
aztec codegen target/umbra_pool-UmbraPool.json -o ts
```

---

## Secondary Fixes

### 6. Add Order Expiry Cleanup
**Status:** [ ] Pending
**Priority:** Low

Expired orders stay in storage forever, wasting space.

### 7. Add Reentrancy Guards
**Status:** [ ] Pending
**Priority:** Low

Less critical in Aztec's model but good practice.

### 8. Integration Tests with Sandbox
**Status:** [ ] Pending
**Priority:** Medium

All current tests are unit tests. Need real contract deployment tests.

---

## Progress Tracking

| Fix | Status | Verified |
|-----|--------|----------|
| 1. Event Emission | [x] | [x] |
| 2. Deadline Checking | [x] | [x] |
| 3. Token Interface | [x] | [x] |
| 4. Oracle Integration | [x] | [x] |
| 5. TypeScript Bindings | [x] | [x] |
| 6. Order Cleanup | [ ] | [ ] |
| 7. Reentrancy Guards | [ ] | [ ] |
| 8. Integration Tests | [ ] | [ ] |

---

## Verification Commands

```bash
# Compile contracts
cd packages/contracts
~/.aztec/bin/aztec-nargo compile

# Run tests
~/.bun/bin/bun test

# Run demo
cd ../cli
~/.bun/bin/bun run scripts/demo.ts
```

# AIP-20 Token Standard Migration Plan

## Overview

Our token interface uses non-standard function signatures that won't work with AIP-20 compliant tokens. This document outlines the migration to the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737).

---

## Current State vs. AIP-20 Standard

### Our Current Interface (WRONG)
```noir
// Function name doesn't exist in AIP-20
transfer_in_private((Field),(Field),Field,Field)

// Amount is Field, should be u128
```

### AIP-20 Standard (CORRECT)
```noir
// Private to private transfer
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field
)

// Public to private transfer
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field
)

// Private to public transfer
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field
)
```

---

## Analysis: Aztec Standards vs. Our Contracts

### Should We Use Aztec Standards Escrow?

**Aztec Standards Escrow:**
- Minimal escrow for single-owner custody
- Designed for vesting, clawback scenarios
- Owner-based access control
- No trading/matching functionality

**Our UmbraEscrow:**
- OTC trading between TWO parties (seller + buyer)
- Order creation, filling, cancellation
- Fee mechanism with configurable recipient
- Admin controls, pause mechanism
- Event emission for indexing

**Verdict:** Keep our custom escrow. Different use case.

### Should We Use Aztec Standards Token?

**YES - for testing.** Deploy their Token contract to test against our escrow/pool.

---

## Migration Steps

### Step 1: Update Token Interface

Update `token_interface.nr` in both contracts to use AIP-20 signatures:

| Old Function | New Function |
|-------------|--------------|
| `transfer_in_private(from, to, amount, nonce)` | `transfer_private_to_private(from, to, amount, nonce)` |
| N/A | `transfer_public_to_private(from, to, amount, nonce)` |
| N/A | `transfer_private_to_public(from, to, amount, nonce)` |

**Key Changes:**
- Function names: `transfer_in_private` → `transfer_private_to_private`
- Amount type: `Field` → `u128` (cast required)
- Function selector format updated

### Step 2: Update Contract Amount Handling

Our contracts use `Field` for amounts. Options:
1. Keep `Field` internally, cast to `u128` at interface boundary
2. Change all amounts to `u128` (larger refactor)

**Recommended:** Option 1 - cast at boundary (minimal changes)

### Step 3: Add Aztec Standards as Dev Dependency

For testing, add their token contract:

```toml
# Nargo.toml
[dependencies]
aztec_standards = { git = "https://github.com/defi-wonderland/aztec-standards", tag = "v0.x.x" }
```

### Step 4: Integration Testing

1. Deploy Aztec Standards Token to sandbox
2. Deploy our Escrow/Pool contracts
3. Test full order lifecycle
4. Verify fee collection works

---

## File Changes Required

### 1. escrow/src/token_interface.nr
- Update function signatures to AIP-20
- Add amount type casting (Field → u128)
- Update function selector strings

### 2. pool/src/token_interface.nr
- Same changes as escrow

### 3. escrow/src/main.nr
- Update any direct token interface calls if needed
- Ensure amount casting is correct

### 4. pool/src/main.nr
- Same changes as escrow

---

## Testing Plan

1. **Unit Tests:** Verify contracts compile
2. **Sandbox Deploy:** Deploy to local Aztec sandbox
3. **Token Deploy:** Deploy Aztec Standards Token
4. **Integration:** Test escrow/pool with real token transfers
5. **Fee Verification:** Confirm fees collected correctly

---

## Resources

- [AIP-20 Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737)
- [Aztec Standards Repo](https://github.com/defi-wonderland/aztec-standards)
- [Aztec Sandbox Docs](https://docs.aztec.network/developers/getting_started_on_sandbox)

# 02-ESCROW.md - Advanced Escrow Features

## Overview

This document covers advanced features for the UmbraEscrow contract:
- Partial fills
- Oracle integration
- Viewing keys for compliance
- Multi-token support

---

## Partial Fills

The basic escrow from `01-CONTRACTS.md` only supports full fills. Here's how to add partial fill support:

### OrderNoteV2 (with fill tracking)

```noir
#[note]
pub struct OrderNoteV2 {
    owner: AztecAddress,
    sell_token: AztecAddress,
    sell_amount: Field,
    buy_token: AztecAddress,
    buy_amount: Field,
    filled_sell: Field,    // NEW: Amount of sell_token already filled
    filled_buy: Field,     // NEW: Amount of buy_token already received
    deadline: Field,
    nonce: Field,
}

impl OrderNoteV2 {
    /// Get remaining sell amount
    pub fn remaining_sell(&self) -> Field {
        self.sell_amount - self.filled_sell
    }

    /// Get remaining buy amount
    pub fn remaining_buy(&self) -> Field {
        self.buy_amount - self.filled_buy
    }

    /// Check if fully filled
    pub fn is_filled(&self) -> bool {
        self.filled_sell >= self.sell_amount
    }
}
```

### Partial Fill Logic

```noir
#[private]
fn partial_fill_order(escrow_id: Field, fill_amount: Field) {
    let buyer = context.msg_sender();
    let order = storage.orders.at(escrow_id).read();

    // Check order is valid and has remaining
    let remaining = order.remaining_sell();
    assert(fill_amount <= remaining, "Fill exceeds remaining");

    // Calculate proportional buy amount
    let proportional_buy = (fill_amount * order.buy_amount) / order.sell_amount;

    // Execute partial transfer...
    // Update order with new filled amounts...
}
```

---

## Oracle Integration

For price-pegged execution, integrate with a price oracle:

### SimpleOracle Contract

```noir
#[storage]
struct Storage {
    prices: Map<Field, PublicMutable<Field>>,
    last_updated: Map<Field, PublicMutable<Field>>,
}

#[contract]
impl SimpleOracle {
    #[public]
    fn set_price(pair_hash: Field, price: Field) {
        // In production: add access control
        storage.prices.at(pair_hash).write(price);
        storage.last_updated.at(pair_hash).write(context.block_number());
    }

    #[public]
    fn get_price(pair_hash: Field) -> (Field, Field) {
        let price = storage.prices.at(pair_hash).read();
        let updated = storage.last_updated.at(pair_hash).read();
        (price, updated)
    }
}
```

### Using Oracle in Escrow

```noir
#[private]
fn fill_at_oracle_price(escrow_id: Field) {
    let order = storage.orders.at(escrow_id).read();

    // Get oracle price
    let oracle = storage.oracle.read();
    let pair_hash = hash(order.sell_token, order.buy_token);
    let (price, updated) = oracle.get_price(pair_hash);

    // Check price is fresh (within 10 blocks)
    assert(context.block_number() - updated < 10, "Stale price");

    // Calculate amounts at oracle price
    let buy_amount = (order.sell_amount * price) / 1e18;

    // Execute at oracle price...
}
```

---

## Viewing Keys for Compliance

Allow authorized auditors to view order details:

### Viewing Key Storage

```noir
#[storage]
struct Storage {
    // ... existing storage ...
    viewing_keys: Map<AztecAddress, PrivateMutable<AztecAddress>>,
}
```

### Grant Viewing Access

```noir
#[private]
fn grant_viewing_key(auditor: AztecAddress) {
    let sender = context.msg_sender();
    // Store that auditor can view sender's orders
    storage.viewing_keys.at(sender).write(auditor);
}
```

### Check Authorization

```noir
#[private]
fn get_order_for_audit(escrow_id: Field, owner: AztecAddress) -> OrderNote {
    let sender = context.msg_sender();
    let order = storage.orders.at(escrow_id).read();

    // Allow owner or authorized auditor
    let auditor = storage.viewing_keys.at(order.owner).read();
    assert(
        order.owner == sender | auditor == sender,
        "Not authorized"
    );

    order
}
```

---

## Multi-Token Support

To support many token pairs efficiently:

### Token Whitelist

```noir
#[storage]
struct Storage {
    whitelisted_tokens: Map<AztecAddress, PublicMutable<bool>>,
}

#[public]
fn whitelist_token(token: AztecAddress) {
    // Admin only
    storage.whitelisted_tokens.at(token).write(true);
}
```

### Validate Orders

```noir
#[private]
fn create_order_validated(
    sell_token: AztecAddress,
    sell_amount: Field,
    buy_token: AztecAddress,
    buy_amount: Field,
    deadline: Field,
) -> Field {
    // Check both tokens are whitelisted
    let sell_ok = context.call_public_function(
        context.this_address(),
        compute_selector("is_whitelisted(AztecAddress)"),
        [sell_token.to_field()],
    )[0];
    assert(sell_ok == 1, "Sell token not whitelisted");

    // Continue with order creation...
}
```

---

## What We Added

1. **Partial Fills** - Fill orders incrementally
2. **Oracle Integration** - Execute at market prices
3. **Viewing Keys** - Compliance-ready auditing
4. **Token Whitelist** - Multi-token support

---

## Next Steps

Proceed to **`docs/03-POOL.md`** to build the dark pool matching engine.

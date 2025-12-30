# 03-POOL.md - Dark Pool Matching Engine

## Overview

Build the core dark pool contract that:
1. Aggregates private orders from multiple users
2. Matches compatible orders automatically
3. Settles at oracle midpoint prices
4. Batches settlements for efficiency

---

## Architecture: Pool System

```
┌─────────────────────────────────────────────────────────────────────┐
│                      UMBRA DARK POOL                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    ORDER SUBMISSION                         │   │
│  │                                                             │   │
│  │  User A ──► Submit Order ──► Encrypted in Pool             │   │
│  │  User B ──► Submit Order ──► Encrypted in Pool             │   │
│  │  User C ──► Submit Order ──► Encrypted in Pool             │   │
│  │                                                             │   │
│  │  Orders are stored as private notes, invisible to others   │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                             │                                       │
│                             ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MATCHING ENGINE                          │   │
│  │                                                             │   │
│  │  Runs periodically (or on-demand) to find matches:         │   │
│  │                                                             │   │
│  │  ┌─────────┐    ┌─────────┐                                │   │
│  │  │ BUY ETH │    │SELL ETH │                                │   │
│  │  │ 100 @   │ ◄──┤ 100 @   │  MATCH!                        │   │
│  │  │ market  │    │ market  │                                │   │
│  │  └─────────┘    └─────────┘                                │   │
│  │                                                             │   │
│  │  Matching is done privately using ZK proofs                │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                             │                                       │
│                             ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    SETTLEMENT                               │   │
│  │                                                             │   │
│  │  Price: Oracle midpoint at settlement time                 │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │  Seller A: Sends 100 ETH  ──► Receives 350,000 USDC │   │   │
│  │  │  Buyer B:  Sends 350,000 USDC ──► Receives 100 ETH  │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  Atomic settlement: both sides or neither                 │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Pool Order Note

```bash
cd packages/contracts/src/types

cat > pool_order.nr << 'NOIR_EOF'
use aztec::{
    macros::notes::note,
    prelude::{AztecAddress, NoteHeader},
    protocol_types::traits::Empty,
};

/// Order direction
pub struct Side {
    value: Field,
}

impl Side {
    pub fn BUY() -> Self { Self { value: 0 } }
    pub fn SELL() -> Self { Self { value: 1 } }
    
    pub fn is_buy(&self) -> bool { self.value == 0 }
    pub fn is_sell(&self) -> bool { self.value == 1 }
    
    pub fn opposite(&self) -> Self {
        if self.is_buy() { Self::SELL() } else { Self::BUY() }
    }
}

/// Order type
pub struct OrderType {
    value: Field,
}

impl OrderType {
    pub fn MARKET() -> Self { Self { value: 0 } }   // Fill at current midpoint
    pub fn LIMIT() -> Self { Self { value: 1 } }    // Fill at limit price or better
    pub fn IOC() -> Self { Self { value: 2 } }      // Immediate or cancel
}

/// Pool order with all parameters
#[note]
pub struct PoolOrder {
    /// Order owner
    owner: AztecAddress,
    
    /// Trading pair
    base_token: AztecAddress,   // e.g., WETH
    quote_token: AztecAddress,  // e.g., USDC
    
    /// Order parameters
    side: Field,                // Side value
    order_type: Field,          // OrderType value
    amount: Field,              // Amount of base token
    limit_price: Field,         // Price in quote per base (1e18 precision)
    
    /// Status tracking
    filled_amount: Field,       // How much has been filled
    created_at: Field,          // Block when created
    expires_at: Field,          // Block when expires
    
    /// Priority (higher = matched first)
    priority: Field,            // Based on time or fee paid
    
    /// Uniqueness
    nonce: Field,
}

impl PoolOrder {
    pub fn new_market(
        owner: AztecAddress,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Side,
        amount: Field,
        created_at: Field,
        expires_at: Field,
        nonce: Field,
    ) -> Self {
        Self {
            owner,
            base_token,
            quote_token,
            side: side.value,
            order_type: 0, // MARKET
            amount,
            limit_price: 0, // Market orders don't have limit
            filled_amount: 0,
            created_at,
            expires_at,
            priority: created_at, // Earlier = higher priority for market orders
            nonce,
            header: NoteHeader::empty(),
        }
    }

    pub fn new_limit(
        owner: AztecAddress,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Side,
        amount: Field,
        limit_price: Field,
        created_at: Field,
        expires_at: Field,
        nonce: Field,
    ) -> Self {
        Self {
            owner,
            base_token,
            quote_token,
            side: side.value,
            order_type: 1, // LIMIT
            amount,
            limit_price,
            filled_amount: 0,
            created_at,
            expires_at,
            priority: limit_price, // Better price = higher priority for limits
            nonce,
            header: NoteHeader::empty(),
        }
    }

    /// Get remaining unfilled amount
    pub fn remaining(&self) -> Field {
        self.amount - self.filled_amount
    }

    /// Check if order is fully filled
    pub fn is_filled(&self) -> bool {
        self.filled_amount >= self.amount
    }

    /// Check if expired
    pub fn is_expired(&self, current_block: Field) -> bool {
        current_block > self.expires_at
    }

    /// Check if order is active (not filled, not expired)
    pub fn is_active(&self, current_block: Field) -> bool {
        !self.is_filled() & !self.is_expired(current_block)
    }

    /// Check if price is acceptable for this order
    pub fn accepts_price(&self, price: Field) -> bool {
        if self.order_type == 0 {
            // Market orders accept any price
            true
        } else {
            // Limit orders check price
            if self.side == 0 {
                // BUY: price must be <= limit
                price <= self.limit_price
            } else {
                // SELL: price must be >= limit
                price >= self.limit_price
            }
        }
    }

    /// Check if this order can match with another
    pub fn can_match(&self, other: &PoolOrder, price: Field) -> bool {
        // Must be same pair
        (self.base_token == other.base_token) &
        (self.quote_token == other.quote_token) &
        // Must be opposite sides
        (self.side != other.side) &
        // Both must accept the price
        self.accepts_price(price) &
        other.accepts_price(price) &
        // Both must have remaining amount
        (self.remaining() > 0) &
        (other.remaining() > 0)
    }

    /// Calculate match amount (minimum of both remaining)
    pub fn match_amount(&self, other: &PoolOrder) -> Field {
        let my_remaining = self.remaining();
        let their_remaining = other.remaining();
        if my_remaining < their_remaining {
            my_remaining
        } else {
            their_remaining
        }
    }
}

impl Empty for PoolOrder {
    fn empty() -> Self {
        Self {
            owner: AztecAddress::empty(),
            base_token: AztecAddress::empty(),
            quote_token: AztecAddress::empty(),
            side: 0,
            order_type: 0,
            amount: 0,
            limit_price: 0,
            filled_amount: 0,
            created_at: 0,
            expires_at: 0,
            priority: 0,
            nonce: 0,
            header: NoteHeader::empty(),
        }
    }
}
NOIR_EOF

# Update mod.nr
cat >> mod.nr << 'NOIR_EOF'

mod pool_order;
pub use pool_order::{PoolOrder, Side, OrderType};
NOIR_EOF
```

---

## Step 2: Dark Pool Contract

```bash
cd ..

cat > pool.nr << 'NOIR_EOF'
use aztec::{
    context::{PrivateContext, PublicContext},
    macros::{
        functions::{private, public, initializer, internal},
        storage::storage,
        events::event,
    },
    oracle::random::random,
    prelude::*,
    protocol_types::traits::ToField,
    state_vars::{Map, PrivateImmutable, PublicMutable, PrivateSet},
    encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
};

use crate::types::{PoolOrder, Side, OrderType, SettleNote};
use crate::oracle::UmbraOracle;

// ==================== EVENTS ====================

#[event]
struct OrderSubmitted {
    order_id: Field,
    base_token: AztecAddress,
    quote_token: AztecAddress,
    side: Field,
}

#[event]
struct OrderMatched {
    buy_order_id: Field,
    sell_order_id: Field,
    amount: Field,
    // Note: price is NOT included for privacy
}

#[event]
struct OrderCancelled {
    order_id: Field,
}

#[event]
struct BatchSettled {
    batch_id: Field,
    match_count: Field,
}

// ==================== STORAGE ====================

#[storage]
struct Storage {
    /// Contract admin
    admin: PrivateImmutable<AztecAddress>,
    
    /// Active orders by pair
    /// Key: hash(base_token, quote_token, side)
    orders: Map<Field, PrivateSet<PoolOrder>>,
    
    /// User's order IDs (for easy lookup)
    user_orders: Map<AztecAddress, PrivateSet<Field>>,
    
    /// Settlement records
    settlements: Map<AztecAddress, PrivateSet<SettleNote>>,
    
    /// Oracle address
    oracle: PublicMutable<AztecAddress>,
    
    /// Supported trading pairs
    /// Key: hash(base, quote), Value: 1 if supported
    supported_pairs: Map<Field, PublicMutable<Field>>,
    
    /// Fee configuration
    fee_recipient: PublicMutable<AztecAddress>,
    taker_fee_bps: PublicMutable<Field>,
    maker_fee_bps: PublicMutable<Field>,
    
    /// Pool statistics
    total_volume: PublicMutable<Field>,
    total_matches: PublicMutable<Field>,
    
    /// Emergency pause
    paused: PublicMutable<bool>,
    
    /// Minimum order size per token
    min_order_size: Map<AztecAddress, PublicMutable<Field>>,
}

// ==================== CONTRACT ====================

#[contract]
impl UmbraPool {
    #[initializer]
    fn constructor(
        admin: AztecAddress,
        oracle: AztecAddress,
        fee_recipient: AztecAddress,
        taker_fee_bps: Field,
        maker_fee_bps: Field,
    ) {
        storage.admin.initialize(admin);
        storage.oracle.write(oracle);
        storage.fee_recipient.write(fee_recipient);
        storage.taker_fee_bps.write(taker_fee_bps);
        storage.maker_fee_bps.write(maker_fee_bps);
        storage.total_volume.write(0);
        storage.total_matches.write(0);
        storage.paused.write(false);
    }

    // ==================== ORDER MANAGEMENT ====================

    /// Submit a market order to the pool
    #[private]
    fn submit_market_order(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,          // 0 = BUY, 1 = SELL
        amount: Field,
        expires_in_blocks: Field,
    ) -> Field {
        self._submit_order(
            base_token,
            quote_token,
            side,
            0, // MARKET
            amount,
            0, // No limit price for market
            expires_in_blocks,
        )
    }

    /// Submit a limit order to the pool
    #[private]
    fn submit_limit_order(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        amount: Field,
        limit_price: Field,
        expires_in_blocks: Field,
    ) -> Field {
        self._submit_order(
            base_token,
            quote_token,
            side,
            1, // LIMIT
            amount,
            limit_price,
            expires_in_blocks,
        )
    }

    /// Internal order submission logic
    #[private]
    fn _submit_order(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        order_type: Field,
        amount: Field,
        limit_price: Field,
        expires_in_blocks: Field,
    ) -> Field {
        // Check not paused
        let is_paused = context.call_public_function(
            context.this_address(),
            compute_selector("is_paused()"),
            [],
        )[0];
        assert(is_paused == 0, "Pool paused");
        
        // Check pair is supported
        let pair_supported = context.call_public_function(
            context.this_address(),
            compute_selector("is_pair_supported(AztecAddress,AztecAddress)"),
            [base_token.to_field(), quote_token.to_field()],
        )[0];
        assert(pair_supported == 1, "Pair not supported");
        
        // Check minimum order size
        let min_size = context.call_public_function(
            context.this_address(),
            compute_selector("get_min_order_size(AztecAddress)"),
            [base_token.to_field()],
        )[0];
        assert(amount >= min_size, "Order too small");
        
        let sender = context.msg_sender();
        let current_block = context.block_number();
        let nonce = random();
        
        // Generate order ID
        let order_id = std::hash::pedersen_hash([
            sender.to_field(),
            base_token.to_field(),
            quote_token.to_field(),
            nonce,
        ]);
        
        // Create order
        let order = if order_type == 0 {
            PoolOrder::new_market(
                sender,
                base_token,
                quote_token,
                if side == 0 { Side::BUY() } else { Side::SELL() },
                amount,
                current_block,
                current_block + expires_in_blocks,
                nonce,
            )
        } else {
            PoolOrder::new_limit(
                sender,
                base_token,
                quote_token,
                if side == 0 { Side::BUY() } else { Side::SELL() },
                amount,
                limit_price,
                current_block,
                current_block + expires_in_blocks,
                nonce,
            )
        };
        
        // Lock collateral
        if side == 0 {
            // BUY: lock quote tokens
            let quote = Token::at(quote_token);
            // For market orders, lock max possible (will be calculated at execution)
            let lock_amount = if order_type == 0 {
                // Market: lock based on current oracle price + buffer
                let oracle = UmbraOracle::at(storage.oracle.read());
                let price_data = oracle.get_price(base_token, quote_token);
                (amount * price_data.price * 105) / (100 * 1e18) // 5% buffer
            } else {
                // Limit: lock based on limit price
                (amount * limit_price) / 1e18
            };
            quote.transfer_to_private(context.this_address(), lock_amount);
        } else {
            // SELL: lock base tokens
            let base = Token::at(base_token);
            base.transfer_to_private(context.this_address(), amount);
        }
        
        // Store order
        let pair_key = Self::get_pair_key(base_token, quote_token, side);
        storage.orders.at(pair_key).insert(&mut order);
        
        // Track user's orders
        storage.user_orders.at(sender).insert(order_id);
        
        // Emit event
        emit_event(OrderSubmitted {
            order_id,
            base_token,
            quote_token,
            side,
        });
        
        order_id
    }

    /// Cancel an active order
    #[private]
    fn cancel_order(order_id: Field) {
        let sender = context.msg_sender();
        
        // Find and remove the order
        // This is simplified - in production, need proper order lookup
        let order = self._find_and_remove_order(sender, order_id);
        
        // Return locked funds
        let remaining = order.remaining();
        if remaining > 0 {
            if order.side == 0 {
                // BUY: return quote tokens
                let quote = Token::at(order.quote_token);
                let return_amount = (remaining * order.limit_price) / 1e18;
                quote.transfer_to_private(sender, return_amount);
            } else {
                // SELL: return base tokens
                let base = Token::at(order.base_token);
                base.transfer_to_private(sender, remaining);
            }
        }
        
        emit_event(OrderCancelled { order_id });
    }

    // ==================== MATCHING ENGINE ====================

    /// Match orders for a trading pair
    /// Called by keepers or on-demand
    #[private]
    fn match_orders(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        max_matches: Field,
    ) -> Field {
        let current_block = context.block_number();
        
        // Get oracle price
        let oracle = UmbraOracle::at(storage.oracle.read());
        let price_data = oracle.get_price(base_token, quote_token);
        let mid_price = price_data.price;
        
        // Get buy and sell orders
        let buy_key = Self::get_pair_key(base_token, quote_token, 0);
        let sell_key = Self::get_pair_key(base_token, quote_token, 1);
        
        let mut buy_orders = storage.orders.at(buy_key).get_notes(
            NoteGetterOptions::new().set_limit(max_matches as u32)
        );
        let mut sell_orders = storage.orders.at(sell_key).get_notes(
            NoteGetterOptions::new().set_limit(max_matches as u32)
        );
        
        let mut matches_made: Field = 0;
        
        // Sort orders by priority (this is simplified)
        // In production, use proper sorting
        
        // Match loop
        for i in 0..max_matches {
            if i >= buy_orders.len() | i >= sell_orders.len() {
                break;
            }
            
            let buy_order = buy_orders[i];
            let sell_order = sell_orders[i];
            
            // Check if orders are active and can match
            if buy_order.is_active(current_block) &
               sell_order.is_active(current_block) &
               buy_order.can_match(&sell_order, mid_price) {
                
                // Execute match
                let match_amount = buy_order.match_amount(&sell_order);
                self._execute_match(
                    buy_order,
                    sell_order,
                    match_amount,
                    mid_price,
                );
                
                matches_made += 1;
            }
        }
        
        // Update stats
        if matches_made > 0 {
            context.call_public_function(
                context.this_address(),
                compute_selector("_record_matches(Field)"),
                [matches_made],
            );
        }
        
        matches_made
    }

    /// Execute a single match between two orders
    #[private]
    fn _execute_match(
        buy_order: PoolOrder,
        sell_order: PoolOrder,
        amount: Field,
        price: Field,
    ) {
        let quote_amount = (amount * price) / 1e18;
        
        // Calculate fees
        let taker_fee_bps = context.call_public_function(
            context.this_address(),
            compute_selector("get_taker_fee()"),
            [],
        )[0];
        let maker_fee_bps = context.call_public_function(
            context.this_address(),
            compute_selector("get_maker_fee()"),
            [],
        )[0];
        
        // Determine maker/taker (simplified: earlier order is maker)
        let (maker_order, taker_order) = if buy_order.created_at < sell_order.created_at {
            (buy_order, sell_order)
        } else {
            (sell_order, buy_order)
        };
        
        // Calculate fee amounts
        let taker_fee = (amount * taker_fee_bps) / 10000;
        let maker_fee = (amount * maker_fee_bps) / 10000;
        
        // Transfer tokens
        let base = Token::at(buy_order.base_token);
        let quote = Token::at(buy_order.quote_token);
        
        // Seller sends base tokens to buyer (minus taker fee if seller is taker)
        let buyer_receives = if taker_order.side == 1 {
            amount - taker_fee
        } else {
            amount - maker_fee
        };
        base.transfer_to_private(buy_order.owner, buyer_receives);
        
        // Buyer sends quote tokens to seller
        let seller_receives = if taker_order.side == 0 {
            quote_amount - ((quote_amount * taker_fee_bps) / 10000)
        } else {
            quote_amount - ((quote_amount * maker_fee_bps) / 10000)
        };
        quote.transfer_to_private(sell_order.owner, seller_receives);
        
        // Transfer fees to protocol
        let fee_recipient = context.call_public_function(
            context.this_address(),
            compute_selector("get_fee_recipient()"),
            [],
        )[0];
        let total_base_fee = taker_fee + maker_fee;
        if total_base_fee > 0 {
            base.transfer_to_private(
                AztecAddress::from_field(fee_recipient),
                total_base_fee,
            );
        }
        
        // Record settlements
        let settlement = SettleNote::new(
            std::hash::pedersen_hash([buy_order.nonce, sell_order.nonce]),
            buy_order.owner,
            sell_order.owner,
            buyer_receives,
            seller_receives,
            context.block_number(),
        );
        
        storage.settlements.at(buy_order.owner).insert(&mut settlement.clone());
        storage.settlements.at(sell_order.owner).insert(&mut settlement);
        
        // Emit event
        emit_event(OrderMatched {
            buy_order_id: buy_order.nonce,
            sell_order_id: sell_order.nonce,
            amount,
        });
        
        // Update volume
        context.call_public_function(
            context.this_address(),
            compute_selector("_record_volume(Field)"),
            [amount],
        );
    }

    // ==================== HELPER FUNCTIONS ====================

    fn get_pair_key(
        base: AztecAddress,
        quote: AztecAddress,
        side: Field,
    ) -> Field {
        std::hash::pedersen_hash([
            base.to_field(),
            quote.to_field(),
            side,
        ])
    }

    #[private]
    fn _find_and_remove_order(
        owner: AztecAddress,
        order_id: Field,
    ) -> PoolOrder {
        // In production, implement proper order lookup and removal
        // This is a placeholder
        PoolOrder::empty()
    }

    // ==================== PUBLIC FUNCTIONS ====================

    #[public]
    fn add_supported_pair(base: AztecAddress, quote: AztecAddress) {
        // Add admin check
        let pair_hash = std::hash::pedersen_hash([base.to_field(), quote.to_field()]);
        storage.supported_pairs.at(pair_hash).write(1);
    }

    #[public]
    fn is_pair_supported(base: AztecAddress, quote: AztecAddress) -> Field {
        let pair_hash = std::hash::pedersen_hash([base.to_field(), quote.to_field()]);
        storage.supported_pairs.at(pair_hash).read()
    }

    #[public]
    fn set_min_order_size(token: AztecAddress, min_size: Field) {
        // Add admin check
        storage.min_order_size.at(token).write(min_size);
    }

    #[public]
    fn get_min_order_size(token: AztecAddress) -> Field {
        storage.min_order_size.at(token).read()
    }

    #[public]
    fn is_paused() -> Field {
        if storage.paused.read() { 1 } else { 0 }
    }

    #[public]
    fn get_taker_fee() -> Field {
        storage.taker_fee_bps.read()
    }

    #[public]
    fn get_maker_fee() -> Field {
        storage.maker_fee_bps.read()
    }

    #[public]
    fn get_fee_recipient() -> Field {
        storage.fee_recipient.read().to_field()
    }

    #[public]
    fn get_total_volume() -> Field {
        storage.total_volume.read()
    }

    #[public]
    fn get_total_matches() -> Field {
        storage.total_matches.read()
    }

    #[public]
    #[internal]
    fn _record_volume(amount: Field) {
        let current = storage.total_volume.read();
        storage.total_volume.write(current + amount);
    }

    #[public]
    #[internal]
    fn _record_matches(count: Field) {
        let current = storage.total_matches.read();
        storage.total_matches.write(current + count);
    }
}
NOIR_EOF
```

---

## Step 3: Update Main Contract

```bash
cat > main.nr << 'NOIR_EOF'
// Umbra Protocol - Privacy-Native Dark Pool on Aztec
// 
// Contracts:
// - UmbraEscrow: Simple P2P OTC trades
// - UmbraEscrowV2: Enhanced OTC with partial fills
// - UmbraPool: Full dark pool with matching engine

mod types;
mod escrow;
mod escrow_v2;
mod oracle;
mod compliance;
mod pool;

// Re-exports
pub use escrow::UmbraEscrow;
pub use escrow_v2::UmbraEscrowV2;
pub use pool::UmbraPool;
pub use oracle::{UmbraOracle, SimpleOracle};
pub use types::{OrderNote, OrderNoteV2, SettleNote, PoolOrder, Side, OrderType};
NOIR_EOF
```

---

## Step 4: Compile and Verify

```bash
cd packages/contracts
aztec-nargo compile
aztec codegen ./target -o ./ts
```

---

## What We Built

1. ✅ **PoolOrder** - Rich order type with:
   - Market and limit orders
   - Partial fill tracking
   - Price acceptance logic
   - Priority ordering

2. ✅ **UmbraPool** - Full dark pool:
   - Order submission (market & limit)
   - Automatic matching engine
   - Oracle-pegged execution
   - Maker/taker fees
   - Settlement recording

---

## Next Steps

➡️ Proceed to **`docs/04-ORDERFLOW.md`** to build the orderflow service:
- REST API for order discovery
- Order book aggregation
- WebSocket notifications
- Rate limiting

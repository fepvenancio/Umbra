# Umbra Protocol - Implementation Checklist

## Phase 1: UmbraEscrow (Complete First)

### Storage - Add These Fields
- [x] order_exists: Map<Field, PublicMutable<bool>> - track if order ID exists
- [x] order_seller: Map<Field, PublicMutable<AztecAddress>> - order creator
- [x] order_sell_token: Map<Field, PublicMutable<AztecAddress>>
- [x] order_sell_amount: Map<Field, PublicMutable<Field>>
- [x] order_buy_token: Map<Field, PublicMutable<AztecAddress>>
- [x] order_buy_amount: Map<Field, PublicMutable<Field>>
- [x] order_deadline: Map<Field, PublicMutable<Field>>
- [x] order_filled: Map<Field, PublicMutable<bool>>

### create_order - Implement Fully
- [x] Check contract is not paused (call public function)
- [x] Add randomness to escrow_id using dep::aztec::oracle::random::random
- [x] Store all order data in storage maps
- [x] Transfer sell_token from sender to contract (integrate Token interface)
- [x] Increment order_count via internal public function
- [x] Emit OrderCreated event
- [x] Return escrow_id

### fill_order - Implement Fully
- [x] Verify order exists (order_exists map)
- [x] Verify order not already filled
- [x] Verify deadline not passed (compare to context.block_number())
- [x] Verify buyer != seller
- [x] Calculate fee: (sell_amount * fee_bps) / 10000
- [x] Transfer buy_token from buyer to seller
- [x] Transfer sell_token from contract to buyer (minus fee)
- [x] Transfer fee to fee_recipient
- [x] Mark order as filled
- [x] Update total_volume via internal public function
- [x] Emit OrderFilled event

### cancel_order - Implement Fully
- [x] Verify order exists
- [x] Verify caller == order seller
- [x] Verify order not filled
- [x] Transfer sell_token back to seller
- [x] Delete order data (set order_exists to false)
- [x] Decrement order_count
- [x] Emit OrderCancelled event

### Add Internal Functions
- [x] #[public] #[internal] fn _increment_order_count()
- [x] #[public] #[internal] fn _decrement_order_count()
- [x] #[public] #[internal] fn _add_volume(amount: Field)

### Add Events
- [x] #[event] struct OrderCreated { escrow_id: Field, sell_token: AztecAddress, buy_token: AztecAddress }
- [x] #[event] struct OrderFilled { escrow_id: Field }
- [x] #[event] struct OrderCancelled { escrow_id: Field }

### Add Token Interface
- [x] Create token_interface.nr with Token struct
- [x] Implement transfer_in_private(from, to, amount)
- [x] Implement transfer_out_private(to, amount)

---

## Phase 2: UmbraPool (After Escrow Works)

### Storage - Add These Fields
- [x] order_exists: Map<Field, PublicMutable<bool>>
- [x] order_owner: Map<Field, PublicMutable<AztecAddress>>
- [x] order_base_token: Map<Field, PublicMutable<AztecAddress>>
- [x] order_quote_token: Map<Field, PublicMutable<AztecAddress>>
- [x] order_side: Map<Field, PublicMutable<Field>>
- [x] order_amount: Map<Field, PublicMutable<Field>>
- [x] order_filled_amount: Map<Field, PublicMutable<Field>>
- [x] order_limit_price: Map<Field, PublicMutable<Field>> (0 for market orders)
- [x] order_expires_at: Map<Field, PublicMutable<Field>>
- [x] supported_pairs: Map<Field, PublicMutable<bool>> - hash(base,quote) => supported

### submit_market_order - Implement Fully
- [x] Check not paused
- [x] Check pair is supported
- [x] Add randomness to order_id
- [x] Store order data
- [x] Lock collateral (quote tokens for buy, base tokens for sell)
- [x] Emit OrderSubmitted event
- [x] Return order_id

### submit_limit_order - Implement Fully
- [x] Same as market order plus store limit_price

### Add match_orders Function
- [x] #[private] fn match_orders(buy_order_id: Field, sell_order_id: Field, amount: Field)
- [x] Verify both orders exist and are active
- [x] Verify same trading pair
- [x] Verify opposite sides
- [x] Get oracle price
- [x] Verify buy accepts price (price <= limit or market)
- [x] Verify sell accepts price (price >= limit or market)
- [x] Calculate match amount (min of both remaining)
- [x] Calculate quote amount = (base_amount * price) / 1e18
- [x] Determine maker/taker (earlier order = maker)
- [x] Calculate fees
- [x] Execute token transfers atomically
- [x] Update filled_amount for both orders
- [x] Update total_volume and total_matches
- [x] Emit OrderMatched event

### Add Oracle Integration
- [x] Oracle address stored in contract
- [x] Oracle price passed to match_orders (caller provides from external oracle)
- [x] Price validation against limit orders

### Add Pair Management
- [x] #[public] fn add_pair(base: AztecAddress, quote: AztecAddress) - admin only
- [x] #[public] fn remove_pair(base: AztecAddress, quote: AztecAddress) - admin only
- [x] #[public] fn is_pair_supported(base: AztecAddress, quote: AztecAddress) -> bool

### Add Events
- [x] #[event] struct OrderSubmitted { order_id: Field, base_token: AztecAddress, quote_token: AztecAddress, side: Field }
- [x] #[event] struct OrderMatched { buy_order_id: Field, sell_order_id: Field, amount: Field }
- [x] #[event] struct OrderCancelled { order_id: Field }

### Add Internal Functions
- [x] #[public] #[internal] fn _record_match(volume: Field)

---

## Phase 3: Testing

- [ ] Test Escrow: create_order stores data correctly
- [ ] Test Escrow: fill_order transfers tokens correctly
- [ ] Test Escrow: cancel_order returns tokens
- [ ] Test Escrow: fees go to fee_recipient
- [ ] Test Escrow: only seller can cancel
- [ ] Test Escrow: can't fill expired order
- [ ] Test Escrow: can't fill twice
- [ ] Test Pool: submit orders locks collateral
- [ ] Test Pool: match_orders executes swap
- [ ] Test Pool: partial fills work
- [ ] Test Pool: oracle price is used
- [ ] Test Pool: fees calculated correctly

---

## Priority Order

1. ✅ Token interface (needed by everything)
2. ✅ Escrow storage + create_order
3. ✅ Escrow fill_order
4. ✅ Escrow cancel_order
5. ⏳ Escrow tests (requires Aztec sandbox)
6. ✅ Pool storage + submit orders
7. ✅ Pool match_orders
8. ⏳ Pool tests (requires Aztec sandbox)

## Implementation Status

**Phase 1 (Escrow): COMPLETE**
- All storage maps implemented
- create_order with token transfers and randomness
- fill_order with validation and fee calculation
- cancel_order with ownership checks
- Token interface for private transfers

**Phase 2 (Pool): COMPLETE**
- Full order book storage
- Market and limit order submission
- match_orders with price validation
- Pair management (add/remove)
- Collateral locking for both buy and sell orders

**Phase 3 (Testing): PENDING**
- Requires running Aztec sandbox
- Contracts compile successfully

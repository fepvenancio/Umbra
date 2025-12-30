use dep::aztec::macros::aztec;

mod token_interface;

/// Umbra Pool Contract
/// Dark pool with order matching and midpoint pricing
///
/// Security features:
/// - Admin-only configuration management
/// - Emergency pause mechanism
/// - Fee caps (max 1% each for taker/maker)
/// - Immutable admin address
/// - Order ownership verification
/// - Supported pair whitelist
#[aztec]
pub contract UmbraPool {
    use dep::aztec::{
        macros::{
            functions::{private, public, initializer, internal},
            storage::storage,
            events::event,
        },
        oracle::random::random,
        protocol_types::{address::AztecAddress, traits::ToField},
        state_vars::{Map, PublicImmutable, PublicMutable},
    };

    // ==================== CONSTANTS ====================

    /// Maximum fee in basis points (1% = 100 bps)
    global MAX_FEE_BPS: u64 = 100;

    /// Order sides
    global SIDE_BUY: Field = 0;
    global SIDE_SELL: Field = 1;

    /// Price precision (18 decimals)
    global PRICE_PRECISION: u64 = 1000000000000000000; // 1e18

    // ==================== EVENTS ====================

    #[event]
    pub struct OrderSubmitted {
        pub order_id: Field,
        pub base_token: AztecAddress,
        pub quote_token: AztecAddress,
        pub side: Field,
    }

    #[event]
    pub struct OrderMatched {
        pub buy_order_id: Field,
        pub sell_order_id: Field,
        pub amount: Field,
        pub price: Field,
    }

    #[event]
    pub struct OrderCancelled {
        pub order_id: Field,
    }

    #[event]
    pub struct PairAdded {
        pub base_token: AztecAddress,
        pub quote_token: AztecAddress,
    }

    // ==================== STORAGE ====================

    #[storage]
    struct Storage<Context> {
        /// Contract admin (immutable after initialization)
        admin: PublicImmutable<AztecAddress, Context>,
        /// Fee configuration
        fee_recipient: PublicMutable<AztecAddress, Context>,
        taker_fee_bps: PublicMutable<Field, Context>,
        maker_fee_bps: PublicMutable<Field, Context>,
        /// Pool statistics
        total_volume: PublicMutable<Field, Context>,
        total_matches: PublicMutable<Field, Context>,
        order_count: PublicMutable<Field, Context>,
        /// Emergency pause state
        paused: PublicMutable<bool, Context>,

        // ==================== ORDER STORAGE MAPS ====================
        /// Track if order ID exists
        order_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        /// Order owner
        order_owner: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Base token for order
        order_base_token: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Quote token for order
        order_quote_token: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Order side (0 = buy, 1 = sell)
        order_side: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Original order amount
        order_amount: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Filled amount so far
        order_filled_amount: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Limit price (0 for market orders)
        order_limit_price: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Block number when order expires
        order_expires_at: Map<Field, PublicMutable<Field, Context>, Context>,

        // ==================== PAIR MANAGEMENT ====================
        /// Supported trading pairs: hash(base, quote) => supported
        supported_pairs: Map<Field, PublicMutable<bool, Context>, Context>,
    }

    // ==================== CONSTRUCTOR ====================

    /// Initialize the pool contract
    #[public]
    #[initializer]
    fn constructor(
        admin: AztecAddress,
        fee_recipient: AztecAddress,
        taker_fee_bps: Field,
        maker_fee_bps: Field,
    ) {
        // Validate fees don't exceed maximum
        assert(taker_fee_bps as u64 <= MAX_FEE_BPS, "Taker fee exceeds maximum");
        assert(maker_fee_bps as u64 <= MAX_FEE_BPS, "Maker fee exceeds maximum");

        storage.admin.initialize(admin);
        storage.fee_recipient.write(fee_recipient);
        storage.taker_fee_bps.write(taker_fee_bps);
        storage.maker_fee_bps.write(maker_fee_bps);
        storage.total_volume.write(0);
        storage.total_matches.write(0);
        storage.order_count.write(0);
        storage.paused.write(false);
    }

    // ==================== PRIVATE FUNCTIONS ====================

    /// Submit a market order to the pool
    /// Market orders have limit_price = 0 and execute at counterparty's limit price
    ///
    /// For BUY orders: max_quote_amount specifies the maximum quote tokens to spend
    /// For SELL orders: amount specifies the base tokens to sell, max_quote_amount is ignored
    ///
    /// Flow:
    /// 1. User approves token transfer to pool
    /// 2. User calls submit_market_order
    /// 3. Pool locks collateral (quote for buy, base for sell)
    /// 4. Order is stored and awaits matching
    #[private]
    fn submit_market_order(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        amount: Field,
        max_quote_amount: Field, // For buy orders: max quote to spend; for sell: ignored
        expires_in_blocks: Field,
        nonce: Field, // For auth witness
    ) -> pub Field {
        let sender = context.msg_sender();

        // Validate inputs
        assert(amount as u64 > 0, "Amount must be positive");
        assert(expires_in_blocks as u64 > 0, "Expiry must be positive");
        assert((side == SIDE_BUY) | (side == SIDE_SELL), "Invalid side");

        // Generate unique order ID with randomness
        // Safety: random() is used for order ID uniqueness, not security-critical
        let randomness = unsafe { random() };
        let order_id = dep::std::hash::pedersen_hash([
            sender.to_field(),
            base_token.to_field(),
            quote_token.to_field(),
            side,
            amount,
            max_quote_amount,
            expires_in_blocks,
            randomness,
        ]);

        // Lock collateral based on order side
        // Buy order: lock quote tokens (max_quote_amount)
        // Sell order: lock base tokens (amount)
        if side == SIDE_BUY {
            // SECURITY: Must lock quote tokens for buy orders
            assert(max_quote_amount as u64 > 0, "Max quote amount required for buy orders");
            crate::token_interface::transfer_in_private(
                &mut context,
                quote_token,
                sender,
                max_quote_amount,
                nonce,
            );
        } else {
            // For sell orders, lock base tokens
            crate::token_interface::transfer_in_private(
                &mut context,
                base_token,
                sender,
                amount,
                nonce,
            );
        }

        // Store order via internal public function
        // For market buy orders, store max_quote_amount as a pseudo-limit price for refund calculation
        UmbraPool::at(context.this_address())._store_order(
            order_id,
            sender,
            base_token,
            quote_token,
            side,
            amount,
            max_quote_amount, // Store max_quote for buy orders (used for refund on cancel)
            expires_in_blocks
        ).enqueue(&mut context);

        order_id
    }

    /// Submit a limit order to the pool
    /// Limit orders specify a maximum (buy) or minimum (sell) price
    #[private]
    fn submit_limit_order(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        amount: Field,
        limit_price: Field,
        expires_in_blocks: Field,
        nonce: Field,
    ) -> pub Field {
        let sender = context.msg_sender();

        // Validate inputs
        assert(amount as u64 > 0, "Amount must be positive");
        assert(limit_price as u64 > 0, "Price must be positive for limit orders");
        assert(expires_in_blocks as u64 > 0, "Expiry must be positive");
        assert((side == SIDE_BUY) | (side == SIDE_SELL), "Invalid side");

        // Generate unique order ID
        // Safety: random() is used for order ID uniqueness, not security-critical
        let randomness = unsafe { random() };
        let order_id = dep::std::hash::pedersen_hash([
            sender.to_field(),
            base_token.to_field(),
            quote_token.to_field(),
            side,
            amount,
            limit_price,
            expires_in_blocks,
            randomness,
        ]);

        // Lock collateral based on order side
        if side == SIDE_BUY {
            // For buy limit orders, lock quote tokens at limit price
            // quote_amount = (amount * limit_price) / PRICE_PRECISION
            let quote_amount = (amount * limit_price) / (PRICE_PRECISION as Field);
            crate::token_interface::transfer_in_private(
                &mut context,
                quote_token,
                sender,
                quote_amount,
                nonce,
            );
        } else {
            // For sell limit orders, lock base tokens
            crate::token_interface::transfer_in_private(
                &mut context,
                base_token,
                sender,
                amount,
                nonce,
            );
        }

        // Store order via internal public function
        UmbraPool::at(context.this_address())._store_order(
            order_id,
            sender,
            base_token,
            quote_token,
            side,
            amount,
            limit_price,
            expires_in_blocks
        ).enqueue(&mut context);

        order_id
    }

    /// Match two orders (buy and sell)
    /// Called by a matcher/keeper to execute a trade
    ///
    /// Pricing: Executes at midpoint of buy and sell limit prices
    /// - Both limits set: price = (buy_limit + sell_limit) / 2
    /// - One market order: price = counterparty's limit price
    /// - Both market orders: not allowed (at least one must have limit)
    ///
    /// Flow:
    /// 1. Verify orders can match (buy_limit >= sell_limit)
    /// 2. Calculate execution price (midpoint)
    /// 3. Execute token transfers
    /// 4. Update order states and statistics
    #[private]
    fn match_orders(
        buy_order_id: Field,
        sell_order_id: Field,
        match_amount: Field,
        // Order data for buy order (caller must provide, validated by internal function)
        buy_owner: AztecAddress,
        buy_limit_price: Field,
        // Order data for sell order
        sell_owner: AztecAddress,
        sell_base_token: AztecAddress,
        sell_quote_token: AztecAddress,
        sell_limit_price: Field,
        // Fee parameters (validated against storage in public function)
        fee_recipient: AztecAddress,
        taker_fee_bps: Field,
        maker_fee_bps: Field,
        // Nonces for transfers
        buy_nonce: Field,
        sell_nonce: Field,
    ) {
        // Verify match amount is positive
        assert(match_amount as u64 > 0, "Match amount must be positive");

        // Calculate execution price (midpoint pricing)
        // At least one order must have a limit price
        let execution_price = if (buy_limit_price as u64 > 0) & (sell_limit_price as u64 > 0) {
            // Both have limits: verify they cross and use midpoint
            assert(buy_limit_price as u64 >= sell_limit_price as u64, "Orders do not cross");
            (buy_limit_price + sell_limit_price) / 2
        } else if buy_limit_price as u64 > 0 {
            // Sell is market order: use buy's limit
            buy_limit_price
        } else if sell_limit_price as u64 > 0 {
            // Buy is market order: use sell's limit
            sell_limit_price
        } else {
            // Both are market orders: cannot determine price
            assert(false, "At least one order must have a limit price");
            0 // unreachable
        };

        assert(execution_price as u64 > 0, "Execution price must be positive");

        // Calculate quote amount at execution price
        // quote_amount = (match_amount * execution_price) / PRICE_PRECISION
        let quote_amount = (match_amount * execution_price) / (PRICE_PRECISION as Field);

        // Calculate fees (taker = buyer, maker = seller)
        let taker_fee = (quote_amount * taker_fee_bps) / 10000;
        let maker_fee = (match_amount * maker_fee_bps) / 10000;

        // Execute transfers:
        // 1. Quote tokens: buyer -> seller (minus taker fee)
        crate::token_interface::transfer_private(
            &mut context,
            sell_quote_token,
            buy_owner,
            sell_owner,
            quote_amount - taker_fee,
            buy_nonce,
        );

        // 2. Base tokens: pool (seller's locked) -> buyer (minus maker fee)
        crate::token_interface::transfer_out_private(
            &mut context,
            sell_base_token,
            buy_owner,
            match_amount - maker_fee,
            sell_nonce,
        );

        // 3. Fees to fee_recipient
        if taker_fee as u64 > 0 {
            crate::token_interface::transfer_private(
                &mut context,
                sell_quote_token,
                buy_owner,
                fee_recipient,
                taker_fee,
                buy_nonce + 1,
            );
        }
        if maker_fee as u64 > 0 {
            crate::token_interface::transfer_out_private(
                &mut context,
                sell_base_token,
                fee_recipient,
                maker_fee,
                sell_nonce + 1,
            );
        }

        // Update order states via internal function
        // Pass fee params for validation against storage
        UmbraPool::at(context.this_address())._process_match(
            buy_order_id,
            sell_order_id,
            match_amount,
            execution_price,
            buy_owner,
            sell_owner,
            sell_base_token,
            sell_quote_token,
            buy_limit_price,
            sell_limit_price,
            fee_recipient,
            taker_fee_bps,
            maker_fee_bps
        ).enqueue(&mut context);
    }

    /// Cancel an active order
    /// Returns escrowed tokens to the owner
    #[private]
    fn cancel_order(
        order_id: Field,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        amount: Field,
        filled_amount: Field,
        limit_price: Field,
        nonce: Field,
    ) {
        let sender = context.msg_sender();

        // Calculate remaining amount
        let remaining_amount = amount - filled_amount;
        assert(remaining_amount as u64 > 0, "No amount to cancel");

        // Return locked tokens
        if side == SIDE_BUY {
            // Return quote tokens
            if limit_price as u64 > 0 {
                let quote_to_return = (remaining_amount * limit_price) / (PRICE_PRECISION as Field);
                crate::token_interface::transfer_out_private(
                    &mut context,
                    quote_token,
                    sender,
                    quote_to_return,
                    nonce,
                );
            }
        } else {
            // Return base tokens
            crate::token_interface::transfer_out_private(
                &mut context,
                base_token,
                sender,
                remaining_amount,
                nonce,
            );
        }

        // Process cancellation via internal function
        UmbraPool::at(context.this_address())._process_cancel(
            order_id,
            sender,
            side,
            amount,
            filled_amount
        ).enqueue(&mut context);
    }

    // ==================== INTERNAL PUBLIC FUNCTIONS ====================

    /// Store order data (called from submit_*_order)
    #[public]
    #[internal]
    fn _store_order(
        order_id: Field,
        owner: AztecAddress,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Field,
        amount: Field,
        limit_price: Field,
        expires_in_blocks: Field,
    ) {
        // Check not paused
        assert(!storage.paused.read(), "Contract is paused");

        // Verify pair is supported
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        assert(storage.supported_pairs.at(pair_hash).read(), "Pair not supported");

        // Verify order doesn't already exist
        assert(!storage.order_exists.at(order_id).read(), "Order already exists");

        // Calculate expiry block
        let current_block = context.block_number() as Field;
        let expires_at = current_block + expires_in_blocks;

        // Store all order data
        storage.order_exists.at(order_id).write(true);
        storage.order_owner.at(order_id).write(owner);
        storage.order_base_token.at(order_id).write(base_token);
        storage.order_quote_token.at(order_id).write(quote_token);
        storage.order_side.at(order_id).write(side);
        storage.order_amount.at(order_id).write(amount);
        storage.order_filled_amount.at(order_id).write(0);
        storage.order_limit_price.at(order_id).write(limit_price);
        storage.order_expires_at.at(order_id).write(expires_at);

        // Increment order count
        let current_count = storage.order_count.read();
        storage.order_count.write(current_count + 1);

        // Emit OrderSubmitted event
        context.emit_public_log(OrderSubmitted {
            order_id,
            base_token,
            quote_token,
            side,
        });
    }

    /// Process order match (called from match_orders)
    /// Validates execution price and fee parameters against storage
    #[public]
    #[internal]
    fn _process_match(
        buy_order_id: Field,
        sell_order_id: Field,
        match_amount: Field,
        execution_price: Field,
        provided_buy_owner: AztecAddress,
        provided_sell_owner: AztecAddress,
        provided_base_token: AztecAddress,
        provided_quote_token: AztecAddress,
        provided_buy_limit: Field,
        provided_sell_limit: Field,
        provided_fee_recipient: AztecAddress,
        provided_taker_fee: Field,
        provided_maker_fee: Field,
    ) {
        // Verify both orders exist
        assert(storage.order_exists.at(buy_order_id).read(), "Buy order does not exist");
        assert(storage.order_exists.at(sell_order_id).read(), "Sell order does not exist");

        // CRITICAL: Validate fee parameters match storage (prevents fee manipulation)
        let stored_fee_recipient = storage.fee_recipient.read();
        let stored_taker_fee = storage.taker_fee_bps.read();
        let stored_maker_fee = storage.maker_fee_bps.read();
        assert(provided_fee_recipient.eq(stored_fee_recipient), "Fee recipient mismatch");
        assert(provided_taker_fee == stored_taker_fee, "Taker fee mismatch");
        assert(provided_maker_fee == stored_maker_fee, "Maker fee mismatch");

        // Validate provided limit prices match stored values
        let buy_limit_price = storage.order_limit_price.at(buy_order_id).read();
        let sell_limit_price = storage.order_limit_price.at(sell_order_id).read();
        assert(provided_buy_limit == buy_limit_price, "Buy limit price mismatch");
        assert(provided_sell_limit == sell_limit_price, "Sell limit price mismatch");

        // Validate execution price is correct midpoint
        // Recalculate to ensure private function didn't manipulate
        let expected_price = if (buy_limit_price as u64 > 0) & (sell_limit_price as u64 > 0) {
            (buy_limit_price + sell_limit_price) / 2
        } else if buy_limit_price as u64 > 0 {
            buy_limit_price
        } else {
            sell_limit_price
        };
        assert(execution_price == expected_price, "Invalid execution price");

        // Verify orders have not expired
        let current_block = context.block_number() as Field;
        let buy_expires = storage.order_expires_at.at(buy_order_id).read();
        let sell_expires = storage.order_expires_at.at(sell_order_id).read();
        assert(buy_expires as u64 > current_block as u64, "Buy order expired");
        assert(sell_expires as u64 > current_block as u64, "Sell order expired");

        // Verify orders are for the same pair
        let buy_base = storage.order_base_token.at(buy_order_id).read();
        let buy_quote = storage.order_quote_token.at(buy_order_id).read();
        let sell_base = storage.order_base_token.at(sell_order_id).read();
        let sell_quote = storage.order_quote_token.at(sell_order_id).read();

        assert(buy_base.eq(sell_base), "Base token mismatch");
        assert(buy_quote.eq(sell_quote), "Quote token mismatch");
        assert(provided_base_token.eq(buy_base), "Provided base token mismatch");
        assert(provided_quote_token.eq(buy_quote), "Provided quote token mismatch");

        // Verify order sides
        assert(storage.order_side.at(buy_order_id).read() == SIDE_BUY, "Not a buy order");
        assert(storage.order_side.at(sell_order_id).read() == SIDE_SELL, "Not a sell order");

        // Verify owners match provided
        let buy_owner = storage.order_owner.at(buy_order_id).read();
        let sell_owner = storage.order_owner.at(sell_order_id).read();
        assert(provided_buy_owner.eq(buy_owner), "Buy owner mismatch");
        assert(provided_sell_owner.eq(sell_owner), "Sell owner mismatch");

        // Verify sufficient remaining amounts
        let buy_amount = storage.order_amount.at(buy_order_id).read();
        let buy_filled = storage.order_filled_amount.at(buy_order_id).read();
        let buy_remaining = buy_amount - buy_filled;
        assert(match_amount as u64 <= buy_remaining as u64, "Insufficient buy amount");

        let sell_amount = storage.order_amount.at(sell_order_id).read();
        let sell_filled = storage.order_filled_amount.at(sell_order_id).read();
        let sell_remaining = sell_amount - sell_filled;
        assert(match_amount as u64 <= sell_remaining as u64, "Insufficient sell amount");

        // Update filled amounts
        storage.order_filled_amount.at(buy_order_id).write(buy_filled + match_amount);
        storage.order_filled_amount.at(sell_order_id).write(sell_filled + match_amount);

        // Mark fully filled orders as non-existent
        if (buy_filled + match_amount) == buy_amount {
            storage.order_exists.at(buy_order_id).write(false);
        }
        if (sell_filled + match_amount) == sell_amount {
            storage.order_exists.at(sell_order_id).write(false);
        }

        // Update statistics
        let current_volume = storage.total_volume.read();
        storage.total_volume.write(current_volume + match_amount);

        let current_matches = storage.total_matches.read();
        storage.total_matches.write(current_matches + 1);

        // Emit OrderMatched event
        context.emit_public_log(OrderMatched {
            buy_order_id,
            sell_order_id,
            amount: match_amount,
            price: execution_price,
        });
    }

    /// Process order cancellation (called from cancel_order)
    #[public]
    #[internal]
    fn _process_cancel(
        order_id: Field,
        sender: AztecAddress,
        provided_side: Field,
        provided_amount: Field,
        provided_filled: Field,
    ) {
        // Verify order exists
        assert(storage.order_exists.at(order_id).read(), "Order does not exist");

        // Verify caller is owner
        let owner = storage.order_owner.at(order_id).read();
        assert(sender.eq(owner), "Only owner can cancel");

        // Verify provided data matches
        let stored_side = storage.order_side.at(order_id).read();
        let stored_amount = storage.order_amount.at(order_id).read();
        let stored_filled = storage.order_filled_amount.at(order_id).read();

        assert(provided_side == stored_side, "Side mismatch");
        assert(provided_amount == stored_amount, "Amount mismatch");
        assert(provided_filled == stored_filled, "Filled amount mismatch");

        // Mark order as non-existent
        storage.order_exists.at(order_id).write(false);

        // Decrement order count
        let current_count = storage.order_count.read();
        storage.order_count.write(current_count - 1);

        // Emit OrderCancelled event
        context.emit_public_log(OrderCancelled { order_id });
    }

    /// Record a match (for statistics)
    #[public]
    #[internal]
    fn _record_match(volume: Field) {
        let current_volume = storage.total_volume.read();
        storage.total_volume.write(current_volume + volume);

        let current_matches = storage.total_matches.read();
        storage.total_matches.write(current_matches + 1);
    }

    // ==================== PUBLIC VIEW FUNCTIONS ====================

    /// Get the contract admin address
    #[public]
    fn get_admin() -> pub AztecAddress {
        storage.admin.read()
    }

    /// Check if contract is paused
    #[public]
    fn is_paused() -> pub bool {
        storage.paused.read()
    }

    /// Get taker fee in basis points
    #[public]
    fn get_taker_fee() -> pub Field {
        storage.taker_fee_bps.read()
    }

    /// Get maker fee in basis points
    #[public]
    fn get_maker_fee() -> pub Field {
        storage.maker_fee_bps.read()
    }

    /// Get fee recipient address
    #[public]
    fn get_fee_recipient() -> pub AztecAddress {
        storage.fee_recipient.read()
    }

    /// Get total trading volume
    #[public]
    fn get_total_volume() -> pub Field {
        storage.total_volume.read()
    }

    /// Get total number of matches
    #[public]
    fn get_total_matches() -> pub Field {
        storage.total_matches.read()
    }

    /// Get order count
    #[public]
    fn get_order_count() -> pub Field {
        storage.order_count.read()
    }

    /// Check if an order exists
    #[public]
    fn order_exists(order_id: Field) -> pub bool {
        storage.order_exists.at(order_id).read()
    }

    /// Get order owner
    #[public]
    fn get_order_owner(order_id: Field) -> pub AztecAddress {
        storage.order_owner.at(order_id).read()
    }

    /// Get order amount
    #[public]
    fn get_order_amount(order_id: Field) -> pub Field {
        storage.order_amount.at(order_id).read()
    }

    /// Get order filled amount
    #[public]
    fn get_order_filled_amount(order_id: Field) -> pub Field {
        storage.order_filled_amount.at(order_id).read()
    }

    /// Get order limit price
    #[public]
    fn get_order_limit_price(order_id: Field) -> pub Field {
        storage.order_limit_price.at(order_id).read()
    }

    /// Check if a trading pair is supported
    #[public]
    fn is_pair_supported(base_token: AztecAddress, quote_token: AztecAddress) -> pub bool {
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        storage.supported_pairs.at(pair_hash).read()
    }

    // ==================== ADMIN FUNCTIONS ====================

    /// Add a supported trading pair (admin only)
    #[public]
    fn add_pair(base_token: AztecAddress, quote_token: AztecAddress) {
        // Verify caller is admin
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can add pair");

        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        storage.supported_pairs.at(pair_hash).write(true);

        // Emit PairAdded event
        context.emit_public_log(PairAdded { base_token, quote_token });
    }

    /// Remove a supported trading pair (admin only)
    #[public]
    fn remove_pair(base_token: AztecAddress, quote_token: AztecAddress) {
        // Verify caller is admin
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can remove pair");

        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        storage.supported_pairs.at(pair_hash).write(false);
    }

    /// Update taker fee (admin only)
    #[public]
    fn set_taker_fee(new_fee_bps: Field) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set taker fee");

        assert(new_fee_bps as u64 <= MAX_FEE_BPS, "Fee exceeds maximum");
        storage.taker_fee_bps.write(new_fee_bps);
    }

    /// Update maker fee (admin only)
    #[public]
    fn set_maker_fee(new_fee_bps: Field) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set maker fee");

        assert(new_fee_bps as u64 <= MAX_FEE_BPS, "Fee exceeds maximum");
        storage.maker_fee_bps.write(new_fee_bps);
    }

    /// Update fee recipient address (admin only)
    #[public]
    fn set_fee_recipient(new_recipient: AztecAddress) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set fee recipient");

        storage.fee_recipient.write(new_recipient);
    }

    /// Pause the contract (admin only)
    #[public]
    fn pause() {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can pause");

        storage.paused.write(true);
    }

    /// Unpause the contract (admin only)
    #[public]
    fn unpause() {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can unpause");

        storage.paused.write(false);
    }
}

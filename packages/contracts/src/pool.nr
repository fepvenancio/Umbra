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
        Self::_submit_order(
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
        Self::_submit_order(
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

        // Store order
        let pair_key = Self::get_pair_key(base_token, quote_token, side);
        storage.orders.at(pair_key).insert(&mut order);

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

        // In production, implement proper order lookup and removal
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

    // ==================== PUBLIC FUNCTIONS ====================

    #[public]
    fn add_supported_pair(base: AztecAddress, quote: AztecAddress) {
        // Add admin check in production
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
        // Add admin check in production
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

    #[public]
    fn pause() {
        // Add admin check in production
        storage.paused.write(true);
    }

    #[public]
    fn unpause() {
        // Add admin check in production
        storage.paused.write(false);
    }
}

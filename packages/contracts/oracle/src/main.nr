use dep::aztec::macros::aztec;

/// Simple Oracle Contract
/// Admin-controlled price feed for testnet
///
/// Prices are stored as: price * 1e18 (18 decimal precision)
/// Example: ETH = $3000 -> stored as 3000 * 1e18
///
/// For mainnet, replace with L1->L2 Chainlink bridge
#[aztec]
pub contract SimpleOracle {
    use dep::aztec::{
        macros::{
            functions::{public, initializer},
            storage::storage,
            events::event,
        },
        protocol_types::{address::AztecAddress, traits::ToField},
        state_vars::{Map, PublicImmutable, PublicMutable},
    };

    // ==================== EVENTS ====================

    #[event]
    pub struct PriceUpdated {
        pub base_token: AztecAddress,
        pub quote_token: AztecAddress,
        pub price: Field,
        pub block_number: Field,
    }

    // ==================== STORAGE ====================

    #[storage]
    struct Storage<Context> {
        /// Contract admin (can update prices)
        admin: PublicImmutable<AztecAddress, Context>,
        /// Prices: hash(base, quote) => price (with 18 decimals)
        prices: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Last update block: hash(base, quote) => block number
        last_updated: Map<Field, PublicMutable<Field, Context>, Context>,
    }

    // ==================== CONSTRUCTOR ====================

    #[public]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        storage.admin.initialize(admin);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /// Set price for a trading pair (admin only)
    /// Price should be in 18 decimal format
    /// Example: 1 ETH = 3000 USDC -> price = 3000 * 1e18
    #[public]
    fn set_price(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        price: Field,
    ) {
        // Verify caller is admin
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set price");

        // Price must be positive
        assert(price as u64 > 0, "Price must be positive");

        // Calculate pair hash
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);

        // Store price and update block
        storage.prices.at(pair_hash).write(price);
        let current_block = context.block_number() as Field;
        storage.last_updated.at(pair_hash).write(current_block);

        // Emit event
        context.emit_public_log(PriceUpdated {
            base_token,
            quote_token,
            price,
            block_number: current_block,
        });
    }

    /// Batch update multiple prices (admin only)
    /// More gas efficient for updating many pairs at once
    #[public]
    fn set_prices(
        base_tokens: [AztecAddress; 5],
        quote_tokens: [AztecAddress; 5],
        prices: [Field; 5],
        count: Field,
    ) {
        // Verify caller is admin
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set prices");

        let current_block = context.block_number() as Field;

        for i in 0..5 {
            if (i as u64) < (count as u64) {
                let base_token = base_tokens[i];
                let quote_token = quote_tokens[i];
                let price = prices[i];

                // Skip if price is 0 (unused slot)
                if price as u64 > 0 {
                    let pair_hash = dep::std::hash::pedersen_hash([
                        base_token.to_field(),
                        quote_token.to_field(),
                    ]);

                    storage.prices.at(pair_hash).write(price);
                    storage.last_updated.at(pair_hash).write(current_block);

                    context.emit_public_log(PriceUpdated {
                        base_token,
                        quote_token,
                        price,
                        block_number: current_block,
                    });
                }
            }
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /// Get the current price for a trading pair
    /// Returns 0 if price not set
    #[public]
    fn get_price(
        base_token: AztecAddress,
        quote_token: AztecAddress,
    ) -> pub Field {
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        storage.prices.at(pair_hash).read()
    }

    /// Get the block number when price was last updated
    #[public]
    fn get_last_updated(
        base_token: AztecAddress,
        quote_token: AztecAddress,
    ) -> pub Field {
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);
        storage.last_updated.at(pair_hash).read()
    }

    /// Get admin address
    #[public]
    fn get_admin() -> pub AztecAddress {
        storage.admin.read()
    }

    /// Check if a price exists and is not stale
    /// max_age_blocks: maximum blocks since last update (0 = no staleness check)
    #[public]
    fn is_price_valid(
        base_token: AztecAddress,
        quote_token: AztecAddress,
        max_age_blocks: Field,
    ) -> pub bool {
        let pair_hash = dep::std::hash::pedersen_hash([
            base_token.to_field(),
            quote_token.to_field(),
        ]);

        let price = storage.prices.at(pair_hash).read();

        // Price must exist (non-zero)
        let price_exists = price as u64 > 0;

        // Check staleness only if max_age_blocks > 0
        let is_fresh = if max_age_blocks as u64 == 0 {
            true  // No staleness check
        } else {
            let last_updated = storage.last_updated.at(pair_hash).read();
            let current_block = context.block_number() as Field;
            let age = current_block - last_updated;
            age as u64 <= max_age_blocks as u64
        };

        price_exists & is_fresh
    }
}

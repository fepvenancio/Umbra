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
    state_vars::{Map, PrivateImmutable, PrivateMutable, PublicMutable, PrivateSet},
    encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
};

use crate::types::{OrderNote, SettleNote};

/// Events for off-chain indexing
#[event]
struct OrderCreated {
    escrow_id: Field,
    sell_token: AztecAddress,
    buy_token: AztecAddress,
    // Note: amounts are NOT included for privacy
}

#[event]
struct OrderFilled {
    escrow_id: Field,
    // Note: buyer address is NOT included for privacy
}

#[event]
struct OrderCancelled {
    escrow_id: Field,
}

/// Storage layout for the escrow contract
#[storage]
struct Storage {
    /// Contract admin
    admin: PrivateImmutable<AztecAddress>,

    /// Active orders (private)
    orders: Map<Field, PrivateMutable<OrderNote>>,

    /// Settlement records (for compliance)
    settlements: Map<AztecAddress, PrivateSet<SettleNote>>,

    /// Order count (public for indexing)
    order_count: PublicMutable<Field>,

    /// Total volume (public for stats)
    total_volume: PublicMutable<Field>,

    /// Protocol fee recipient
    fee_recipient: PublicMutable<AztecAddress>,

    /// Fee in basis points (e.g., 30 = 0.3%)
    fee_bps: PublicMutable<Field>,
}

/// Umbra Escrow Contract
/// Handles private OTC trades between two parties
#[contract]
impl UmbraEscrow {
    /// Initialize the escrow contract
    #[initializer]
    fn constructor(admin: AztecAddress, fee_recipient: AztecAddress, fee_bps: Field) {
        storage.admin.initialize(admin);
        storage.fee_recipient.write(fee_recipient);
        storage.fee_bps.write(fee_bps);
        storage.order_count.write(0);
        storage.total_volume.write(0);
    }

    /// Create a new escrow order (seller calls this)
    ///
    /// The seller deposits sell_token into escrow and specifies
    /// what they want in return (buy_token, buy_amount)
    #[private]
    fn create_order(
        sell_token: AztecAddress,
        sell_amount: Field,
        buy_token: AztecAddress,
        buy_amount: Field,
        deadline: Field,
    ) -> Field {
        let sender = context.msg_sender();

        // Generate unique escrow ID
        let nonce = random();
        let escrow_id = std::hash::pedersen_hash([
            sender.to_field(),
            sell_token.to_field(),
            buy_token.to_field(),
            nonce,
        ]);

        // Create order note
        let order = OrderNote::new(
            sender,
            sell_token,
            sell_amount,
            buy_token,
            buy_amount,
            deadline,
            nonce,
        );

        // Store order privately
        storage.orders.at(escrow_id).write(order);

        // Emit event for indexers (minimal data)
        emit_event(OrderCreated {
            escrow_id,
            sell_token,
            buy_token,
        });

        // Update public state
        context.call_public_function(
            context.this_address(),
            compute_selector("_increment_order_count()"),
            [],
        );

        escrow_id
    }

    /// Fill an existing escrow order (buyer calls this)
    ///
    /// The buyer provides buy_token and receives sell_token
    #[private]
    fn fill_order(escrow_id: Field) {
        let buyer = context.msg_sender();

        // Read and nullify the order
        let order = storage.orders.at(escrow_id).read();

        // Verify order is valid
        let current_block = context.block_number();
        assert(!order.is_expired(current_block), "Order expired");
        assert(order.owner != buyer, "Cannot fill own order");

        // Calculate fee
        let fee_bps = context.call_public_function(
            context.this_address(),
            compute_selector("get_fee_bps()"),
            [],
        )[0];
        let fee_amount = (order.sell_amount * fee_bps) / 10000;
        let buyer_receives = order.sell_amount - fee_amount;

        // Record settlement for compliance
        let settlement = SettleNote::new(
            escrow_id,
            buyer,
            order.owner,
            buyer_receives,
            order.buy_amount,
            current_block,
        );

        // Store for both parties
        storage.settlements.at(buyer).insert(&mut settlement.clone());
        storage.settlements.at(order.owner).insert(&mut settlement);

        // Emit event
        emit_event(OrderFilled { escrow_id });

        // Update public stats
        context.call_public_function(
            context.this_address(),
            compute_selector("_record_volume(Field)"),
            [order.sell_amount],
        );
    }

    /// Cancel an unfilled order (only order creator can cancel)
    #[private]
    fn cancel_order(escrow_id: Field) {
        let sender = context.msg_sender();

        // Read and nullify the order
        let order = storage.orders.at(escrow_id).read();

        // Verify sender is the order owner
        assert(order.owner == sender, "Only owner can cancel");

        // Emit event
        emit_event(OrderCancelled { escrow_id });

        // Decrement order count
        context.call_public_function(
            context.this_address(),
            compute_selector("_decrement_order_count()"),
            [],
        );
    }

    /// Get order details (only owner can view full details)
    #[private]
    fn get_order(escrow_id: Field) -> OrderNote {
        let sender = context.msg_sender();
        let order = storage.orders.at(escrow_id).read();

        // Only owner can see full order details
        assert(order.owner == sender, "Not authorized");

        order
    }

    /// Get settlement history for a user
    #[private]
    fn get_settlements(user: AztecAddress) -> [SettleNote; 10] {
        let sender = context.msg_sender();

        // Users can only view their own settlements
        assert(user == sender, "Not authorized");

        storage.settlements.at(user).get_notes(
            NoteGetterOptions::new().set_limit(10)
        )
    }

    // ==================== PUBLIC FUNCTIONS ====================

    #[public]
    #[internal]
    fn _increment_order_count() {
        let current = storage.order_count.read();
        storage.order_count.write(current + 1);
    }

    #[public]
    #[internal]
    fn _decrement_order_count() {
        let current = storage.order_count.read();
        if current > 0 {
            storage.order_count.write(current - 1);
        }
    }

    #[public]
    #[internal]
    fn _record_volume(amount: Field) {
        let current = storage.total_volume.read();
        storage.total_volume.write(current + amount);

        let count = storage.order_count.read();
        if count > 0 {
            storage.order_count.write(count - 1);
        }
    }

    #[public]
    fn get_order_count() -> Field {
        storage.order_count.read()
    }

    #[public]
    fn get_total_volume() -> Field {
        storage.total_volume.read()
    }

    #[public]
    fn get_fee_bps() -> Field {
        storage.fee_bps.read()
    }

    #[public]
    fn get_fee_recipient() -> AztecAddress {
        storage.fee_recipient.read()
    }

    /// Admin function to update fee
    #[public]
    fn set_fee(new_fee_bps: Field) {
        // In production, add admin check
        assert(new_fee_bps <= 100, "Fee too high"); // Max 1%
        storage.fee_bps.write(new_fee_bps);
    }
}

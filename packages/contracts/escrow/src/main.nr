use dep::aztec::macros::aztec;

mod token_interface;

/// Umbra Escrow Contract
/// Handles private OTC trades between two parties
///
/// Security features:
/// - Admin-only fee management
/// - Fee cap at 1% (100 bps)
/// - Immutable admin address
/// - Pause mechanism
/// - Order existence and state tracking
#[aztec]
pub contract UmbraEscrow {
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

    // ==================== EVENTS ====================

    #[event]
    pub struct OrderCreated {
        pub escrow_id: Field,
        pub sell_token: AztecAddress,
        pub buy_token: AztecAddress,
    }

    #[event]
    pub struct OrderFilled {
        pub escrow_id: Field,
    }

    #[event]
    pub struct OrderCancelled {
        pub escrow_id: Field,
    }

    // ==================== STORAGE ====================

    #[storage]
    struct Storage<Context> {
        /// Contract admin (immutable after initialization)
        admin: PublicImmutable<AztecAddress, Context>,
        /// Protocol fee recipient
        fee_recipient: PublicMutable<AztecAddress, Context>,
        /// Fee in basis points (e.g., 30 = 0.3%)
        fee_bps: PublicMutable<Field, Context>,
        /// Emergency pause state
        paused: PublicMutable<bool, Context>,
        /// Order count (public for indexing)
        order_count: PublicMutable<Field, Context>,
        /// Total volume (public for stats)
        total_volume: PublicMutable<Field, Context>,
        /// Reentrancy guard
        reentrancy_guard: PublicMutable<bool, Context>,
        /// Supported tokens: token_address => supported
        supported_tokens: Map<Field, PublicMutable<bool, Context>, Context>,

        // ==================== ORDER STORAGE MAPS ====================
        /// Track if order ID exists
        order_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        /// Order creator/seller
        order_seller: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Token being sold
        order_sell_token: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Amount of sell token
        order_sell_amount: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Token being bought
        order_buy_token: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        /// Amount of buy token
        order_buy_amount: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Block deadline for order
        order_deadline: Map<Field, PublicMutable<Field, Context>, Context>,
        /// Whether order has been filled
        order_filled: Map<Field, PublicMutable<bool, Context>, Context>,
    }

    // ==================== CONSTRUCTOR ====================

    /// Initialize the escrow contract
    #[public]
    #[initializer]
    fn constructor(admin: AztecAddress, fee_recipient: AztecAddress, fee_bps: Field) {
        // Validate fee doesn't exceed maximum
        assert(fee_bps as u64 <= MAX_FEE_BPS, "Fee exceeds maximum");

        storage.admin.initialize(admin);
        storage.fee_recipient.write(fee_recipient);
        storage.fee_bps.write(fee_bps);
        storage.paused.write(false);
        storage.reentrancy_guard.write(false);
        storage.order_count.write(0);
        storage.total_volume.write(0);
    }

    // ==================== PRIVATE FUNCTIONS ====================

    /// Create a new escrow order (seller calls this)
    ///
    /// The seller must have pre-authorized this contract to transfer their sell_token
    /// using the auth witness system before calling this function.
    ///
    /// Flow:
    /// 1. Seller calls Token.approve(escrow_address, sell_amount, nonce)
    /// 2. Seller calls create_order(...)
    /// 3. Contract transfers sell_token from seller to itself
    /// 4. Order is stored in public state
    #[private]
    fn create_order(
        sell_token: AztecAddress,
        sell_amount: Field,
        buy_token: AztecAddress,
        buy_amount: Field,
        deadline: Field,
        nonce: Field, // Nonce for auth witness
    ) -> pub Field {
        let sender = context.msg_sender();

        // Validate inputs
        assert(sell_amount as u64 > 0, "Sell amount must be positive");
        assert(buy_amount as u64 > 0, "Buy amount must be positive");

        // Generate unique escrow ID with randomness
        // Safety: random() is used for order ID uniqueness, not security-critical randomness
        let randomness = unsafe { random() };
        let escrow_id = dep::std::hash::pedersen_hash([
            sender.to_field(),
            sell_token.to_field(),
            buy_token.to_field(),
            sell_amount,
            buy_amount,
            deadline,
            randomness,
        ]);

        // Transfer sell_token from seller to this contract
        // Requires seller to have pre-approved this transfer via auth witness
        crate::token_interface::transfer_in_private(
            &mut context,
            sell_token,
            sender,
            sell_amount,
            nonce,
        );

        // Call internal public function to store order and increment count
        UmbraEscrow::at(context.this_address())._store_order(
            escrow_id,
            sender,
            sell_token,
            sell_amount,
            buy_token,
            buy_amount,
            deadline
        ).enqueue(&mut context);

        escrow_id
    }

    /// Fill an existing escrow order (buyer calls this)
    ///
    /// The buyer must provide the order details since private functions cannot read
    /// public state. The internal public function validates these match the stored order.
    ///
    /// Flow:
    /// 1. Buyer calls Token.approve(escrow_address, buy_amount, nonce)
    /// 2. Buyer calls fill_order(...) with order details
    /// 3. Contract transfers buy_token from buyer to seller
    /// 4. Contract transfers sell_token from itself to buyer (minus fee)
    /// 5. Contract transfers fee to fee_recipient
    /// 6. Order is marked as filled in public state
    #[private]
    fn fill_order(
        escrow_id: Field,
        seller: AztecAddress,
        sell_token: AztecAddress,
        sell_amount: Field,
        buy_token: AztecAddress,
        buy_amount: Field,
        fee_recipient: AztecAddress,
        fee_bps: Field,
        nonce: Field, // Nonce for auth witness
    ) {
        let buyer = context.msg_sender();

        // Verify buyer is not the seller
        assert(!buyer.eq(seller), "Buyer cannot be seller");

        // Calculate fee and amount after fee
        let fee = (sell_amount * fee_bps) / 10000;
        let amount_after_fee = sell_amount - fee;

        // Transfer buy_token from buyer to seller (uses buyer's authwit)
        crate::token_interface::transfer_private(
            &mut context,
            buy_token,
            buyer,
            seller,
            buy_amount,
            nonce,  // User's single nonce (Solidity-like: one approval needed)
        );

        // Escrow owns sell_token - generates its own nonces for these transfers
        // Safety: random() used for nonce uniqueness, not security-critical
        let escrow_nonce1 = unsafe { random() };
        // Safety: random() used for nonce uniqueness, not security-critical
        let escrow_nonce2 = unsafe { random() };

        // Transfer sell_token from escrow to buyer (minus fee)
        crate::token_interface::transfer_out_private(
            &mut context,
            sell_token,
            buyer,
            amount_after_fee,
            escrow_nonce1,  // Escrow-generated nonce
        );

        // Transfer fee to fee_recipient (if fee > 0)
        if fee as u64 > 0 {
            crate::token_interface::transfer_out_private(
                &mut context,
                sell_token,
                fee_recipient,
                fee,
                escrow_nonce2,  // Escrow-generated nonce
            );
        }

        // Call internal public function to validate order data and mark as filled
        // Pass fee params for validation against storage
        UmbraEscrow::at(context.this_address())._process_fill(
            escrow_id,
            buyer,
            seller,
            sell_token,
            sell_amount,
            buy_token,
            buy_amount,
            fee_recipient,
            fee_bps
        ).enqueue(&mut context);
    }

    /// Cancel an unfilled order (only order creator can cancel)
    ///
    /// The seller must provide the order details for token refund.
    ///
    /// Flow:
    /// 1. Seller calls cancel_order(...) with order details
    /// 2. Contract validates caller is the seller
    /// 3. Contract transfers sell_token back to seller
    /// 4. Order is deleted from public state
    #[private]
    fn cancel_order(
        escrow_id: Field,
        sell_token: AztecAddress,
        sell_amount: Field,
        // Note: No nonce needed - escrow owns tokens and generates its own nonce
    ) {
        let sender = context.msg_sender();

        // Escrow generates its own nonce for refund (Solidity-like pattern)
        // Safety: random() used for nonce uniqueness, not security-critical
        let refund_nonce = unsafe { random() };

        // Transfer sell_token back to seller
        crate::token_interface::transfer_out_private(
            &mut context,
            sell_token,
            sender,
            sell_amount,
            refund_nonce,
        );

        // Call internal public function to validate and process cancellation
        UmbraEscrow::at(context.this_address())._process_cancel(
            escrow_id,
            sender,
            sell_token,
            sell_amount
        ).enqueue(&mut context);
    }

    // ==================== INTERNAL PUBLIC FUNCTIONS ====================

    /// Store order data (called from create_order)
    #[public]
    #[internal]
    fn _store_order(
        escrow_id: Field,
        seller: AztecAddress,
        sell_token: AztecAddress,
        sell_amount: Field,
        buy_token: AztecAddress,
        buy_amount: Field,
        deadline: Field,
    ) {
        // Reentrancy guard (defense in depth)
        assert(!storage.reentrancy_guard.read(), "Reentrant call");
        storage.reentrancy_guard.write(true);

        // Check not paused
        assert(!storage.paused.read(), "Contract is paused");

        // Verify tokens are supported
        assert(storage.supported_tokens.at(sell_token.to_field()).read(), "Sell token not supported");
        assert(storage.supported_tokens.at(buy_token.to_field()).read(), "Buy token not supported");

        // Verify order doesn't already exist
        assert(!storage.order_exists.at(escrow_id).read(), "Order already exists");

        // Store all order data
        storage.order_exists.at(escrow_id).write(true);
        storage.order_seller.at(escrow_id).write(seller);
        storage.order_sell_token.at(escrow_id).write(sell_token);
        storage.order_sell_amount.at(escrow_id).write(sell_amount);
        storage.order_buy_token.at(escrow_id).write(buy_token);
        storage.order_buy_amount.at(escrow_id).write(buy_amount);
        storage.order_deadline.at(escrow_id).write(deadline);
        storage.order_filled.at(escrow_id).write(false);

        // Increment order count
        let current_count = storage.order_count.read();
        storage.order_count.write(current_count + 1);

        // Emit OrderCreated event
        context.emit_public_log(OrderCreated {
            escrow_id,
            sell_token,
            buy_token,
        });

        // Release reentrancy guard
        storage.reentrancy_guard.write(false);
    }

    /// Process order fill (called from fill_order)
    /// Validates that the provided parameters match the stored order
    /// Token transfers already happened in the private function
    #[public]
    #[internal]
    fn _process_fill(
        escrow_id: Field,
        buyer: AztecAddress,
        provided_seller: AztecAddress,
        provided_sell_token: AztecAddress,
        provided_sell_amount: Field,
        provided_buy_token: AztecAddress,
        provided_buy_amount: Field,
        provided_fee_recipient: AztecAddress,
        provided_fee_bps: Field,
    ) {
        // Reentrancy guard (defense in depth)
        assert(!storage.reentrancy_guard.read(), "Reentrant call");
        storage.reentrancy_guard.write(true);

        // Verify order exists
        assert(storage.order_exists.at(escrow_id).read(), "Order does not exist");

        // Verify not already filled
        assert(!storage.order_filled.at(escrow_id).read(), "Order already filled");

        // CRITICAL: Validate fee parameters match storage (prevents fee bypass attack)
        let stored_fee_recipient = storage.fee_recipient.read();
        let stored_fee_bps = storage.fee_bps.read();
        assert(provided_fee_recipient.eq(stored_fee_recipient), "Fee recipient mismatch");
        assert(provided_fee_bps == stored_fee_bps, "Fee bps mismatch");

        // Get stored order data
        let stored_seller = storage.order_seller.at(escrow_id).read();
        let stored_sell_token = storage.order_sell_token.at(escrow_id).read();
        let stored_sell_amount = storage.order_sell_amount.at(escrow_id).read();
        let stored_buy_token = storage.order_buy_token.at(escrow_id).read();
        let stored_buy_amount = storage.order_buy_amount.at(escrow_id).read();
        let deadline = storage.order_deadline.at(escrow_id).read();

        // Validate provided parameters match stored order (critical security check)
        assert(provided_seller.eq(stored_seller), "Seller mismatch");
        assert(provided_sell_token.eq(stored_sell_token), "Sell token mismatch");
        assert(provided_sell_amount == stored_sell_amount, "Sell amount mismatch");
        assert(provided_buy_token.eq(stored_buy_token), "Buy token mismatch");
        assert(provided_buy_amount == stored_buy_amount, "Buy amount mismatch");

        // Verify deadline not passed
        let current_block = context.block_number();
        assert(deadline as u64 > current_block as u64, "Order expired");

        // Verify buyer != seller
        assert(!buyer.eq(stored_seller), "Buyer cannot be seller");

        // Mark order as filled
        storage.order_filled.at(escrow_id).write(true);

        // Update total volume
        let current_volume = storage.total_volume.read();
        storage.total_volume.write(current_volume + stored_sell_amount);

        // Emit OrderFilled event
        context.emit_public_log(OrderFilled { escrow_id });

        // Release reentrancy guard
        storage.reentrancy_guard.write(false);
    }

    /// Process order cancellation (called from cancel_order)
    /// Validates that the provided parameters match the stored order
    /// Token refund already happened in the private function
    #[public]
    #[internal]
    fn _process_cancel(
        escrow_id: Field,
        sender: AztecAddress,
        provided_sell_token: AztecAddress,
        provided_sell_amount: Field,
    ) {
        // Reentrancy guard (defense in depth)
        assert(!storage.reentrancy_guard.read(), "Reentrant call");
        storage.reentrancy_guard.write(true);

        // Verify order exists
        assert(storage.order_exists.at(escrow_id).read(), "Order does not exist");

        // Verify not already filled
        assert(!storage.order_filled.at(escrow_id).read(), "Order already filled");

        // Get stored order data
        let stored_seller = storage.order_seller.at(escrow_id).read();
        let stored_sell_token = storage.order_sell_token.at(escrow_id).read();
        let stored_sell_amount = storage.order_sell_amount.at(escrow_id).read();

        // Verify caller is the seller
        assert(sender.eq(stored_seller), "Only seller can cancel");

        // Validate provided parameters match stored order (critical security check)
        assert(provided_sell_token.eq(stored_sell_token), "Sell token mismatch");
        assert(provided_sell_amount == stored_sell_amount, "Sell amount mismatch");

        // Mark order as non-existent (effectively deletes it)
        storage.order_exists.at(escrow_id).write(false);

        // Decrement order count (with underflow check)
        let current_count = storage.order_count.read();
        assert(current_count as u64 > 0, "No orders to decrement");
        storage.order_count.write(current_count - 1);

        // Emit OrderCancelled event
        context.emit_public_log(OrderCancelled { escrow_id });

        // Release reentrancy guard
        storage.reentrancy_guard.write(false);
    }

    // ==================== PUBLIC VIEW FUNCTIONS ====================

    /// Get the contract admin address
    #[public]
    fn get_admin() -> pub AztecAddress {
        storage.admin.read()
    }

    /// Get current order count
    #[public]
    fn get_order_count() -> pub Field {
        storage.order_count.read()
    }

    /// Get total trading volume
    #[public]
    fn get_total_volume() -> pub Field {
        storage.total_volume.read()
    }

    /// Get current fee in basis points
    #[public]
    fn get_fee_bps() -> pub Field {
        storage.fee_bps.read()
    }

    /// Get fee recipient address
    #[public]
    fn get_fee_recipient() -> pub AztecAddress {
        storage.fee_recipient.read()
    }

    /// Check if contract is paused
    #[public]
    fn is_paused() -> pub bool {
        storage.paused.read()
    }

    /// Check if an order exists
    #[public]
    fn order_exists(escrow_id: Field) -> pub bool {
        storage.order_exists.at(escrow_id).read()
    }

    /// Check if an order is filled
    #[public]
    fn is_order_filled(escrow_id: Field) -> pub bool {
        storage.order_filled.at(escrow_id).read()
    }

    /// Get order seller
    #[public]
    fn get_order_seller(escrow_id: Field) -> pub AztecAddress {
        storage.order_seller.at(escrow_id).read()
    }

    /// Get order sell amount
    #[public]
    fn get_order_sell_amount(escrow_id: Field) -> pub Field {
        storage.order_sell_amount.at(escrow_id).read()
    }

    /// Get order buy amount
    #[public]
    fn get_order_buy_amount(escrow_id: Field) -> pub Field {
        storage.order_buy_amount.at(escrow_id).read()
    }

    // ==================== ADMIN FUNCTIONS ====================

    /// Update protocol fee (admin only)
    #[public]
    fn set_fee(new_fee_bps: Field) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can set fee");
        assert(new_fee_bps as u64 <= MAX_FEE_BPS, "Fee exceeds maximum");
        storage.fee_bps.write(new_fee_bps);
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

    /// Add a supported token (admin only)
    #[public]
    fn add_token(token: AztecAddress) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can add token");
        storage.supported_tokens.at(token.to_field()).write(true);
    }

    /// Remove a supported token (admin only)
    #[public]
    fn remove_token(token: AztecAddress) {
        let caller = context.msg_sender();
        let admin = storage.admin.read();
        assert(caller.eq(admin), "Only admin can remove token");
        storage.supported_tokens.at(token.to_field()).write(false);
    }

    /// Check if a token is supported
    #[public]
    fn is_token_supported(token: AztecAddress) -> pub bool {
        storage.supported_tokens.at(token.to_field()).read()
    }
}

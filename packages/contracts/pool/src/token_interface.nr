use dep::aztec::{
    protocol_types::{address::AztecAddress, traits::ToField},
    context::PrivateContext,
};

/// Token interface for interacting with Aztec Token contracts
///
/// IMPORTANT: This interface assumes the token contract implements:
/// - transfer_in_private(from, to, amount, nonce) - for authenticated transfers from user to contract
/// - transfer_to_private(from, to, amount) - for transfers from contract to user
///
/// The user must have created an authentication witness (authwit) before calling
/// functions that spend their tokens. See Aztec's authwit documentation:
/// https://docs.aztec.network/aztec/concepts/advanced/authwit
///
/// Token contracts should follow the Aztec Token standard for compatibility.

/// Transfer tokens from sender to this contract (private)
/// Used when a user deposits tokens into the pool for an order
///
/// Requires: User must have pre-authorized this contract via authwit
/// with the specified nonce.
pub fn transfer_in_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    // Call the token contract's transfer_in_private method
    // Standard signature: transfer_in_private(from: AztecAddress, to: AztecAddress, amount: Field, nonce: Field)
    // The 'from' account must have created an authwit for this transfer
    let _result = context.call_private_function(
        token,
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature(
            "transfer_in_private((Field),(Field),Field,Field)"
        ),
        [from.to_field(), context.this_address().to_field(), amount, nonce],
    );
}

/// Transfer tokens from this contract to a recipient (private)
/// Used when tokens are released from the pool after matching or cancellation
///
/// This contract must hold sufficient token balance to complete the transfer.
/// The nonce is used to prevent replay attacks.
pub fn transfer_out_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    // Transfer from this contract to the recipient
    // Since the contract owns these tokens, no external authwit is needed
    let _result = context.call_private_function(
        token,
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature(
            "transfer_in_private((Field),(Field),Field,Field)"
        ),
        [context.this_address().to_field(), to.to_field(), amount, nonce],
    );
}

/// Transfer tokens between two addresses (private)
/// Used for direct transfers during order matching (buyer to seller)
///
/// Requires: The 'from' account must have pre-authorized this transfer via authwit
/// with the specified nonce.
pub fn transfer_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    // Facilitates transfer between two parties
    // The 'from' account must have created an authwit for this transfer
    let _result = context.call_private_function(
        token,
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature(
            "transfer_in_private((Field),(Field),Field,Field)"
        ),
        [from.to_field(), to.to_field(), amount, nonce],
    );
}

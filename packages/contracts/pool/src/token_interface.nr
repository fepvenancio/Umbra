use dep::aztec::{
    protocol_types::{address::AztecAddress, traits::ToField},
    context::PrivateContext,
};

/// Token interface for interacting with Aztec Token contracts
/// This module provides methods to transfer tokens in private context

/// Transfer tokens from sender to this contract (private)
/// Used when a user deposits tokens into the escrow
pub fn transfer_in_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    // Call the token contract's transfer_in_private method
    // The standard Aztec Token contract has this function signature:
    // fn transfer_in_private(from: AztecAddress, to: AztecAddress, amount: Field, nonce: Field)

    let _result = context.call_private_function(
        token,
        // Function selector for transfer_in_private(AztecAddress,AztecAddress,Field,Field)
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature("transfer_in_private((Field),(Field),Field,Field)"),
        [from.to_field(), context.this_address().to_field(), amount, nonce],
    );
}

/// Transfer tokens from this contract to a recipient (private)
/// Used when tokens are released from escrow to buyer/seller
pub fn transfer_out_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    let _result = context.call_private_function(
        token,
        // Function selector for transfer_in_private(AztecAddress,AztecAddress,Field,Field)
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature("transfer_in_private((Field),(Field),Field,Field)"),
        [context.this_address().to_field(), to.to_field(), amount, nonce],
    );
}

/// Transfer tokens between two addresses (private)
/// Used for direct transfers during order fill
pub fn transfer_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    let _result = context.call_private_function(
        token,
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature("transfer_in_private((Field),(Field),Field,Field)"),
        [from.to_field(), to.to_field(), amount, nonce],
    );
}

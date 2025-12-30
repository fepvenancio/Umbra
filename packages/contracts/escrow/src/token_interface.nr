use dep::aztec::{
    protocol_types::{address::AztecAddress, traits::ToField},
    context::PrivateContext,
};

/// AIP-20 Compliant Token Interface
///
/// This module provides methods to transfer tokens using the AIP-20 standard.
/// Reference: https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737
///
/// Compatible with: https://github.com/defi-wonderland/aztec-standards
///
/// IMPORTANT: Users must create an authentication witness (authwit) before calling
/// functions that spend their tokens.

/// Transfer tokens privately from one address to another (private to private)
/// Used for direct transfers between parties (e.g., buyer pays seller)
///
/// AIP-20 function: transfer_private_to_private(from, to, amount, nonce)
pub fn transfer_private_to_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    // Cast Field to u128 for AIP-20 compatibility
    // Note: Ensure amount fits in u128 (max ~3.4e38)
    let _result = context.call_private_function(
        token,
        dep::aztec::protocol_types::abis::function_selector::FunctionSelector::from_signature(
            "transfer_private_to_private((Field),(Field),u128,Field)"
        ),
        [from.to_field(), to.to_field(), amount, nonce],
    );
}

/// Transfer tokens from user's private balance to this contract's private balance
/// Used when user deposits tokens into escrow
///
/// This is equivalent to transfer_private_to_private with `to` = this contract
pub fn transfer_in_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    let to = context.this_address();
    transfer_private_to_private(context, token, from, to, amount, nonce);
}

/// Transfer tokens from this contract's private balance to a recipient
/// Used when releasing tokens from escrow (to buyer or refund to seller)
///
/// Since the contract owns these tokens, it can transfer without external authwit
pub fn transfer_out_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    let from = context.this_address();
    transfer_private_to_private(context, token, from, to, amount, nonce);
}

/// Alias for transfer_private_to_private for backward compatibility
pub fn transfer_private(
    context: &mut PrivateContext,
    token: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    amount: Field,
    nonce: Field,
) {
    transfer_private_to_private(context, token, from, to, amount, nonce);
}

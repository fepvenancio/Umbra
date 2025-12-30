use dep::aztec::{
    protocol_types::{address::AztecAddress, traits::ToField},
};

/// Oracle interface for price validation
///
/// IMPORTANT: This is a simplified oracle interface for price validation.
/// In production, integrate with a dedicated Aztec oracle contract.
///
/// The oracle address is stored in the pool contract. When set to zero,
/// oracle validation is skipped (useful for testing).

/// Check if an oracle is configured (non-zero address)
pub fn is_oracle_configured(oracle: AztecAddress) -> bool {
    // AztecAddress::zero() check - if all bytes are 0, no oracle configured
    oracle.to_field() != 0
}

/// Validate that the provided price is within acceptable range
/// Returns true if price is valid, false otherwise
///
/// In production, this should call the oracle contract to get the price.
/// For now, it validates based on limit prices from the orders.
pub fn validate_price_range(
    provided_price: Field,
    buy_limit_price: Field,
    sell_limit_price: Field,
) -> bool {
    // If no limit prices set (market orders), any price is valid
    let no_limits = (buy_limit_price as u64 == 0) & (sell_limit_price as u64 == 0);

    // Check buy limit: provided price must be <= limit (buyer won't pay more)
    let buy_valid = if buy_limit_price as u64 > 0 {
        provided_price as u64 <= buy_limit_price as u64
    } else {
        true
    };

    // Check sell limit: provided price must be >= limit (seller won't accept less)
    let sell_valid = if sell_limit_price as u64 > 0 {
        provided_price as u64 >= sell_limit_price as u64
    } else {
        true
    };

    // Price is valid if no limits set OR both limits are satisfied
    no_limits | (buy_valid & sell_valid)
}

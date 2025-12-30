use aztec::{
    macros::notes::note,
    prelude::{AztecAddress, NoteHeader},
    protocol_types::traits::Empty,
};

/// Order direction
pub struct Side {
    value: Field,
}

impl Side {
    pub fn BUY() -> Self { Self { value: 0 } }
    pub fn SELL() -> Self { Self { value: 1 } }

    pub fn is_buy(&self) -> bool { self.value == 0 }
    pub fn is_sell(&self) -> bool { self.value == 1 }

    pub fn opposite(&self) -> Self {
        if self.is_buy() { Self::SELL() } else { Self::BUY() }
    }
}

/// Order type
pub struct OrderType {
    value: Field,
}

impl OrderType {
    pub fn MARKET() -> Self { Self { value: 0 } }   // Fill at current midpoint
    pub fn LIMIT() -> Self { Self { value: 1 } }    // Fill at limit price or better
    pub fn IOC() -> Self { Self { value: 2 } }      // Immediate or cancel
}

/// Pool order with all parameters
#[note]
pub struct PoolOrder {
    /// Order owner
    owner: AztecAddress,

    /// Trading pair
    base_token: AztecAddress,   // e.g., WETH
    quote_token: AztecAddress,  // e.g., USDC

    /// Order parameters
    side: Field,                // Side value
    order_type: Field,          // OrderType value
    amount: Field,              // Amount of base token
    limit_price: Field,         // Price in quote per base (1e18 precision)

    /// Status tracking
    filled_amount: Field,       // How much has been filled
    created_at: Field,          // Block when created
    expires_at: Field,          // Block when expires

    /// Priority (higher = matched first)
    priority: Field,            // Based on time or fee paid

    /// Uniqueness
    nonce: Field,
}

impl PoolOrder {
    pub fn new_market(
        owner: AztecAddress,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Side,
        amount: Field,
        created_at: Field,
        expires_at: Field,
        nonce: Field,
    ) -> Self {
        Self {
            owner,
            base_token,
            quote_token,
            side: side.value,
            order_type: 0, // MARKET
            amount,
            limit_price: 0, // Market orders don't have limit
            filled_amount: 0,
            created_at,
            expires_at,
            priority: created_at, // Earlier = higher priority for market orders
            nonce,
            header: NoteHeader::empty(),
        }
    }

    pub fn new_limit(
        owner: AztecAddress,
        base_token: AztecAddress,
        quote_token: AztecAddress,
        side: Side,
        amount: Field,
        limit_price: Field,
        created_at: Field,
        expires_at: Field,
        nonce: Field,
    ) -> Self {
        Self {
            owner,
            base_token,
            quote_token,
            side: side.value,
            order_type: 1, // LIMIT
            amount,
            limit_price,
            filled_amount: 0,
            created_at,
            expires_at,
            priority: limit_price, // Better price = higher priority for limits
            nonce,
            header: NoteHeader::empty(),
        }
    }

    /// Get remaining unfilled amount
    pub fn remaining(&self) -> Field {
        self.amount - self.filled_amount
    }

    /// Check if order is fully filled
    pub fn is_filled(&self) -> bool {
        self.filled_amount >= self.amount
    }

    /// Check if expired
    pub fn is_expired(&self, current_block: Field) -> bool {
        current_block > self.expires_at
    }

    /// Check if order is active (not filled, not expired)
    pub fn is_active(&self, current_block: Field) -> bool {
        !self.is_filled() & !self.is_expired(current_block)
    }

    /// Check if price is acceptable for this order
    pub fn accepts_price(&self, price: Field) -> bool {
        if self.order_type == 0 {
            // Market orders accept any price
            true
        } else {
            // Limit orders check price
            if self.side == 0 {
                // BUY: price must be <= limit
                price <= self.limit_price
            } else {
                // SELL: price must be >= limit
                price >= self.limit_price
            }
        }
    }

    /// Check if this order can match with another
    pub fn can_match(&self, other: &PoolOrder, price: Field) -> bool {
        // Must be same pair
        (self.base_token == other.base_token) &
        (self.quote_token == other.quote_token) &
        // Must be opposite sides
        (self.side != other.side) &
        // Both must accept the price
        self.accepts_price(price) &
        other.accepts_price(price) &
        // Both must have remaining amount
        (self.remaining() > 0) &
        (other.remaining() > 0)
    }

    /// Calculate match amount (minimum of both remaining)
    pub fn match_amount(&self, other: &PoolOrder) -> Field {
        let my_remaining = self.remaining();
        let their_remaining = other.remaining();
        if my_remaining < their_remaining {
            my_remaining
        } else {
            their_remaining
        }
    }
}

impl Empty for PoolOrder {
    fn empty() -> Self {
        Self {
            owner: AztecAddress::empty(),
            base_token: AztecAddress::empty(),
            quote_token: AztecAddress::empty(),
            side: 0,
            order_type: 0,
            amount: 0,
            limit_price: 0,
            filled_amount: 0,
            created_at: 0,
            expires_at: 0,
            priority: 0,
            nonce: 0,
            header: NoteHeader::empty(),
        }
    }
}

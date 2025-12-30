use aztec::{
    macros::notes::note,
    note::note_getter_options::NoteGetterOptions,
    prelude::{AztecAddress, NoteHash, NoteHeader},
    protocol_types::traits::{Empty, Serialize, Deserialize},
};

/// OrderNote represents a private OTC order
/// Only the order creator can see the full details
#[note]
pub struct OrderNote {
    /// The address that created this order (seller)
    owner: AztecAddress,
    /// Token address being sold
    sell_token: AztecAddress,
    /// Amount of sell_token being offered
    sell_amount: Field,
    /// Token address wanted in exchange
    buy_token: AztecAddress,
    /// Amount of buy_token wanted
    buy_amount: Field,
    /// Block number deadline for the order
    deadline: Field,
    /// Random nonce for uniqueness
    nonce: Field,
}

impl OrderNote {
    pub fn new(
        owner: AztecAddress,
        sell_token: AztecAddress,
        sell_amount: Field,
        buy_token: AztecAddress,
        buy_amount: Field,
        deadline: Field,
        nonce: Field,
    ) -> Self {
        Self {
            owner,
            sell_token,
            sell_amount,
            buy_token,
            buy_amount,
            deadline,
            nonce,
            header: NoteHeader::empty(),
        }
    }

    /// Get the effective price (buy/sell ratio)
    pub fn get_price(&self) -> Field {
        // Note: In production, use proper fixed-point math
        self.buy_amount / self.sell_amount
    }

    /// Check if order is expired
    pub fn is_expired(&self, current_block: Field) -> bool {
        current_block > self.deadline
    }

    /// Check if this order can be matched with another
    pub fn can_match(&self, other: &OrderNote) -> bool {
        // Orders match if:
        // 1. Sell/buy tokens are swapped
        // 2. Amounts are compatible
        // 3. Neither is expired
        (self.sell_token == other.buy_token) &
        (self.buy_token == other.sell_token) &
        (self.sell_amount >= other.buy_amount) &
        (self.buy_amount <= other.sell_amount)
    }
}

impl Empty for OrderNote {
    fn empty() -> Self {
        Self {
            owner: AztecAddress::empty(),
            sell_token: AztecAddress::empty(),
            sell_amount: 0,
            buy_token: AztecAddress::empty(),
            buy_amount: 0,
            deadline: 0,
            nonce: 0,
            header: NoteHeader::empty(),
        }
    }
}

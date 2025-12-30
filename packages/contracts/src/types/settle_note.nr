use aztec::{
    macros::notes::note,
    prelude::{AztecAddress, NoteHash, NoteHeader},
    protocol_types::traits::Empty,
};

/// SettleNote records a completed trade
/// Used for compliance and audit purposes
#[note]
pub struct SettleNote {
    /// Unique escrow identifier
    escrow_id: Field,
    /// Buyer address
    buyer: AztecAddress,
    /// Seller address
    seller: AztecAddress,
    /// Amount buyer received
    buyer_amount: Field,
    /// Amount seller received
    seller_amount: Field,
    /// Block when settled
    settled_at: Field,
}

impl SettleNote {
    pub fn new(
        escrow_id: Field,
        buyer: AztecAddress,
        seller: AztecAddress,
        buyer_amount: Field,
        seller_amount: Field,
        settled_at: Field,
    ) -> Self {
        Self {
            escrow_id,
            buyer,
            seller,
            buyer_amount,
            seller_amount,
            settled_at,
            header: NoteHeader::empty(),
        }
    }
}

impl Empty for SettleNote {
    fn empty() -> Self {
        Self {
            escrow_id: 0,
            buyer: AztecAddress::empty(),
            seller: AztecAddress::empty(),
            buyer_amount: 0,
            seller_amount: 0,
            settled_at: 0,
            header: NoteHeader::empty(),
        }
    }
}

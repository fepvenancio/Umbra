// Umbra Protocol - Privacy-Native Dark Pool on Aztec
//
// This contract system enables:
// - Private OTC trades with no information leakage
// - Hidden order books with encrypted intents
// - Atomic settlement with ZK proofs
//
// Architecture:
// - UmbraEscrow: Handles individual OTC trades
// - UmbraPool: Aggregates orders for matching

mod types;
mod escrow;
mod pool;

// Re-export for external use
pub use escrow::UmbraEscrow;
pub use pool::UmbraPool;
pub use types::{OrderNote, SettleNote, PoolOrder, Side, OrderType};

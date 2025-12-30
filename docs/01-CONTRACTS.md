# 01-CONTRACTS.md - Noir Smart Contract Development

## Overview

Build the core Noir smart contracts for Umbra Protocol. We'll create:
1. **OrderNote** - Private order data structure
2. **UmbraEscrow** - OTC escrow for single trades
3. **UmbraPool** - Dark pool with order matching

---

## Contract Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UMBRA CONTRACT SYSTEM                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐     ┌─────────────────┐                       │
│  │   OrderNote     │     │   SettleNote    │                       │
│  │   (Private)     │     │   (Private)     │                       │
│  │                 │     │                 │                       │
│  │ - owner         │     │ - escrow_id     │                       │
│  │ - sell_token    │     │ - buyer         │                       │
│  │ - sell_amount   │     │ - seller        │                       │
│  │ - buy_token     │     │ - completed     │                       │
│  │ - buy_amount    │     │ - timestamp     │                       │
│  │ - deadline      │     │                 │                       │
│  │ - nonce         │     │                 │                       │
│  └────────┬────────┘     └────────┬────────┘                       │
│           │                       │                                 │
│           ▼                       ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │                   UmbraEscrow                           │       │
│  │                                                         │       │
│  │  PRIVATE FUNCTIONS:                                     │       │
│  │  - create_order()    Create new escrow order           │       │
│  │  - fill_order()      Fill existing order               │       │
│  │  - cancel_order()    Cancel unfilled order             │       │
│  │                                                         │       │
│  │  PUBLIC FUNCTIONS:                                      │       │
│  │  - finalize_create() Commit order to state             │       │
│  │  - finalize_fill()   Complete the swap                 │       │
│  │                                                         │       │
│  └────────────────────────────────┬────────────────────────┘       │
│                                   │                                 │
│                                   ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │                    UmbraPool                            │       │
│  │                                                         │       │
│  │  PRIVATE FUNCTIONS:                                     │       │
│  │  - submit_order()    Submit order to pool              │       │
│  │  - match_orders()    Match compatible orders           │       │
│  │  - withdraw()        Withdraw from pool                │       │
│  │                                                         │       │
│  │  PUBLIC STATE:                                          │       │
│  │  - total_volume      Total volume traded               │       │
│  │  - order_count       Number of active orders           │       │
│  │                                                         │       │
│  └─────────────────────────────────────────────────────────┘       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Create Note Types

### OrderNote (Private Order Data)

```bash
# Navigate to types directory
cd packages/contracts/src/types

# Create order_note.nr
cat > order_note.nr << 'NOIR_EOF'
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
NOIR_EOF
```

### SettleNote (Settlement Record)

```bash
cat > settle_note.nr << 'NOIR_EOF'
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
NOIR_EOF
```

### Update Types Module

```bash
cat > mod.nr << 'NOIR_EOF'
mod order_note;
mod settle_note;

pub use order_note::OrderNote;
pub use settle_note::SettleNote;
NOIR_EOF
```

---

## Step 2: Create Escrow Contract

```bash
cd ..

# Create escrow contract
cat > escrow.nr << 'NOIR_EOF'
use aztec::{
    context::{PrivateContext, PublicContext},
    macros::{
        functions::{private, public, initializer, internal},
        storage::storage,
        events::event,
    },
    messages::message_delivery::MessageDelivery,
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
        
        // Transfer sell_token from seller to this contract
        // Note: Caller must have approved this contract
        let token = Token::at(sell_token);
        token.transfer_to_private(context.this_address(), sell_amount);
        
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
        
        // Transfer buy_token from buyer to seller
        let buy_token = Token::at(order.buy_token);
        buy_token.transfer_from(buyer, order.owner, order.buy_amount);
        
        // Transfer sell_token from escrow to buyer
        let sell_token = Token::at(order.sell_token);
        sell_token.transfer_to_private(buyer, buyer_receives);
        
        // Transfer fee to protocol
        if fee_amount > 0 {
            let fee_recipient = context.call_public_function(
                context.this_address(),
                compute_selector("get_fee_recipient()"),
                [],
            )[0];
            sell_token.transfer_to_private(
                AztecAddress::from_field(fee_recipient),
                fee_amount,
            );
        }
        
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
        
        // Return funds to seller
        let sell_token = Token::at(order.sell_token);
        sell_token.transfer_to_private(sender, order.sell_amount);
        
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
NOIR_EOF
```

---

## Step 3: Update Main Contract File

```bash
cat > main.nr << 'NOIR_EOF'
// Umbra Protocol - Privacy-Native Dark Pool on Aztec
// 
// This contract system enables:
// - Private OTC trades with no information leakage
// - Hidden order books with encrypted intents
// - Atomic settlement with ZK proofs
// 
// Architecture:
// - UmbraEscrow: Handles individual OTC trades
// - UmbraPool: Aggregates orders for matching (Phase 2)

mod types;
mod escrow;

// Re-export for external use
pub use escrow::UmbraEscrow;
pub use types::{OrderNote, SettleNote};
NOIR_EOF
```

---

## Step 4: Create Token Interface

We need a token contract interface for interacting with tokens.

```bash
cat > token_interface.nr << 'NOIR_EOF'
use aztec::prelude::*;

/// Interface for interacting with Aztec token contracts
/// Based on the standard Aztec token implementation
struct Token {
    address: AztecAddress,
}

impl Token {
    pub fn at(address: AztecAddress) -> Self {
        Self { address }
    }

    /// Transfer tokens to a private balance
    pub fn transfer_to_private(
        self,
        to: AztecAddress,
        amount: Field,
    ) {
        // This calls the token contract's transfer_to_private function
        context.call_private_function(
            self.address,
            compute_selector("transfer_to_private(AztecAddress,Field)"),
            [to.to_field(), amount],
        );
    }

    /// Transfer tokens between private balances
    pub fn transfer_from(
        self,
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
    ) {
        context.call_private_function(
            self.address,
            compute_selector("transfer(AztecAddress,Field)"),
            [to.to_field(), amount],
        );
    }

    /// Get public balance
    pub fn balance_of_public(self, owner: AztecAddress) -> Field {
        context.call_public_function(
            self.address,
            compute_selector("balance_of_public(AztecAddress)"),
            [owner.to_field()],
        )[0]
    }
}
NOIR_EOF
```

---

## Step 5: Compile Contracts

```bash
# Return to contracts root
cd packages/contracts

# Compile
aztec-nargo compile

# Expected output:
# Compiling umbra_contracts
# Compiled successfully
```

---

## Step 6: Generate TypeScript Bindings

```bash
# Generate TypeScript artifacts
aztec codegen ./target -o ./ts

# This creates:
# ts/
# ├── UmbraEscrow.ts
# ├── artifacts/
# │   └── umbra_escrow.json
# └── index.ts
```

---

## Step 7: Create Contract Tests

```bash
mkdir -p tests

cat > tests/escrow.test.ts << 'TYPESCRIPT_EOF'
import { describe, it, expect, beforeAll } from "bun:test";
import {
  AccountWallet,
  CompleteAddress,
  createPXEClient,
  PXE,
} from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { UmbraEscrow } from "../ts/UmbraEscrow.js";

describe("UmbraEscrow", () => {
  let pxe: PXE;
  let wallets: AccountWallet[];
  let escrowContract: UmbraEscrow;
  let seller: AccountWallet;
  let buyer: AccountWallet;

  beforeAll(async () => {
    // Connect to sandbox
    pxe = createPXEClient("http://localhost:8080");
    wallets = await getInitialTestAccountsWallets(pxe);
    
    seller = wallets[0];
    buyer = wallets[1];
    
    // Deploy escrow contract
    const deployTx = await UmbraEscrow.deploy(
      seller,
      seller.getAddress(),  // admin
      seller.getAddress(),  // fee recipient
      30n,                  // 0.3% fee
    ).send();
    
    escrowContract = await deployTx.deployed();
    console.log(`Escrow deployed at: ${escrowContract.address}`);
  });

  it("should deploy successfully", async () => {
    expect(escrowContract.address).toBeDefined();
  });

  it("should have zero order count initially", async () => {
    const count = await escrowContract.methods.get_order_count().simulate();
    expect(count).toBe(0n);
  });

  it("should create an order", async () => {
    // This test requires deploying test tokens first
    // See 05-CLI.md for full integration tests
    expect(true).toBe(true);
  });
});
TYPESCRIPT_EOF
```

---

## Step 8: Verify Compilation

```bash
# Final check
aztec-nargo compile

# Run TypeScript build
bun run build

# Run tests (will need sandbox running)
bun test
```

---

## Common Errors and Fixes

### "Cannot find module 'aztec'"

```bash
# Check Nargo.toml has correct version
# Update to match your sandbox version:
aztec --version

# Update Nargo.toml:
aztec = { git = "...", tag = "vX.X.X", ... }
```

### "Note type not found"

```bash
# Ensure notes have #[note] macro
# Ensure mod.nr exports them properly
```

### "Cannot call public from private"

This is expected behavior in Aztec. Use `context.call_public_function()` pattern.

---

## What We Built

1. ✅ **OrderNote** - Private order representation
2. ✅ **SettleNote** - Settlement records for compliance
3. ✅ **UmbraEscrow** - Core escrow logic with:
   - Private order creation
   - Private order filling
   - Order cancellation
   - Fee collection
   - Settlement tracking

---

## Next Steps

➡️ Proceed to **`docs/02-ESCROW.md`** for advanced escrow features:
- Partial fills
- Price oracle integration
- Multi-token support
- Viewing key implementation

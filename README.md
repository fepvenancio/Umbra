# Umbra Protocol

A dark pool for Aztec Network.

## Overview

Umbra enables OTC trading on Aztec with atomic settlement and oracle-based pricing.

**Three contracts:**
- **UmbraEscrow** — Bilateral OTC trades between two parties
- **UmbraPool** — Order book with automatic matching at oracle prices
- **SimpleOracle** — Price feed for the pool (testnet only)

## How It Works

### Escrow Flow
```
1. Seller creates order, locks tokens
2. Buyer fills order at agreed price
3. Tokens swap atomically — no counterparty risk
```

### Pool Flow
```
1. Traders submit buy/sell orders with collateral
2. Keeper matches compatible orders at oracle price
3. Tokens transfer atomically, fees collected
```

## Privacy Model

Umbra runs on Aztec, a ZK rollup. Here's what that means:

**Private (hidden from observers):**
- Token balances — stored as encrypted notes
- Transfer amounts — ZK proofs verify without revealing
- Transaction sender — private function callers are hidden

**Public (visible on-chain):**
- Order metadata — tokens, amounts, owner, limits
- Order status — filled, cancelled, partial fills
- Protocol config — fees, admin, oracle address

Orders are public by design. A matcher must read orders to pair them. The privacy comes from Aztec's token layer — your balances and transfers stay hidden.

## Quick Start

```bash
# Install dependencies
bun install

# Compile contracts
cd packages/contracts && ~/.aztec/bin/aztec-nargo compile

# Run tests
bun test

# Start API server
cd packages/api && bun run start
```

## Project Structure

```
umbra/
├── packages/
│   ├── contracts/     # Noir smart contracts
│   │   ├── escrow/    # OTC escrow
│   │   ├── pool/      # Dark pool
│   │   └── oracle/    # Price feed
│   ├── api/           # Orderflow REST API
│   └── cli/           # CLI tools
└── docs/              # Documentation
```

## Contracts

### UmbraEscrow

Bilateral OTC escrow:
- Create order with token lockup
- Fill atomically with fee collection
- Cancel and reclaim tokens
- Admin controls: pause, fees, token whitelist

### UmbraPool

Order book with matching:
- Market orders (execute at oracle price)
- Limit orders (price constraints)
- Partial fills with accurate tracking
- Trading pair whitelist

### SimpleOracle

Admin-controlled price feed:
- Set prices per trading pair
- Staleness validation
- Testnet only — mainnet uses L1 oracle bridge

## Fees

| Parameter | Default | Max |
|-----------|---------|-----|
| Taker Fee | 30 bps | 100 bps |
| Maker Fee | 10 bps | 100 bps |

## Status

**Testnet Ready** — Contracts compile and pass tests.

See [docs/FIXES.md](docs/FIXES.md) for security details.

## License

MIT

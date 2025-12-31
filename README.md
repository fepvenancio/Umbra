# Umbra Protocol

Privacy-native dark pool on Aztec Network.

## What is Umbra?

Umbra enables private OTC trades on Aztec Network:

- **Private Orders** - Order details encrypted with ZK proofs
- **Atomic Settlement** - All-or-nothing trades, no counterparty risk
- **Oracle Pricing** - Fair execution at oracle price (no price revelation)
- **Partial Fills** - Large orders fill incrementally

## Architecture

```
Traders -> PXE (client-side ZK proofs) -> Smart Contracts -> Aztec Network

Contracts:
- UmbraEscrow: P2P OTC trades with escrow
- UmbraPool: Dark pool with automatic matching
- SimpleOracle: Admin-controlled price feed (testnet)
```

## Quick Start

```bash
# Install
bun install

# Compile contracts
cd packages/contracts && ~/.aztec/bin/aztec-nargo compile

# Run tests
bun test

# Start API
cd packages/api && bun run start
```

## Project Structure

```
umbra/
├── packages/
│   ├── contracts/     # Noir smart contracts
│   │   ├── escrow/    # OTC escrow contract
│   │   ├── pool/      # Dark pool contract
│   │   └── oracle/    # Price oracle contract
│   ├── api/           # Orderflow REST API
│   └── cli/           # CLI tools and demo
└── docs/              # Documentation
```

## Contracts

### UmbraEscrow
P2P OTC trades with:
- Order creation with token escrow
- Atomic fill with fee collection
- Cancellation with refund
- Admin controls (pause, fee management)

### UmbraPool
Dark pool order book with:
- Market and limit orders
- Automatic order matching
- Oracle-based pricing (true dark pool)
- Partial fills
- Trading pair whitelist

### SimpleOracle
Admin-controlled price feed for testnet:
- Set prices per trading pair
- Staleness checking
- For mainnet: replace with L1->L2 Chainlink bridge

## Configuration

| Parameter | Default | Range |
|-----------|---------|-------|
| Taker Fee | 30 bps | 0-100 bps |
| Maker Fee | 10 bps | 0-100 bps |
| Max Fee | 100 bps (1%) | - |

## Status

**Testnet Ready** - Contracts compile and pass tests.

See [docs/FIXES.md](docs/FIXES.md) for security assessment.

## License

MIT

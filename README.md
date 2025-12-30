# 🌑 Umbra Protocol

**The first privacy-native dark pool on Aztec Network**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Aztec](https://img.shields.io/badge/Built%20on-Aztec-purple)](https://aztec.network)
[![Noir](https://img.shields.io/badge/Language-Noir-black)](https://noir-lang.org)

---

## 🎯 What is Umbra?

Umbra is a **decentralized dark pool** that enables private OTC trades on Aztec Network. Unlike transparent DEXes where every trade is visible, Umbra keeps your:

- **Order details private** - No one sees your size or price
- **Trading strategy hidden** - No front-running or copy-trading
- **Identity protected** - Trade without revealing your wallet

Perfect for institutions, whales, and anyone who values financial privacy.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔒 **Private Orders** | Orders encrypted with ZK proofs |
| ⚡ **Atomic Settlement** | All-or-nothing trades, no counterparty risk |
| 📊 **Oracle Pricing** | Midpoint execution pegged to real prices |
| 🔄 **Partial Fills** | Large orders fill incrementally |
| 📋 **Compliance Ready** | Viewing keys for auditors |
| 💰 **Low Fees** | 0.3% taker, 0.1% maker |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     UMBRA PROTOCOL                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Trader    │    │   Trader    │    │   Trader    │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                            ▼                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              UMBRA SMART CONTRACTS                   │  │
│  │                                                      │  │
│  │  • UmbraEscrow - P2P OTC trades                     │  │
│  │  • UmbraPool - Dark pool matching                   │  │
│  │  • SimpleOracle - Price feeds                       │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                │
│                            ▼                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                 AZTEC NETWORK                        │  │
│  │                                                      │  │
│  │  • Client-side ZK proofs                            │  │
│  │  • Private state trees                              │  │
│  │  • Ethereum settlement                              │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) v20+
- [Bun](https://bun.sh/) v1.1+
- [Docker](https://docker.com/)
- [Aztec CLI](https://docs.aztec.network/)

### Installation

```bash
# Clone the repo
git clone https://github.com/your-org/umbra-protocol.git
cd umbra-protocol

# Install dependencies
bun install

# Install Aztec toolchain
bash -i <(curl -s https://install.aztec.network)
```

### Run Locally

```bash
# Terminal 1: Start Aztec sandbox
bun run sandbox

# Terminal 2: Start API
bun run api

# Terminal 3: Run demo
bun run demo
```

---

## 📦 Project Structure

```
umbra-protocol/
├── packages/
│   ├── contracts/          # Noir smart contracts
│   │   ├── src/
│   │   │   ├── main.nr    # Contract entry
│   │   │   ├── escrow.nr  # OTC escrow
│   │   │   ├── pool.nr    # Dark pool
│   │   │   └── types/     # Note types
│   │   └── Nargo.toml
│   │
│   ├── api/               # Orderflow service
│   │   └── src/
│   │       ├── index.ts   # Server
│   │       ├── db.ts      # Database
│   │       └── handlers.ts
│   │
│   └── cli/               # CLI tools
│       └── scripts/
│           ├── deploy.ts
│           ├── create-order.ts
│           └── demo.ts
│
├── docs/                  # Documentation
├── CLAUDE.md             # Build guide
├── BUILD.md              # Phase-by-phase guide
└── README.md             # This file
```

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [CLAUDE.md](CLAUDE.md) | AI build guide with persona |
| [BUILD.md](BUILD.md) | Step-by-step build phases |
| [00-SETUP.md](docs/00-SETUP.md) | Environment setup |
| [01-CONTRACTS.md](docs/01-CONTRACTS.md) | Contract development |
| [02-ESCROW.md](docs/02-ESCROW.md) | Escrow features |
| [03-POOL.md](docs/03-POOL.md) | Pool matching |
| [04-ORDERFLOW.md](docs/04-ORDERFLOW.md) | API service |
| [05-CLI.md](docs/05-CLI.md) | CLI tools |
| [07-DEPLOY.md](docs/07-DEPLOY.md) | Deployment |

---

## 🔧 Commands

```bash
# Build
bun run build              # Build all
bun run build:contracts    # Build contracts only

# Test
bun run test               # Run all tests
bun run test:contracts     # Contract tests
bun run test:api           # API tests

# Development
bun run sandbox            # Start local Aztec
bun run api                # Start API server
bun run demo               # Run full demo

# CLI
bun run setup:deploy       # Deploy contracts
bun run setup:mint         # Mint test tokens
bun run order:create       # Create order
bun run order:fill         # Fill order
bun run balances           # Check balances
```

---

## 🛡️ Security

### Audit Status

⚠️ **NOT AUDITED** - This is experimental software. Use at your own risk.

### Bug Bounty

Coming soon.

### Responsible Disclosure

Email: security@umbra.xyz

---

## 🗺️ Roadmap

- [x] **Phase 1**: Basic OTC escrow
- [x] **Phase 2**: Partial fills & oracle pricing
- [x] **Phase 3**: Dark pool matching engine
- [ ] **Phase 4**: Cross-chain bridges
- [ ] **Phase 5**: Mainnet launch
- [ ] **Phase 6**: Governance token

---

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/umbra-protocol.git

# Create branch
git checkout -b feature/your-feature

# Make changes and test
bun run test

# Submit PR
```

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

## 🔗 Links

- [Aztec Network](https://aztec.network)
- [Noir Language](https://noir-lang.org)
- [Aztec Documentation](https://docs.aztec.network)

---

## 💬 Community

- Discord: [Join](https://discord.gg/umbra)
- Twitter: [@UmbraProtocol](https://twitter.com/umbraprotocol)
- Forum: [forum.umbra.xyz](https://forum.umbra.xyz)

---

<p align="center">
  <b>Built with 🖤 on Aztec Network</b>
</p>

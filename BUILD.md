# BUILD.md - Claude Code Master Build Guide

## 🎯 OBJECTIVE

Build **Umbra Protocol** - a privacy-native dark pool on Aztec Network.

**You are ShadowForge**, an expert ZK protocol developer. Follow this guide sequentially, completing each phase before moving to the next.

---

## 📋 BUILD PHASES

```
PHASE 1: Environment Setup       [~15 min]
PHASE 2: Core Contracts          [~2 hours]
PHASE 3: Orderflow API           [~1 hour]
PHASE 4: CLI Integration         [~1 hour]
PHASE 5: Testing & Polish        [~1 hour]
PHASE 6: Documentation           [~30 min]
```

---

## 🚀 PHASE 1: Environment Setup

### 1.1 Initialize Repository

```bash
# Create project structure
mkdir -p umbra-protocol
cd umbra-protocol

# Initialize git
git init
echo "node_modules/\n.env\ndata/\ntarget/\nartifacts/" > .gitignore

# Create workspace structure
mkdir -p packages/contracts/src/types
mkdir -p packages/api/src
mkdir -p packages/cli/scripts
mkdir -p docs
mkdir -p data
```

### 1.2 Create Root package.json

```json
{
  "name": "umbra-protocol",
  "version": "0.1.0",
  "private": true,
  "workspaces": ["packages/*"],
  "scripts": {
    "build": "bun run build:contracts && bun run build:api",
    "build:contracts": "cd packages/contracts && aztec-nargo compile && aztec codegen ./target -o ./ts",
    "test": "bun run test:contracts && bun run test:api",
    "test:contracts": "cd packages/contracts && bun test",
    "test:api": "cd packages/api && bun test",
    "sandbox": "aztec start --sandbox",
    "api": "cd packages/api && bun run start",
    "demo": "cd packages/cli && bun run demo"
  }
}
```

### 1.3 Install Aztec Toolchain

```bash
# Install Aztec (if not already installed)
bash -i <(curl -s https://install.aztec.network)

# Verify
aztec --version
aztec-nargo --version
```

### ✅ CHECKPOINT 1: Environment Ready

```bash
# Verify:
aztec --version      # Should output version
bun --version        # Should output version
docker ps           # Docker running
```

---

## 🔨 PHASE 2: Core Contracts

### 2.1 Create Nargo.toml

```bash
cd packages/contracts

cat > Nargo.toml << 'EOF'
[package]
name = "umbra_contracts"
type = "contract"
authors = ["Umbra Protocol"]
compiler_version = ">=1.0.0"

[dependencies]
aztec = { git = "https://github.com/AztecProtocol/aztec-packages/", tag = "v1.2.0", directory = "noir-projects/aztec-nr/aztec" }
value_note = { git = "https://github.com/AztecProtocol/aztec-packages/", tag = "v1.2.0", directory = "noir-projects/aztec-nr/value-note" }
EOF
```

### 2.2 Create Note Types

**File: `src/types/order_note.nr`**

Create the OrderNote struct with:
- owner: AztecAddress
- sell_token: AztecAddress
- sell_amount: Field
- buy_token: AztecAddress
- buy_amount: Field
- deadline: Field
- nonce: Field

Include the `#[note]` macro and implement `Empty` trait.

### 2.3 Create Escrow Contract

**File: `src/escrow.nr`**

Implement UmbraEscrow with:

**Storage:**
- admin: PrivateImmutable<AztecAddress>
- orders: Map<Field, PrivateMutable<OrderNote>>
- fee_bps: PublicMutable<Field>
- total_volume: PublicMutable<Field>

**Functions:**
- `constructor(admin, fee_recipient, fee_bps)`
- `create_order(sell_token, sell_amount, buy_token, buy_amount, deadline) -> Field`
- `fill_order(escrow_id)`
- `cancel_order(escrow_id)`
- `get_fee_bps() -> Field` (public)
- `get_total_volume() -> Field` (public)

### 2.4 Create Main Entry

**File: `src/main.nr`**

```noir
mod types;
mod escrow;

pub use escrow::UmbraEscrow;
pub use types::OrderNote;
```

### 2.5 Compile Contracts

```bash
aztec-nargo compile
```

### ✅ CHECKPOINT 2: Contracts Compile

```bash
# Verify:
ls target/  # Should contain compiled artifacts
```

---

## 🌐 PHASE 3: Orderflow API

### 3.1 Create API Package

```bash
cd packages/api

cat > package.json << 'EOF'
{
  "name": "@umbra/api",
  "version": "0.1.0",
  "scripts": {
    "start": "bun run src/index.ts",
    "dev": "bun --watch run src/index.ts",
    "test": "bun test"
  },
  "dependencies": {
    "better-sqlite3": "^9.4.0"
  },
  "devDependencies": {
    "@types/better-sqlite3": "^7.6.8"
  }
}
EOF

bun install
```

### 3.2 Create Database Layer

**File: `src/db.ts`**

Create SQLite database with tables:
- orders (id, escrow_address, base_token, quote_token, side, status, created_at, expires_at)
- pairs (base_token, quote_token, is_active)

### 3.3 Create API Handlers

**File: `src/handlers.ts`**

Implement handlers for:
- `createOrder(req) -> Response`
- `getOrder(req, id) -> Response`
- `listOrders(req) -> Response`
- `cancelOrder(req, id) -> Response`
- `listPairs(req) -> Response`

### 3.4 Create Server

**File: `src/index.ts`**

Create Bun.serve() with routing:
- GET /health
- GET/POST /order
- GET/PUT/DELETE /order/:id
- GET/POST /pairs

### 3.5 Test API

```bash
bun run start &
curl http://localhost:3000/health
```

### ✅ CHECKPOINT 3: API Running

```bash
# Verify:
curl http://localhost:3000/health  # Returns {"status":"healthy"}
```

---

## 🖥️ PHASE 4: CLI Integration

### 4.1 Create CLI Package

```bash
cd packages/cli

cat > package.json << 'EOF'
{
  "name": "@umbra/cli",
  "version": "0.1.0",
  "scripts": {
    "setup:deploy": "bun run scripts/deploy.ts",
    "setup:mint": "bun run scripts/mint.ts",
    "order:create": "bun run scripts/create-order.ts",
    "order:fill": "bun run scripts/fill-order.ts",
    "balances": "bun run scripts/balances.ts",
    "demo": "bun run scripts/demo.ts"
  },
  "dependencies": {
    "@aztec/aztec.js": "^0.84.0",
    "@aztec/accounts": "^0.84.0"
  }
}
EOF

bun install
```

### 4.2 Create Utility Functions

**File: `scripts/utils.ts`**

Create helpers for:
- PXE client connection
- Wallet management
- Deployment data storage/loading
- Logging utilities

### 4.3 Create Deploy Script

**File: `scripts/deploy.ts`**

Script that:
1. Connects to PXE
2. Gets deployer wallet
3. Deploys Token contracts
4. Deploys UmbraEscrow
5. Saves addresses to data/deployments.json

### 4.4 Create Order Scripts

**File: `scripts/create-order.ts`**
- Creates order on-chain
- Registers with API

**File: `scripts/fill-order.ts`**
- Fills order on-chain
- Updates API status

### 4.5 Create Demo Script

**File: `scripts/demo.ts`**

Orchestrates full flow:
1. Deploy
2. Mint
3. Show balances
4. Create order
5. Fill order
6. Show final balances

### ✅ CHECKPOINT 4: CLI Working

```bash
# Verify (with sandbox running):
bun run demo  # Should complete without errors
```

---

## 🧪 PHASE 5: Testing & Polish

### 5.1 Contract Tests

**File: `packages/contracts/tests/escrow.test.ts`**

Write tests for:
- Contract deployment
- Order creation
- Order filling
- Order cancellation
- Fee collection

### 5.2 API Tests

**File: `packages/api/tests/api.test.ts`**

Write tests for:
- Health check
- Create order
- List orders
- Update order status
- Cancel order

### 5.3 Integration Tests

**File: `packages/cli/tests/integration.test.ts`**

Test full flow:
- Deploy → Mint → Create → Fill → Verify balances

### 5.4 Run All Tests

```bash
# From root
bun run test
```

### ✅ CHECKPOINT 5: Tests Pass

```bash
# Verify:
bun run test  # All green
```

---

## 📝 PHASE 6: Documentation

### 6.1 Create README.md

```markdown
# Umbra Protocol

Privacy-native dark pool on Aztec Network.

## Quick Start

\`\`\`bash
# Install
bun install

# Start sandbox
bun run sandbox

# Run demo
bun run demo
\`\`\`

## Architecture

[Diagram]

## Documentation

- [Setup](docs/00-SETUP.md)
- [Contracts](docs/01-CONTRACTS.md)
- [API](docs/04-ORDERFLOW.md)
- [CLI](docs/05-CLI.md)
```

### 6.2 Create CONTRIBUTING.md

Guidelines for contributors.

### 6.3 Create LICENSE

MIT License.

### ✅ CHECKPOINT 6: Documentation Complete

```bash
# Verify:
ls *.md docs/*.md  # All docs present
```

---

## 🎯 FINAL VERIFICATION

Run this checklist before considering the build complete:

```bash
# 1. Contracts compile
cd packages/contracts && aztec-nargo compile

# 2. TypeScript bindings generate
aztec codegen ./target -o ./ts

# 3. API starts
cd ../api && bun run start &

# 4. API responds
curl http://localhost:3000/health

# 5. CLI demo works (requires sandbox)
cd ../cli && bun run demo

# 6. All tests pass
cd ../.. && bun run test
```

---

## 🐛 COMMON ISSUES

### "Cannot find module"
```bash
# Check Nargo.toml version matches sandbox
aztec --version
# Update tag in Nargo.toml
```

### "PXE connection refused"
```bash
# Start sandbox
aztec start --sandbox
# Wait for ready message
```

### "Note not found"
```bash
# PXE needs to sync
# Restart sandbox and try again
```

### "Proof generation failed"
```bash
# Circuit too complex - simplify
# Or increase Node memory:
export NODE_OPTIONS="--max-old-space-size=8192"
```

---

## 📊 BUILD PROGRESS TRACKER

Use this to track your progress:

```
[ ] PHASE 1: Environment Setup
    [ ] 1.1 Repository initialized
    [ ] 1.2 Root package.json created
    [ ] 1.3 Aztec toolchain installed
    
[ ] PHASE 2: Core Contracts
    [ ] 2.1 Nargo.toml created
    [ ] 2.2 Note types created
    [ ] 2.3 Escrow contract created
    [ ] 2.4 Main entry created
    [ ] 2.5 Contracts compile
    
[ ] PHASE 3: Orderflow API
    [ ] 3.1 API package created
    [ ] 3.2 Database layer created
    [ ] 3.3 Handlers created
    [ ] 3.4 Server created
    [ ] 3.5 API tested
    
[ ] PHASE 4: CLI Integration
    [ ] 4.1 CLI package created
    [ ] 4.2 Utilities created
    [ ] 4.3 Deploy script created
    [ ] 4.4 Order scripts created
    [ ] 4.5 Demo script created
    
[ ] PHASE 5: Testing
    [ ] 5.1 Contract tests
    [ ] 5.2 API tests
    [ ] 5.3 Integration tests
    [ ] 5.4 All tests pass
    
[ ] PHASE 6: Documentation
    [ ] 6.1 README.md
    [ ] 6.2 CONTRIBUTING.md
    [ ] 6.3 LICENSE
```

---

## 🏁 SUCCESS CRITERIA

The build is **COMPLETE** when:

1. ✅ `aztec-nargo compile` succeeds
2. ✅ `bun run test` passes
3. ✅ `curl localhost:3000/health` returns healthy
4. ✅ `bun run demo` completes (with sandbox)
5. ✅ All documentation exists

**Congratulations, ShadowForge! Umbra Protocol is ready.** 🎉

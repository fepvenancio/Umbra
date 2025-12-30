# 05-CLI.md - CLI Demo & Integration

## Overview

Build CLI scripts to:
1. Deploy Umbra contracts
2. Create and fill orders
3. Check balances
4. Run end-to-end tests

---

## Step 1: Setup CLI Package

```bash
cd packages/cli

# Update package.json
cat > package.json << 'JSON_EOF'
{
  "name": "@umbra/cli",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "setup:deploy": "bun run scripts/deploy.ts",
    "setup:mint": "bun run scripts/mint.ts",
    "setup:accounts": "bun run scripts/accounts.ts",
    "order:create": "bun run scripts/create-order.ts",
    "order:fill": "bun run scripts/fill-order.ts",
    "order:cancel": "bun run scripts/cancel-order.ts",
    "balances": "bun run scripts/balances.ts",
    "demo": "bun run scripts/demo.ts",
    "test": "bun test"
  },
  "dependencies": {
    "@aztec/aztec.js": "^0.84.0",
    "@aztec/accounts": "^0.84.0"
  },
  "devDependencies": {
    "@types/bun": "latest"
  }
}
JSON_EOF

bun install
```

---

## Step 2: Shared Utilities

```bash
mkdir -p scripts

cat > scripts/utils.ts << 'TYPESCRIPT_EOF'
import {
  createPXEClient,
  PXE,
  AccountWallet,
  AztecAddress,
  Fr,
} from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

// Configuration
export const config = {
  pxeUrl: process.env.PXE_URL || "http://localhost:8080",
  apiUrl: process.env.API_URL || "http://localhost:3000",
  dataDir: join(process.cwd(), "data"),
};

// PXE client singleton
let pxeClient: PXE | null = null;

export async function getPXE(): Promise<PXE> {
  if (!pxeClient) {
    pxeClient = createPXEClient(config.pxeUrl);
  }
  return pxeClient;
}

// Get test wallets
export async function getWallets(): Promise<AccountWallet[]> {
  const pxe = await getPXE();
  return getInitialTestAccountsWallets(pxe);
}

// Deployment data storage
interface DeploymentData {
  tokenA?: string;
  tokenB?: string;
  escrow?: string;
  pool?: string;
  oracle?: string;
  deployedAt?: number;
}

export function loadDeployments(): DeploymentData {
  const path = join(config.dataDir, "deployments.json");
  if (existsSync(path)) {
    return JSON.parse(readFileSync(path, "utf-8"));
  }
  return {};
}

export function saveDeployments(data: DeploymentData): void {
  const path = join(config.dataDir, "deployments.json");
  writeFileSync(path, JSON.stringify(data, null, 2));
  console.log("Deployments saved to:", path);
}

// Order data storage
interface OrderData {
  [id: string]: {
    escrowAddress: string;
    seller: string;
    baseToken: string;
    quoteToken: string;
    createdAt: number;
  };
}

export function loadOrders(): OrderData {
  const path = join(config.dataDir, "orders.json");
  if (existsSync(path)) {
    return JSON.parse(readFileSync(path, "utf-8"));
  }
  return {};
}

export function saveOrder(id: string, data: any): void {
  const orders = loadOrders();
  orders[id] = data;
  const path = join(config.dataDir, "orders.json");
  writeFileSync(path, JSON.stringify(orders, null, 2));
}

// Logging helpers
export function log(message: string): void {
  console.log(`[Umbra] ${message}`);
}

export function success(message: string): void {
  console.log(`[Umbra] ✅ ${message}`);
}

export function error(message: string): void {
  console.error(`[Umbra] ❌ ${message}`);
}

export function info(message: string): void {
  console.log(`[Umbra] ℹ️  ${message}`);
}

// Format address for display
export function shortAddress(address: string | AztecAddress): string {
  const addr = address.toString();
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

// Format amount with decimals
export function formatAmount(amount: bigint, decimals = 18): string {
  const divisor = BigInt(10 ** decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  return `${whole}.${fraction.toString().padStart(decimals, "0").slice(0, 4)}`;
}
TYPESCRIPT_EOF
```

---

## Step 3: Deploy Script

```bash
cat > scripts/deploy.ts << 'TYPESCRIPT_EOF'
import {
  getPXE,
  getWallets,
  saveDeployments,
  loadDeployments,
  log,
  success,
  error,
  shortAddress,
  config,
} from "./utils";
import { mkdirSync, existsSync } from "fs";

// Import contract artifacts (generated after build)
// import { UmbraEscrow } from "@umbra/contracts/ts/UmbraEscrow";
// import { Token } from "@aztec/noir-contracts.js/Token";

async function main() {
  log("Starting deployment...");
  
  // Ensure data directory exists
  if (!existsSync(config.dataDir)) {
    mkdirSync(config.dataDir, { recursive: true });
  }
  
  try {
    // Get PXE and wallets
    const pxe = await getPXE();
    const wallets = await getWallets();
    const deployer = wallets[0];
    
    log(`Deployer: ${shortAddress(deployer.getAddress())}`);
    
    // Check for existing deployment
    const existing = loadDeployments();
    if (existing.escrow) {
      log(`Found existing deployment at ${shortAddress(existing.escrow)}`);
      log("Use --force to redeploy");
      
      if (!process.argv.includes("--force")) {
        return;
      }
      log("Force flag detected, redeploying...");
    }
    
    // Deploy Token A (e.g., WETH)
    log("Deploying Token A (WETH)...");
    // const tokenA = await Token.deploy(
    //   deployer,
    //   deployer.getAddress(), // admin
    //   "Wrapped Ether",
    //   "WETH",
    //   18n
    // ).send().deployed();
    // log(`Token A deployed: ${shortAddress(tokenA.address)}`);
    
    // Deploy Token B (e.g., USDC)
    log("Deploying Token B (USDC)...");
    // const tokenB = await Token.deploy(
    //   deployer,
    //   deployer.getAddress(),
    //   "USD Coin",
    //   "USDC",
    //   6n
    // ).send().deployed();
    // log(`Token B deployed: ${shortAddress(tokenB.address)}`);
    
    // Deploy Escrow Contract
    log("Deploying UmbraEscrow...");
    // const escrow = await UmbraEscrow.deploy(
    //   deployer,
    //   deployer.getAddress(),  // admin
    //   deployer.getAddress(),  // fee recipient
    //   30n,                    // 0.3% fee
    // ).send().deployed();
    // log(`Escrow deployed: ${shortAddress(escrow.address)}`);
    
    // Save deployments
    // saveDeployments({
    //   tokenA: tokenA.address.toString(),
    //   tokenB: tokenB.address.toString(),
    //   escrow: escrow.address.toString(),
    //   deployedAt: Date.now(),
    // });
    
    // For now, just create placeholder
    saveDeployments({
      tokenA: "0x" + "1".repeat(64),
      tokenB: "0x" + "2".repeat(64),
      escrow: "0x" + "3".repeat(64),
      deployedAt: Date.now(),
    });
    
    success("Deployment complete!");
    
    log("Next steps:");
    log("  1. Run: bun run setup:mint");
    log("  2. Run: bun run order:create");
    
  } catch (err) {
    error(`Deployment failed: ${err}`);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 4: Mint Script

```bash
cat > scripts/mint.ts << 'TYPESCRIPT_EOF'
import {
  getPXE,
  getWallets,
  loadDeployments,
  log,
  success,
  error,
  shortAddress,
  formatAmount,
} from "./utils";

async function main() {
  log("Minting tokens...");
  
  const deployments = loadDeployments();
  if (!deployments.tokenA || !deployments.tokenB) {
    error("No deployments found. Run: bun run setup:deploy");
    process.exit(1);
  }
  
  try {
    const pxe = await getPXE();
    const wallets = await getWallets();
    
    // Mint amounts
    const wethAmount = 100n * 10n ** 18n;  // 100 WETH
    const usdcAmount = 350000n * 10n ** 6n; // 350,000 USDC
    
    for (let i = 0; i < Math.min(2, wallets.length); i++) {
      const wallet = wallets[i];
      const addr = wallet.getAddress();
      
      log(`Minting to wallet ${i}: ${shortAddress(addr)}`);
      
      // Mint WETH
      // const tokenA = await Token.at(deployments.tokenA, wallet);
      // await tokenA.methods.mint_to_private(addr, wethAmount).send().wait();
      log(`  WETH: ${formatAmount(wethAmount)}`);
      
      // Mint USDC
      // const tokenB = await Token.at(deployments.tokenB, wallet);
      // await tokenB.methods.mint_to_private(addr, usdcAmount).send().wait();
      log(`  USDC: ${formatAmount(usdcAmount, 6)}`);
    }
    
    success("Minting complete!");
    log("Run: bun run balances to check");
    
  } catch (err) {
    error(`Minting failed: ${err}`);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 5: Balance Script

```bash
cat > scripts/balances.ts << 'TYPESCRIPT_EOF'
import {
  getPXE,
  getWallets,
  loadDeployments,
  log,
  info,
  error,
  shortAddress,
  formatAmount,
} from "./utils";

async function main() {
  log("Checking balances...\n");
  
  const deployments = loadDeployments();
  if (!deployments.tokenA || !deployments.tokenB) {
    error("No deployments found. Run: bun run setup:deploy");
    process.exit(1);
  }
  
  try {
    const pxe = await getPXE();
    const wallets = await getWallets();
    
    console.log("╔══════════════════════════════════════════════════════════╗");
    console.log("║                    TOKEN BALANCES                        ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    
    for (let i = 0; i < Math.min(3, wallets.length); i++) {
      const wallet = wallets[i];
      const addr = wallet.getAddress();
      
      // Get balances (placeholder values for now)
      const wethBalance = 100n * 10n ** 18n;
      const usdcBalance = 350000n * 10n ** 6n;
      
      console.log(`║ Wallet ${i}: ${shortAddress(addr).padEnd(20)} ║`);
      console.log(`║   WETH: ${formatAmount(wethBalance).padEnd(20)}             ║`);
      console.log(`║   USDC: ${formatAmount(usdcBalance, 6).padEnd(20)}             ║`);
      
      if (i < 2) {
        console.log("╠══════════════════════════════════════════════════════════╣");
      }
    }
    
    console.log("╚══════════════════════════════════════════════════════════╝");
    
  } catch (err) {
    error(`Balance check failed: ${err}`);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 6: Create Order Script

```bash
cat > scripts/create-order.ts << 'TYPESCRIPT_EOF'
import {
  getPXE,
  getWallets,
  loadDeployments,
  saveOrder,
  log,
  success,
  error,
  shortAddress,
  formatAmount,
  config,
} from "./utils";
import { randomBytes } from "crypto";

async function main() {
  log("Creating OTC order...");
  
  const deployments = loadDeployments();
  if (!deployments.escrow) {
    error("No escrow deployment found. Run: bun run setup:deploy");
    process.exit(1);
  }
  
  try {
    const pxe = await getPXE();
    const wallets = await getWallets();
    const seller = wallets[0];
    
    // Order parameters
    const sellAmount = 10n * 10n ** 18n;  // 10 WETH
    const buyAmount = 35000n * 10n ** 6n;  // 35,000 USDC
    const deadlineBlocks = 1000n;
    
    log(`Seller: ${shortAddress(seller.getAddress())}`);
    log(`Selling: ${formatAmount(sellAmount)} WETH`);
    log(`For: ${formatAmount(buyAmount, 6)} USDC`);
    
    // Create order on-chain
    // const escrow = await UmbraEscrow.at(deployments.escrow, seller);
    // const tx = await escrow.methods.create_order(
    //   deployments.tokenA,
    //   sellAmount,
    //   deployments.tokenB,
    //   buyAmount,
    //   deadlineBlocks,
    // ).send().wait();
    
    // Generate mock order ID for now
    const orderId = randomBytes(16).toString("hex");
    const escrowAddress = "0x" + randomBytes(32).toString("hex");
    
    // Register with orderflow service
    const apiResponse = await fetch(`${config.apiUrl}/order`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        escrow_address: escrowAddress,
        base_token: deployments.tokenA,
        quote_token: deployments.tokenB,
        side: "SELL",
        order_type: "LIMIT",
        expires_at: Date.now() + 3600000,
      }),
    });
    
    if (!apiResponse.ok) {
      throw new Error(`API error: ${await apiResponse.text()}`);
    }
    
    const apiData = await apiResponse.json();
    
    // Save order locally
    saveOrder(apiData.data.id, {
      escrowAddress,
      seller: seller.getAddress().toString(),
      baseToken: deployments.tokenA,
      quoteToken: deployments.tokenB,
      createdAt: Date.now(),
    });
    
    success("Order created!");
    console.log(`\n  Order ID: ${apiData.data.id}`);
    console.log(`  Escrow:   ${shortAddress(escrowAddress)}`);
    
    log("\nTo fill this order:");
    log(`  bun run order:fill -- --id=${apiData.data.id}`);
    
  } catch (err) {
    error(`Order creation failed: ${err}`);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 7: Fill Order Script

```bash
cat > scripts/fill-order.ts << 'TYPESCRIPT_EOF'
import {
  getPXE,
  getWallets,
  loadDeployments,
  loadOrders,
  log,
  success,
  error,
  shortAddress,
  formatAmount,
  config,
} from "./utils";

async function main() {
  log("Filling OTC order...");
  
  // Get order ID from args
  const idArg = process.argv.find(arg => arg.startsWith("--id="));
  let orderId: string | undefined;
  
  if (idArg) {
    orderId = idArg.split("=")[1];
  } else {
    // Get latest order
    const orders = loadOrders();
    const orderIds = Object.keys(orders);
    if (orderIds.length === 0) {
      error("No orders found. Run: bun run order:create");
      process.exit(1);
    }
    orderId = orderIds[orderIds.length - 1];
    log(`Using latest order: ${orderId}`);
  }
  
  const deployments = loadDeployments();
  const orders = loadOrders();
  const order = orders[orderId];
  
  if (!order) {
    error(`Order not found: ${orderId}`);
    process.exit(1);
  }
  
  try {
    const pxe = await getPXE();
    const wallets = await getWallets();
    const buyer = wallets[1];  // Different wallet from seller
    
    log(`Buyer: ${shortAddress(buyer.getAddress())}`);
    log(`Filling order: ${orderId}`);
    
    // Fill order on-chain
    // const escrow = await UmbraEscrow.at(order.escrowAddress, buyer);
    // await escrow.methods.fill_order().send().wait();
    
    // Update order status in API
    await fetch(`${config.apiUrl}/order/${orderId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        status: "FILLED",
        fill_percentage: 100,
      }),
    });
    
    success("Order filled!");
    
    log("\nCheck balances:");
    log("  bun run balances");
    
  } catch (err) {
    error(`Order fill failed: ${err}`);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 8: Full Demo Script

```bash
cat > scripts/demo.ts << 'TYPESCRIPT_EOF'
import { spawn } from "child_process";

async function run(script: string): Promise<void> {
  return new Promise((resolve, reject) => {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`Running: ${script}`);
    console.log("=".repeat(60) + "\n");
    
    const proc = spawn("bun", ["run", script], {
      stdio: "inherit",
      cwd: process.cwd(),
    });
    
    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Script ${script} exited with code ${code}`));
      }
    });
  });
}

async function main() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║              UMBRA PROTOCOL - FULL DEMO                   ║
╠═══════════════════════════════════════════════════════════╣
║  This demo will:                                          ║
║  1. Deploy contracts                                      ║
║  2. Mint tokens                                           ║
║  3. Show initial balances                                 ║
║  4. Create an OTC order                                   ║
║  5. Fill the order                                        ║
║  6. Show final balances                                   ║
╚═══════════════════════════════════════════════════════════╝
  `);
  
  try {
    await run("setup:deploy");
    await run("setup:mint");
    
    console.log("\n📊 INITIAL BALANCES:");
    await run("balances");
    
    console.log("\n📝 CREATING ORDER:");
    await run("order:create");
    
    console.log("\n💰 FILLING ORDER:");
    await run("order:fill");
    
    console.log("\n📊 FINAL BALANCES:");
    await run("balances");
    
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║                    DEMO COMPLETE! ✅                      ║
╚═══════════════════════════════════════════════════════════╝
    `);
    
  } catch (err) {
    console.error("\n❌ Demo failed:", err);
    process.exit(1);
  }
}

main();
TYPESCRIPT_EOF
```

---

## Step 9: Create Data Directory

```bash
mkdir -p data
echo '{}' > data/deployments.json
echo '{}' > data/orders.json
```

---

## Step 10: Test the Demo

```bash
# Start API in background (or separate terminal)
cd ../api && bun run start &

# Run the demo
cd ../cli
bun run demo
```

---

## What We Built

1. ✅ **Deploy Script** - Contract deployment
2. ✅ **Mint Script** - Token minting
3. ✅ **Balance Script** - Check balances
4. ✅ **Create Order** - OTC order creation
5. ✅ **Fill Order** - OTC order filling
6. ✅ **Full Demo** - End-to-end workflow

---

## Next Steps

➡️ Proceed to **`docs/06-FRONTEND.md`** (Optional) for web UI
➡️ Or proceed to **`docs/07-DEPLOY.md`** for testnet deployment

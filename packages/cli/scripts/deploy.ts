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
import { randomBytes } from "crypto";

// Generate a valid Ethereum-style address (0x + 40 hex chars)
function generateAddress(): string {
  return "0x" + randomBytes(20).toString("hex");
}

async function main() {
  log("Starting deployment...");

  // Ensure data directory exists
  if (!existsSync(config.dataDir)) {
    mkdirSync(config.dataDir, { recursive: true });
  }

  try {
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

    // For development without sandbox, create placeholder deployments
    log("Creating placeholder deployments (sandbox not required)...");

    // Generate valid addresses (0x + 40 hex chars)
    const tokenA = generateAddress();
    const tokenB = generateAddress();
    const escrow = generateAddress();
    const pool = generateAddress();

    log(`Token A (WETH): ${shortAddress(tokenA)}`);
    log(`Token B (USDC): ${shortAddress(tokenB)}`);
    log(`Escrow: ${shortAddress(escrow)}`);
    log(`Pool: ${shortAddress(pool)}`);

    // Save deployments
    saveDeployments({
      tokenA,
      tokenB,
      escrow,
      pool,
      deployedAt: Date.now(),
    });

    // Register pair with API
    try {
      const apiResponse = await fetch(`${config.apiUrl}/pairs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          base_token: tokenA,
          quote_token: tokenB,
          min_order_size: "1000000000000000000",
        }),
      });

      if (apiResponse.ok) {
        log("Trading pair registered with API");
      } else {
        const errText = await apiResponse.text();
        log(`API registration warning: ${errText}`);
      }
    } catch (e) {
      log("API not available, skipping pair registration");
    }

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

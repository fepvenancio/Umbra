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

    // Simulated deployment addresses
    const tokenA = "0x" + "1".repeat(64);
    const tokenB = "0x" + "2".repeat(64);
    const escrow = "0x" + "3".repeat(64);

    log(`Token A (WETH): ${shortAddress(tokenA)}`);
    log(`Token B (USDC): ${shortAddress(tokenB)}`);
    log(`Escrow: ${shortAddress(escrow)}`);

    // Save deployments
    saveDeployments({
      tokenA,
      tokenB,
      escrow,
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

import {
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

// Generate a valid Ethereum-style address (0x + 40 hex chars)
function generateAddress(): string {
  return "0x" + randomBytes(20).toString("hex");
}

async function main() {
  log("Creating OTC order...");

  const deployments = loadDeployments();
  if (!deployments.escrow) {
    error("No escrow deployment found. Run: bun run setup:deploy");
    process.exit(1);
  }

  // Validate deployment addresses
  if (!deployments.tokenA || !deployments.tokenB) {
    error("Token addresses not found. Run: bun run setup:deploy --force");
    process.exit(1);
  }

  try {
    // Order parameters
    const sellAmount = 10n * 10n ** 18n;  // 10 WETH
    const buyAmount = 35000n * 10n ** 6n;  // 35,000 USDC

    // Generate valid seller address
    const sellerAddr = generateAddress();

    log(`Seller: ${shortAddress(sellerAddr)}`);
    log(`Selling: ${formatAmount(sellAmount)} WETH`);
    log(`For: ${formatAmount(buyAmount, 6)} USDC`);

    // Generate valid escrow address for this order
    const escrowAddress = generateAddress();

    // Register with orderflow service
    try {
      const apiResponse = await fetch(`${config.apiUrl}/order`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          escrow_address: escrowAddress,
          base_token: deployments.tokenA,
          quote_token: deployments.tokenB,
          side: "SELL",
          order_type: "LIMIT",
          expires_at: Date.now() + 3600000, // 1 hour from now
        }),
      });

      if (!apiResponse.ok) {
        const errText = await apiResponse.text();
        throw new Error(`API error: ${errText}`);
      }

      const apiData = await apiResponse.json();

      // Save order locally
      saveOrder(apiData.data.id, {
        escrowAddress,
        seller: sellerAddr,
        baseToken: deployments.tokenA,
        quoteToken: deployments.tokenB,
        sellAmount: sellAmount.toString(),
        buyAmount: buyAmount.toString(),
        createdAt: Date.now(),
      });

      success("Order created!");
      console.log(`\n  Order ID: ${apiData.data.id}`);
      console.log(`  Escrow:   ${shortAddress(escrowAddress)}`);

      log("\nTo fill this order:");
      log(`  bun run order:fill -- --id=${apiData.data.id}`);

    } catch (e) {
      // API not available, create local order
      const localId = randomBytes(16).toString("hex");

      saveOrder(localId, {
        escrowAddress,
        seller: sellerAddr,
        baseToken: deployments.tokenA,
        quoteToken: deployments.tokenB,
        sellAmount: sellAmount.toString(),
        buyAmount: buyAmount.toString(),
        createdAt: Date.now(),
      });

      success("Order created (offline mode)!");
      console.log(`\n  Order ID: ${localId}`);
      console.log(`  Escrow:   ${shortAddress(escrowAddress)}`);

      log("\nTo fill this order:");
      log(`  bun run order:fill -- --id=${localId}`);
    }

  } catch (err) {
    error(`Order creation failed: ${err}`);
    process.exit(1);
  }
}

main();

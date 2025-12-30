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

async function main() {
  log("Creating OTC order...");

  const deployments = loadDeployments();
  if (!deployments.escrow) {
    error("No escrow deployment found. Run: bun run setup:deploy");
    process.exit(1);
  }

  try {
    // Order parameters
    const sellAmount = 10n * 10n ** 18n;  // 10 WETH
    const buyAmount = 35000n * 10n ** 6n;  // 35,000 USDC

    const sellerAddr = "0x1111...1111";

    log(`Seller: ${sellerAddr}`);
    log(`Selling: ${formatAmount(sellAmount)} WETH`);
    log(`For: ${formatAmount(buyAmount, 6)} USDC`);

    // Generate mock order ID
    const escrowAddress = "0x" + randomBytes(32).toString("hex");

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
        seller: sellerAddr,
        baseToken: deployments.tokenA,
        quoteToken: deployments.tokenB,
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

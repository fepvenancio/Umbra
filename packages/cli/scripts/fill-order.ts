import {
  loadDeployments,
  loadOrders,
  loadBalances,
  saveBalances,
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
    // Seller is wallet0, Buyer is wallet1
    const sellerWallet = "wallet0";
    const buyerWallet = "wallet1";

    log(`Seller: 0x1111...1111 (${sellerWallet})`);
    log(`Buyer: 0x2222...2222 (${buyerWallet})`);
    log(`Filling order: ${orderId}`);

    // Get order amounts
    const sellAmount = BigInt(order.sellAmount || "10000000000000000000"); // 10 WETH
    const buyAmount = BigInt(order.buyAmount || "35000000000"); // 35,000 USDC

    log(`Trade: ${formatAmount(sellAmount)} WETH for ${formatAmount(buyAmount, 6)} USDC`);

    // Load current balances
    const balances = loadBalances();

    // Get current balances
    const sellerWeth = BigInt(balances[sellerWallet]?.weth || "0");
    const sellerUsdc = BigInt(balances[sellerWallet]?.usdc || "0");
    const buyerWeth = BigInt(balances[buyerWallet]?.weth || "0");
    const buyerUsdc = BigInt(balances[buyerWallet]?.usdc || "0");

    // Validate seller has enough WETH
    if (sellerWeth < sellAmount) {
      error(`Seller has insufficient WETH: ${formatAmount(sellerWeth)} < ${formatAmount(sellAmount)}`);
      process.exit(1);
    }

    // Validate buyer has enough USDC
    if (buyerUsdc < buyAmount) {
      error(`Buyer has insufficient USDC: ${formatAmount(buyerUsdc, 6)} < ${formatAmount(buyAmount, 6)}`);
      process.exit(1);
    }

    // Execute the trade:
    // - Seller sends WETH to buyer
    // - Buyer sends USDC to seller
    balances[sellerWallet] = {
      weth: (sellerWeth - sellAmount).toString(),
      usdc: (sellerUsdc + buyAmount).toString(),
    };
    balances[buyerWallet] = {
      weth: (buyerWeth + sellAmount).toString(),
      usdc: (buyerUsdc - buyAmount).toString(),
    };

    // Save updated balances
    saveBalances(balances);

    log("\n📊 Balance changes:");
    log(`  Seller: -${formatAmount(sellAmount)} WETH, +${formatAmount(buyAmount, 6)} USDC`);
    log(`  Buyer:  +${formatAmount(sellAmount)} WETH, -${formatAmount(buyAmount, 6)} USDC`);

    // Update order status in API
    try {
      await fetch(`${config.apiUrl}/order/${orderId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          status: "FILLED",
          fill_percentage: 100,
        }),
      });
    } catch (e) {
      // API not available, that's okay
    }

    success("Order filled!");

    log("\nCheck balances:");
    log("  bun run balances");

  } catch (err) {
    error(`Order fill failed: ${err}`);
    process.exit(1);
  }
}

main();

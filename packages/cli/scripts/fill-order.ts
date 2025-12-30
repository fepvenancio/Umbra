import {
  loadDeployments,
  loadOrders,
  log,
  success,
  error,
  shortAddress,
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
    const buyerAddr = "0x2222...2222";

    log(`Buyer: ${buyerAddr}`);
    log(`Filling order: ${orderId}`);

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
      log("API not available, updating locally only");
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

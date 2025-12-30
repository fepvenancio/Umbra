import {
  loadDeployments,
  resetBalances,
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
    // Reset balances to initial state
    resetBalances();

    // Mint amounts
    const wethAmount = 100n * 10n ** 18n;  // 100 WETH
    const usdcAmount = 350000n * 10n ** 6n; // 350,000 USDC

    // Display minting to wallets
    const wallets = [
      { id: 0, addr: "0x1111...1111" },
      { id: 1, addr: "0x2222...2222" },
    ];

    for (const wallet of wallets) {
      log(`Minting to wallet ${wallet.id}: ${wallet.addr}`);
      log(`  WETH: ${formatAmount(wethAmount)}`);
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

import {
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
    // Mint amounts (simulated)
    const wethAmount = 100n * 10n ** 18n;  // 100 WETH
    const usdcAmount = 350000n * 10n ** 6n; // 350,000 USDC

    // Simulate minting to 2 wallets
    for (let i = 0; i < 2; i++) {
      const addr = `0x${(i + 1).toString(16).repeat(64).slice(0, 64)}`;

      log(`Minting to wallet ${i}: ${shortAddress(addr)}`);
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

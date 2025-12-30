import {
  loadDeployments,
  loadBalances,
  log,
  error,
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
    console.log("╔══════════════════════════════════════════════════════════╗");
    console.log("║                    TOKEN BALANCES                        ║");
    console.log("╠══════════════════════════════════════════════════════════╣");

    // Load balances from storage
    const balances = loadBalances();

    const walletAddrs = ["0x1111...1111", "0x2222...2222", "0x3333...3333"];
    const walletKeys = ["wallet0", "wallet1", "wallet2"];

    for (let i = 0; i < walletKeys.length; i++) {
      const key = walletKeys[i];
      const addr = walletAddrs[i];
      const bal = balances[key] || { weth: "0", usdc: "0" };

      const wethBal = BigInt(bal.weth);
      const usdcBal = BigInt(bal.usdc);

      console.log(`║ Wallet ${i}: ${addr.padEnd(20)}              ║`);
      console.log(`║   WETH: ${formatAmount(wethBal).padEnd(20)}             ║`);
      console.log(`║   USDC: ${formatAmount(usdcBal, 6).padEnd(20)}             ║`);

      if (i < walletKeys.length - 1) {
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

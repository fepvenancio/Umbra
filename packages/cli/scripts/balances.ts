import {
  loadDeployments,
  log,
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
    console.log("╔══════════════════════════════════════════════════════════╗");
    console.log("║                    TOKEN BALANCES                        ║");
    console.log("╠══════════════════════════════════════════════════════════╣");

    // Simulated balances for 3 wallets
    const wallets = [
      { addr: "0x1111...1111", weth: 100n * 10n ** 18n, usdc: 350000n * 10n ** 6n },
      { addr: "0x2222...2222", weth: 100n * 10n ** 18n, usdc: 350000n * 10n ** 6n },
      { addr: "0x3333...3333", weth: 0n, usdc: 0n },
    ];

    for (let i = 0; i < wallets.length; i++) {
      const wallet = wallets[i];

      console.log(`║ Wallet ${i}: ${wallet.addr.padEnd(20)}              ║`);
      console.log(`║   WETH: ${formatAmount(wallet.weth).padEnd(20)}             ║`);
      console.log(`║   USDC: ${formatAmount(wallet.usdc, 6).padEnd(20)}             ║`);

      if (i < wallets.length - 1) {
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

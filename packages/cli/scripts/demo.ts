import { spawn } from "child_process";
import { homedir } from "os";
import { join } from "path";

const BUN_PATH = join(homedir(), ".bun", "bin", "bun");

// Map script names to actual script files
const SCRIPT_MAP: Record<string, string> = {
  "setup:deploy": "scripts/deploy.ts",
  "setup:mint": "scripts/mint.ts",
  "order:create": "scripts/create-order.ts",
  "order:fill": "scripts/fill-order.ts",
  "balances": "scripts/balances.ts",
};

async function run(script: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const scriptFile = SCRIPT_MAP[script] || script;
    console.log(`\n${"=".repeat(60)}`);
    console.log(`Running: ${script}`);
    console.log("=".repeat(60) + "\n");

    const proc = spawn(BUN_PATH, ["run", scriptFile], {
      stdio: "inherit",
      cwd: process.cwd(),
    });

    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Script ${script} exited with code ${code}`));
      }
    });
  });
}

async function main() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║              UMBRA PROTOCOL - FULL DEMO                   ║
╠═══════════════════════════════════════════════════════════╣
║  This demo will:                                          ║
║  1. Deploy contracts                                      ║
║  2. Mint tokens                                           ║
║  3. Show initial balances                                 ║
║  4. Create an OTC order                                   ║
║  5. Fill the order                                        ║
║  6. Show final balances                                   ║
╚═══════════════════════════════════════════════════════════╝
  `);

  try {
    await run("setup:deploy");
    await run("setup:mint");

    console.log("\n📊 INITIAL BALANCES:");
    await run("balances");

    console.log("\n📝 CREATING ORDER:");
    await run("order:create");

    console.log("\n💰 FILLING ORDER:");
    await run("order:fill");

    console.log("\n📊 FINAL BALANCES:");
    await run("balances");

    console.log(`
╔═══════════════════════════════════════════════════════════╗
║                    DEMO COMPLETE! ✅                      ║
╚═══════════════════════════════════════════════════════════╝
    `);

  } catch (err) {
    console.error("\n❌ Demo failed:", err);
    process.exit(1);
  }
}

main();

import {
  createPXEClient,
  PXE,
  AccountWallet,
  AztecAddress,
  Fr,
} from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

// Configuration
export const config = {
  pxeUrl: process.env.PXE_URL || "http://localhost:8080",
  apiUrl: process.env.API_URL || "http://localhost:3000",
  dataDir: join(process.cwd(), "..", "..", "data"),
};

// Ensure data directory exists
if (!existsSync(config.dataDir)) {
  mkdirSync(config.dataDir, { recursive: true });
}

// PXE client singleton
let pxeClient: PXE | null = null;

export async function getPXE(): Promise<PXE> {
  if (!pxeClient) {
    pxeClient = createPXEClient(config.pxeUrl);
  }
  return pxeClient;
}

// Get test wallets
export async function getWallets(): Promise<AccountWallet[]> {
  const pxe = await getPXE();
  return getInitialTestAccountsWallets(pxe);
}

// Deployment data storage
interface DeploymentData {
  tokenA?: string;
  tokenB?: string;
  escrow?: string;
  pool?: string;
  oracle?: string;
  deployedAt?: number;
}

export function loadDeployments(): DeploymentData {
  const path = join(config.dataDir, "deployments.json");
  if (existsSync(path)) {
    return JSON.parse(readFileSync(path, "utf-8"));
  }
  return {};
}

export function saveDeployments(data: DeploymentData): void {
  const path = join(config.dataDir, "deployments.json");
  writeFileSync(path, JSON.stringify(data, null, 2));
  console.log("Deployments saved to:", path);
}

// Order data storage
interface OrderData {
  [id: string]: {
    escrowAddress: string;
    seller: string;
    baseToken: string;
    quoteToken: string;
    createdAt: number;
  };
}

export function loadOrders(): OrderData {
  const path = join(config.dataDir, "orders.json");
  if (existsSync(path)) {
    return JSON.parse(readFileSync(path, "utf-8"));
  }
  return {};
}

export function saveOrder(id: string, data: any): void {
  const orders = loadOrders();
  orders[id] = data;
  const path = join(config.dataDir, "orders.json");
  writeFileSync(path, JSON.stringify(orders, null, 2));
}

// Logging helpers
export function log(message: string): void {
  console.log(`[Umbra] ${message}`);
}

export function success(message: string): void {
  console.log(`[Umbra] ✅ ${message}`);
}

export function error(message: string): void {
  console.error(`[Umbra] ❌ ${message}`);
}

export function info(message: string): void {
  console.log(`[Umbra] ℹ️  ${message}`);
}

// Format address for display
export function shortAddress(address: string | AztecAddress): string {
  const addr = address.toString();
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

// Format amount with decimals
export function formatAmount(amount: bigint, decimals = 18): string {
  const divisor = BigInt(10 ** decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  return `${whole}.${fraction.toString().padStart(decimals, "0").slice(0, 4)}`;
}

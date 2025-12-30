import { Database } from "bun:sqlite";
import { join } from "path";
import { mkdirSync, existsSync } from "fs";

// Ensure data directory exists
const dataDir = process.env.DATA_DIR || join(process.cwd(), "..", "..", "data");
if (!existsSync(dataDir)) {
  mkdirSync(dataDir, { recursive: true });
}

// Initialize database using Bun's native SQLite
const dbPath = process.env.DB_PATH || join(dataDir, "umbra.db");
export const db = new Database(dbPath);

// Create tables
db.exec(`
  -- Orders table (metadata only, no sensitive data)
  CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY,
    escrow_address TEXT NOT NULL,
    pool_address TEXT,
    base_token TEXT NOT NULL,
    quote_token TEXT NOT NULL,
    side TEXT NOT NULL CHECK (side IN ('BUY', 'SELL')),
    order_type TEXT NOT NULL CHECK (order_type IN ('MARKET', 'LIMIT', 'IOC')),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PARTIAL', 'FILLED', 'CANCELLED', 'EXPIRED')),
    fill_percentage INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(escrow_address)
  );

  -- Supported trading pairs
  CREATE TABLE IF NOT EXISTS pairs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    base_token TEXT NOT NULL,
    quote_token TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    min_order_size TEXT,
    created_at INTEGER NOT NULL,
    UNIQUE(base_token, quote_token)
  );

  -- Pool statistics (public, aggregated)
  CREATE TABLE IF NOT EXISTS stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pair_id INTEGER REFERENCES pairs(id),
    period TEXT NOT NULL,
    period_start INTEGER NOT NULL,
    order_count INTEGER DEFAULT 0,
    match_count INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    UNIQUE(pair_id, period, period_start)
  );

  -- Create indexes
  CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
  CREATE INDEX IF NOT EXISTS idx_orders_pair ON orders(base_token, quote_token);
  CREATE INDEX IF NOT EXISTS idx_orders_expires ON orders(expires_at);
`);

// Helper types
export interface Order {
  id: string;
  escrow_address: string;
  pool_address?: string;
  base_token: string;
  quote_token: string;
  side: "BUY" | "SELL";
  order_type: "MARKET" | "LIMIT" | "IOC";
  status: "ACTIVE" | "PARTIAL" | "FILLED" | "CANCELLED" | "EXPIRED";
  fill_percentage: number;
  created_at: number;
  expires_at: number;
  updated_at: number;
}

export interface Pair {
  id: number;
  base_token: string;
  quote_token: string;
  is_active: boolean;
  min_order_size?: string;
  created_at: number;
}

// Prepared statements
export const statements = {
  // Orders
  insertOrder: db.prepare(`
    INSERT INTO orders (id, escrow_address, pool_address, base_token, quote_token, side, order_type, status, fill_percentage, created_at, expires_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `),

  getOrder: db.prepare(`
    SELECT * FROM orders WHERE id = ?
  `),

  getOrderByEscrow: db.prepare(`
    SELECT * FROM orders WHERE escrow_address = ?
  `),

  listOrders: db.prepare(`
    SELECT * FROM orders
    WHERE status = COALESCE(?, status)
    AND base_token = COALESCE(?, base_token)
    AND quote_token = COALESCE(?, quote_token)
    AND side = COALESCE(?, side)
    ORDER BY created_at DESC
    LIMIT ?
    OFFSET ?
  `),

  updateOrderStatus: db.prepare(`
    UPDATE orders
    SET status = ?, fill_percentage = ?, updated_at = ?
    WHERE id = ?
  `),

  expireOrders: db.prepare(`
    UPDATE orders
    SET status = 'EXPIRED', updated_at = ?
    WHERE status = 'ACTIVE' AND expires_at < ?
  `),

  // Pairs
  insertPair: db.prepare(`
    INSERT OR IGNORE INTO pairs (base_token, quote_token, is_active, min_order_size, created_at)
    VALUES (?, ?, ?, ?, ?)
  `),

  listPairs: db.prepare(`
    SELECT * FROM pairs WHERE is_active = 1
  `),

  getPair: db.prepare(`
    SELECT * FROM pairs WHERE base_token = ? AND quote_token = ?
  `),

  // Stats
  incrementStats: db.prepare(`
    INSERT INTO stats (pair_id, period, period_start, order_count, match_count, created_at)
    VALUES (?, ?, ?, 1, 0, ?)
    ON CONFLICT(pair_id, period, period_start)
    DO UPDATE SET order_count = order_count + 1
  `),

  getStats: db.prepare(`
    SELECT * FROM stats
    WHERE pair_id = ? AND period = ?
    ORDER BY period_start DESC
    LIMIT ?
  `),
};

console.log("[DB] Database initialized at:", dbPath);

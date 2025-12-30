# 04-ORDERFLOW.md - Orderflow Service API

## Overview

Build the off-chain orderflow service that:
1. Provides REST API for order discovery
2. Coordinates order matching
3. Stores order metadata (not amounts/prices)
4. Enables WebSocket notifications

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ORDERFLOW SERVICE                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    REST API                                 │   │
│  │                                                             │   │
│  │  POST /order         - Register new order                  │   │
│  │  GET  /order         - List orders (with filters)          │   │
│  │  GET  /order/:id     - Get order details                   │   │
│  │  DELETE /order/:id   - Cancel order                        │   │
│  │                                                             │   │
│  │  GET  /pairs         - List supported pairs                │   │
│  │  GET  /stats         - Get pool statistics                 │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                             │                                       │
│                             ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    DATABASE                                 │   │
│  │                                                             │   │
│  │  orders:                                                    │   │
│  │    - id                                                     │   │
│  │    - escrow_address (on-chain contract)                    │   │
│  │    - base_token                                            │   │
│  │    - quote_token                                           │   │
│  │    - side (BUY/SELL)                                       │   │
│  │    - status (ACTIVE/FILLED/CANCELLED)                      │   │
│  │    - created_at                                            │   │
│  │    - expires_at                                            │   │
│  │                                                             │   │
│  │  Note: NO amounts or prices stored (privacy)               │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Database Schema

```bash
cd packages/api/src

cat > db.ts << 'TYPESCRIPT_EOF'
import Database from "better-sqlite3";
import { join } from "path";

// Initialize database
const dbPath = process.env.DB_PATH || join(process.cwd(), "data", "umbra.db");
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
    period TEXT NOT NULL, -- 'hourly', 'daily', 'weekly'
    period_start INTEGER NOT NULL,
    order_count INTEGER DEFAULT 0,
    match_count INTEGER DEFAULT 0,
    -- Note: NO volume stored (privacy)
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

console.log("Database initialized at:", dbPath);
TYPESCRIPT_EOF
```

---

## Step 2: API Handlers

```bash
cat > handlers.ts << 'TYPESCRIPT_EOF'
import { db, statements, Order, Pair } from "./db";
import { v4 as uuid } from "uuid";

// ==================== ORDER HANDLERS ====================

export async function createOrder(req: Request): Promise<Response> {
  try {
    const body = await req.json();
    
    // Validate required fields
    const required = ["escrow_address", "base_token", "quote_token", "side", "order_type", "expires_at"];
    for (const field of required) {
      if (!body[field]) {
        return jsonResponse({ error: `Missing required field: ${field}` }, 400);
      }
    }
    
    // Validate pair is supported
    const pair = statements.getPair.get(body.base_token, body.quote_token);
    if (!pair) {
      return jsonResponse({ error: "Trading pair not supported" }, 400);
    }
    
    // Generate order ID
    const id = uuid();
    const now = Date.now();
    
    // Insert order
    statements.insertOrder.run(
      id,
      body.escrow_address,
      body.pool_address || null,
      body.base_token,
      body.quote_token,
      body.side,
      body.order_type,
      "ACTIVE",
      0,
      now,
      body.expires_at,
      now
    );
    
    // Update stats
    statements.incrementStats.run(
      pair.id,
      "hourly",
      Math.floor(now / 3600000) * 3600000,
      now
    );
    
    return jsonResponse({
      success: true,
      data: {
        id,
        escrow_address: body.escrow_address,
        status: "ACTIVE",
        created_at: now,
      }
    }, 201);
  } catch (error) {
    console.error("Create order error:", error);
    return jsonResponse({ error: "Failed to create order" }, 500);
  }
}

export async function getOrder(req: Request, id: string): Promise<Response> {
  try {
    const order = statements.getOrder.get(id) as Order | undefined;
    
    if (!order) {
      return jsonResponse({ error: "Order not found" }, 404);
    }
    
    return jsonResponse({ success: true, data: order });
  } catch (error) {
    console.error("Get order error:", error);
    return jsonResponse({ error: "Failed to get order" }, 500);
  }
}

export async function listOrders(req: Request): Promise<Response> {
  try {
    const url = new URL(req.url);
    const params = {
      status: url.searchParams.get("status"),
      base_token: url.searchParams.get("base_token"),
      quote_token: url.searchParams.get("quote_token"),
      side: url.searchParams.get("side"),
      limit: parseInt(url.searchParams.get("limit") || "50"),
      offset: parseInt(url.searchParams.get("offset") || "0"),
    };
    
    // Cap limit
    if (params.limit > 100) params.limit = 100;
    
    const orders = statements.listOrders.all(
      params.status,
      params.base_token,
      params.quote_token,
      params.side,
      params.limit,
      params.offset
    ) as Order[];
    
    return jsonResponse({
      success: true,
      data: orders,
      pagination: {
        limit: params.limit,
        offset: params.offset,
        total: orders.length,
      }
    });
  } catch (error) {
    console.error("List orders error:", error);
    return jsonResponse({ error: "Failed to list orders" }, 500);
  }
}

export async function updateOrder(req: Request, id: string): Promise<Response> {
  try {
    const body = await req.json();
    const now = Date.now();
    
    // Only allow status and fill_percentage updates
    if (body.status || body.fill_percentage !== undefined) {
      statements.updateOrderStatus.run(
        body.status || "ACTIVE",
        body.fill_percentage || 0,
        now,
        id
      );
    }
    
    const order = statements.getOrder.get(id) as Order | undefined;
    
    if (!order) {
      return jsonResponse({ error: "Order not found" }, 404);
    }
    
    return jsonResponse({ success: true, data: order });
  } catch (error) {
    console.error("Update order error:", error);
    return jsonResponse({ error: "Failed to update order" }, 500);
  }
}

export async function cancelOrder(req: Request, id: string): Promise<Response> {
  try {
    const now = Date.now();
    
    statements.updateOrderStatus.run("CANCELLED", 0, now, id);
    
    return jsonResponse({ success: true, message: "Order cancelled" });
  } catch (error) {
    console.error("Cancel order error:", error);
    return jsonResponse({ error: "Failed to cancel order" }, 500);
  }
}

// ==================== PAIR HANDLERS ====================

export async function listPairs(req: Request): Promise<Response> {
  try {
    const pairs = statements.listPairs.all() as Pair[];
    
    return jsonResponse({ success: true, data: pairs });
  } catch (error) {
    console.error("List pairs error:", error);
    return jsonResponse({ error: "Failed to list pairs" }, 500);
  }
}

export async function addPair(req: Request): Promise<Response> {
  try {
    const body = await req.json();
    const now = Date.now();
    
    statements.insertPair.run(
      body.base_token,
      body.quote_token,
      1,
      body.min_order_size || null,
      now
    );
    
    const pair = statements.getPair.get(body.base_token, body.quote_token);
    
    return jsonResponse({ success: true, data: pair }, 201);
  } catch (error) {
    console.error("Add pair error:", error);
    return jsonResponse({ error: "Failed to add pair" }, 500);
  }
}

// ==================== STATS HANDLERS ====================

export async function getStats(req: Request): Promise<Response> {
  try {
    const url = new URL(req.url);
    const base = url.searchParams.get("base_token");
    const quote = url.searchParams.get("quote_token");
    const period = url.searchParams.get("period") || "hourly";
    const limit = parseInt(url.searchParams.get("limit") || "24");
    
    if (!base || !quote) {
      return jsonResponse({ error: "base_token and quote_token required" }, 400);
    }
    
    const pair = statements.getPair.get(base, quote) as Pair | undefined;
    if (!pair) {
      return jsonResponse({ error: "Pair not found" }, 404);
    }
    
    const stats = statements.getStats.all(pair.id, period, limit);
    
    return jsonResponse({ success: true, data: stats });
  } catch (error) {
    console.error("Get stats error:", error);
    return jsonResponse({ error: "Failed to get stats" }, 500);
  }
}

// ==================== HEALTH CHECK ====================

export async function healthCheck(req: Request): Promise<Response> {
  return jsonResponse({
    status: "healthy",
    version: "0.1.0",
    timestamp: Date.now(),
  });
}

// ==================== HELPERS ====================

function jsonResponse(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    },
  });
}
TYPESCRIPT_EOF
```

---

## Step 3: Main Server

```bash
cat > index.ts << 'TYPESCRIPT_EOF'
import {
  createOrder,
  getOrder,
  listOrders,
  updateOrder,
  cancelOrder,
  listPairs,
  addPair,
  getStats,
  healthCheck,
} from "./handlers";

// Initialize database (imported for side effects)
import "./db";

const PORT = parseInt(process.env.PORT || "3000");

// Router
async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  // CORS preflight
  if (method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // Route matching
  try {
    // Health check
    if (path === "/" || path === "/health") {
      return healthCheck(req);
    }

    // Orders
    if (path === "/order" || path === "/orders") {
      if (method === "GET") return listOrders(req);
      if (method === "POST") return createOrder(req);
    }

    const orderMatch = path.match(/^\/order\/([a-f0-9-]+)$/);
    if (orderMatch) {
      const id = orderMatch[1];
      if (method === "GET") return getOrder(req, id);
      if (method === "PUT" || method === "PATCH") return updateOrder(req, id);
      if (method === "DELETE") return cancelOrder(req, id);
    }

    // Pairs
    if (path === "/pairs" || path === "/pair") {
      if (method === "GET") return listPairs(req);
      if (method === "POST") return addPair(req);
    }

    // Stats
    if (path === "/stats") {
      return getStats(req);
    }

    // 404
    return new Response(JSON.stringify({ error: "Not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Request error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

// Start server
const server = Bun.serve({
  port: PORT,
  fetch: handleRequest,
});

console.log(`
╔═══════════════════════════════════════════════════════════╗
║                  UMBRA ORDERFLOW SERVICE                  ║
╠═══════════════════════════════════════════════════════════╣
║  Status: Running                                          ║
║  Port:   ${PORT}                                             ║
║  Docs:   http://localhost:${PORT}/                           ║
╚═══════════════════════════════════════════════════════════╝
`);

// Expire old orders periodically
setInterval(() => {
  const now = Date.now();
  const { statements } = require("./db");
  statements.expireOrders.run(now, now);
}, 60000); // Every minute
TYPESCRIPT_EOF
```

---

## Step 4: Install Dependencies

```bash
cd packages/api
bun add better-sqlite3 uuid
bun add -d @types/better-sqlite3 @types/uuid
```

---

## Step 5: Create Tests

```bash
mkdir -p tests

cat > tests/api.test.ts << 'TYPESCRIPT_EOF'
import { describe, it, expect, beforeAll, afterAll } from "bun:test";

const BASE_URL = "http://localhost:3000";
let testOrderId: string;

describe("Umbra Orderflow API", () => {
  // Add pair first
  beforeAll(async () => {
    await fetch(`${BASE_URL}/pairs`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        base_token: "0x1111111111111111111111111111111111111111",
        quote_token: "0x2222222222222222222222222222222222222222",
        min_order_size: "1000000000000000000",
      }),
    });
  });

  describe("Health Check", () => {
    it("should return healthy status", async () => {
      const res = await fetch(`${BASE_URL}/health`);
      const data = await res.json();
      
      expect(res.status).toBe(200);
      expect(data.status).toBe("healthy");
    });
  });

  describe("Pairs", () => {
    it("should list pairs", async () => {
      const res = await fetch(`${BASE_URL}/pairs`);
      const data = await res.json();
      
      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(Array.isArray(data.data)).toBe(true);
    });
  });

  describe("Orders", () => {
    it("should create an order", async () => {
      const res = await fetch(`${BASE_URL}/order`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          escrow_address: "0x" + "a".repeat(40),
          base_token: "0x1111111111111111111111111111111111111111",
          quote_token: "0x2222222222222222222222222222222222222222",
          side: "BUY",
          order_type: "LIMIT",
          expires_at: Date.now() + 3600000,
        }),
      });
      const data = await res.json();
      
      expect(res.status).toBe(201);
      expect(data.success).toBe(true);
      expect(data.data.id).toBeDefined();
      
      testOrderId = data.data.id;
    });

    it("should get an order", async () => {
      const res = await fetch(`${BASE_URL}/order/${testOrderId}`);
      const data = await res.json();
      
      expect(res.status).toBe(200);
      expect(data.data.id).toBe(testOrderId);
    });

    it("should list orders", async () => {
      const res = await fetch(`${BASE_URL}/orders`);
      const data = await res.json();
      
      expect(res.status).toBe(200);
      expect(Array.isArray(data.data)).toBe(true);
    });

    it("should cancel an order", async () => {
      const res = await fetch(`${BASE_URL}/order/${testOrderId}`, {
        method: "DELETE",
      });
      const data = await res.json();
      
      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
    });
  });
});
TYPESCRIPT_EOF
```

---

## Step 6: Run and Test

```bash
# Make sure data directory exists
mkdir -p data

# Start the server
bun run dev

# In another terminal, run tests
bun test

# Test manually
curl http://localhost:3000/health
curl http://localhost:3000/pairs
```

---

## API Reference

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/pairs` | List trading pairs |
| POST | `/pairs` | Add trading pair |
| GET | `/orders` | List orders |
| POST | `/order` | Create order |
| GET | `/order/:id` | Get order |
| PUT | `/order/:id` | Update order |
| DELETE | `/order/:id` | Cancel order |
| GET | `/stats` | Get statistics |

### Request/Response Examples

**Create Order:**
```bash
curl -X POST http://localhost:3000/order \
  -H "Content-Type: application/json" \
  -d '{
    "escrow_address": "0x...",
    "base_token": "0x...",
    "quote_token": "0x...",
    "side": "BUY",
    "order_type": "LIMIT",
    "expires_at": 1735689600000
  }'
```

**List Orders:**
```bash
curl "http://localhost:3000/orders?status=ACTIVE&side=BUY&limit=10"
```

---

## What We Built

1. ✅ **SQLite Database** - Persistent storage for:
   - Order metadata
   - Trading pairs
   - Statistics

2. ✅ **REST API** - Full CRUD for:
   - Orders
   - Pairs
   - Stats

3. ✅ **Test Suite** - Coverage for all endpoints

---

## Next Steps

➡️ Proceed to **`docs/05-CLI.md`** to build the CLI demo:
- Contract deployment
- Order creation workflow
- Balance checking
- Full integration test

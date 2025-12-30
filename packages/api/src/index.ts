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
import { statements } from "./db";

const PORT = parseInt(process.env.PORT || "3000");

// ==================== RATE LIMITING ====================

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

const rateLimits = new Map<string, RateLimitEntry>();
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 100; // 100 requests per minute

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimits.get(ip);

  if (!entry || entry.resetAt < now) {
    // Create new entry or reset expired one
    rateLimits.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW });
    return false;
  }

  entry.count++;
  if (entry.count > RATE_LIMIT_MAX) {
    return true;
  }

  return false;
}

// Clean up old rate limit entries periodically
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of rateLimits) {
    if (entry.resetAt < now) {
      rateLimits.delete(ip);
    }
  }
}, 60000);

// ==================== REQUEST HANDLER ====================

async function handleRequest(req: Request, server: any): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  // Get client IP for rate limiting
  const ip = server.requestIP(req)?.address || "unknown";

  // Check rate limit
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: {
        "Content-Type": "application/json",
        "Retry-After": "60",
      },
    });
  }

  // CORS preflight
  if (method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Access-Control-Max-Age": "86400",
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
      return methodNotAllowed();
    }

    // Single order operations
    const orderMatch = path.match(/^\/order\/([a-f0-9-]+)$/);
    if (orderMatch) {
      const id = orderMatch[1];
      if (method === "GET") return getOrder(req, id);
      if (method === "PUT" || method === "PATCH") return updateOrder(req, id);
      if (method === "DELETE") return cancelOrder(req, id);
      return methodNotAllowed();
    }

    // Pairs
    if (path === "/pairs" || path === "/pair") {
      if (method === "GET") return listPairs(req);
      if (method === "POST") return addPair(req);
      return methodNotAllowed();
    }

    // Stats
    if (path === "/stats") {
      if (method === "GET") return getStats(req);
      return methodNotAllowed();
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

function methodNotAllowed(): Response {
  return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405,
    headers: { "Content-Type": "application/json" },
  });
}

// ==================== SERVER STARTUP ====================

const server = Bun.serve({
  port: PORT,
  fetch: handleRequest,
});

console.log(`
╔═══════════════════════════════════════════════════════════╗
║                  UMBRA ORDERFLOW SERVICE                  ║
╠═══════════════════════════════════════════════════════════╣
║  Status: Running                                          ║
║  Port:   ${String(PORT).padEnd(48)}║
║  Docs:   http://localhost:${String(PORT).padEnd(32)}║
╚═══════════════════════════════════════════════════════════╝
`);

// Expire old orders periodically
setInterval(() => {
  const now = Date.now();
  try {
    statements.expireOrders.run(now, now);
  } catch (error) {
    console.error("Error expiring orders:", error);
  }
}, 60000); // Every minute

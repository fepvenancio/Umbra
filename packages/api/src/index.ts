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
║  Port:   ${String(PORT).padEnd(48)}║
║  Docs:   http://localhost:${String(PORT).padEnd(32)}║
╚═══════════════════════════════════════════════════════════╝
`);

// Expire old orders periodically
setInterval(() => {
  const now = Date.now();
  statements.expireOrders.run(now, now);
}, 60000); // Every minute

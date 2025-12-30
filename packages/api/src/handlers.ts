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
    const pair = statements.getPair.get(body.base_token, body.quote_token) as Pair | undefined;
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

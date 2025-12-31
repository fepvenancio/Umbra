import { db, statements, Order, Pair } from "./db";
import { v4 as uuid, validate as uuidValidate } from "uuid";

// ==================== INPUT VALIDATION ====================

// Validate Ethereum-style address format (0x + 40 hex chars)
function isValidAddress(addr: string): boolean {
  return typeof addr === "string" && /^0x[a-fA-F0-9]{40}$/.test(addr);
}

// Validate order side
function isValidSide(side: string): boolean {
  return side === "BUY" || side === "SELL";
}

// Validate order type
function isValidOrderType(type: string): boolean {
  return type === "MARKET" || type === "LIMIT" || type === "IOC";
}

// Validate positive integer
function isPositiveInt(val: unknown): boolean {
  return typeof val === "number" && Number.isInteger(val) && val > 0;
}

// Sanitize string input (prevent XSS in responses)
function sanitize(str: string): string {
  return str.replace(/[<>&"']/g, (c) => ({
    '<': '&lt;',
    '>': '&gt;',
    '&': '&amp;',
    '"': '&quot;',
    "'": '&#39;',
  }[c] || c));
}

// ==================== ORDER HANDLERS ====================

export async function createOrder(req: Request): Promise<Response> {
  try {
    const body = await req.json();

    // Validate required fields exist
    const required = ["contract_address", "base_token", "quote_token", "side", "order_type", "expires_at"];
    for (const field of required) {
      if (!body[field]) {
        return jsonResponse({ error: `Missing required field: ${field}` }, 400);
      }
    }

    // Validate field formats
    if (!isValidAddress(body.contract_address)) {
      return jsonResponse({ error: "Invalid contract_address format" }, 400);
    }
    if (!isValidAddress(body.base_token)) {
      return jsonResponse({ error: "Invalid base_token format" }, 400);
    }
    if (!isValidAddress(body.quote_token)) {
      return jsonResponse({ error: "Invalid quote_token format" }, 400);
    }
    if (!isValidSide(body.side)) {
      return jsonResponse({ error: "Invalid side (must be BUY or SELL)" }, 400);
    }
    if (!isValidOrderType(body.order_type)) {
      return jsonResponse({ error: "Invalid order_type (must be MARKET, LIMIT, or IOC)" }, 400);
    }
    if (!isPositiveInt(body.expires_at)) {
      return jsonResponse({ error: "expires_at must be a positive integer (timestamp)" }, 400);
    }

    // Validate expiry is in the future
    const now = Date.now();
    if (body.expires_at <= now) {
      return jsonResponse({ error: "expires_at must be in the future" }, 400);
    }

    // Validate pair is supported
    const pair = statements.getPair.get(body.base_token, body.quote_token) as Pair | undefined;
    if (!pair) {
      return jsonResponse({ error: "Trading pair not supported" }, 400);
    }

    // Generate order ID
    const id = uuid();

    // Insert order
    statements.insertOrder.run(
      id,
      body.contract_address.toLowerCase(),
      body.base_token.toLowerCase(),
      body.quote_token.toLowerCase(),
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
        contract_address: body.contract_address.toLowerCase(),
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
    // Validate ID format
    if (!uuidValidate(id)) {
      return jsonResponse({ error: "Invalid order ID format" }, 400);
    }

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

    // Parse and validate parameters
    const status = url.searchParams.get("status");
    const base_token = url.searchParams.get("base_token");
    const quote_token = url.searchParams.get("quote_token");
    const side = url.searchParams.get("side");
    let limit = parseInt(url.searchParams.get("limit") || "50", 10);
    let offset = parseInt(url.searchParams.get("offset") || "0", 10);

    // Validate status if provided
    if (status && !["ACTIVE", "PARTIAL", "FILLED", "CANCELLED", "EXPIRED"].includes(status)) {
      return jsonResponse({ error: "Invalid status" }, 400);
    }

    // Validate side if provided
    if (side && !isValidSide(side)) {
      return jsonResponse({ error: "Invalid side" }, 400);
    }

    // Validate token formats if provided
    if (base_token && !isValidAddress(base_token)) {
      return jsonResponse({ error: "Invalid base_token format" }, 400);
    }
    if (quote_token && !isValidAddress(quote_token)) {
      return jsonResponse({ error: "Invalid quote_token format" }, 400);
    }

    // Sanitize pagination params
    if (isNaN(limit) || limit < 1) limit = 50;
    if (limit > 100) limit = 100;
    if (isNaN(offset) || offset < 0) offset = 0;

    const orders = statements.listOrders.all(
      status,
      base_token?.toLowerCase() || null,
      quote_token?.toLowerCase() || null,
      side,
      limit,
      offset
    ) as Order[];

    return jsonResponse({
      success: true,
      data: orders,
      pagination: {
        limit,
        offset,
        count: orders.length,
      }
    });
  } catch (error) {
    console.error("List orders error:", error);
    return jsonResponse({ error: "Failed to list orders" }, 500);
  }
}

export async function updateOrder(req: Request, id: string): Promise<Response> {
  try {
    // Validate ID format
    if (!uuidValidate(id)) {
      return jsonResponse({ error: "Invalid order ID format" }, 400);
    }

    const body = await req.json();
    const now = Date.now();

    // Validate status if provided
    if (body.status && !["ACTIVE", "PARTIAL", "FILLED", "CANCELLED", "EXPIRED"].includes(body.status)) {
      return jsonResponse({ error: "Invalid status" }, 400);
    }

    // Validate fill_percentage if provided
    if (body.fill_percentage !== undefined) {
      if (typeof body.fill_percentage !== "number" || body.fill_percentage < 0 || body.fill_percentage > 100) {
        return jsonResponse({ error: "fill_percentage must be 0-100" }, 400);
      }
    }

    // Check order exists
    const existingOrder = statements.getOrder.get(id) as Order | undefined;
    if (!existingOrder) {
      return jsonResponse({ error: "Order not found" }, 404);
    }

    // Only allow status and fill_percentage updates
    if (body.status || body.fill_percentage !== undefined) {
      statements.updateOrderStatus.run(
        body.status || existingOrder.status,
        body.fill_percentage ?? existingOrder.fill_percentage,
        now,
        id
      );
    }

    const order = statements.getOrder.get(id) as Order;

    return jsonResponse({ success: true, data: order });
  } catch (error) {
    console.error("Update order error:", error);
    return jsonResponse({ error: "Failed to update order" }, 500);
  }
}

export async function cancelOrder(req: Request, id: string): Promise<Response> {
  try {
    // Validate ID format
    if (!uuidValidate(id)) {
      return jsonResponse({ error: "Invalid order ID format" }, 400);
    }

    // Check order exists and is active
    const existingOrder = statements.getOrder.get(id) as Order | undefined;
    if (!existingOrder) {
      return jsonResponse({ error: "Order not found" }, 404);
    }

    if (existingOrder.status !== "ACTIVE" && existingOrder.status !== "PARTIAL") {
      return jsonResponse({ error: "Order cannot be cancelled (already filled/cancelled/expired)" }, 400);
    }

    const now = Date.now();
    statements.updateOrderStatus.run("CANCELLED", existingOrder.fill_percentage, now, id);

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

    // Validate required fields
    if (!body.base_token || !body.quote_token) {
      return jsonResponse({ error: "base_token and quote_token required" }, 400);
    }

    // Validate address formats
    if (!isValidAddress(body.base_token)) {
      return jsonResponse({ error: "Invalid base_token format" }, 400);
    }
    if (!isValidAddress(body.quote_token)) {
      return jsonResponse({ error: "Invalid quote_token format" }, 400);
    }

    // Validate tokens are different
    if (body.base_token.toLowerCase() === body.quote_token.toLowerCase()) {
      return jsonResponse({ error: "base_token and quote_token must be different" }, 400);
    }

    const now = Date.now();

    statements.insertPair.run(
      body.base_token.toLowerCase(),
      body.quote_token.toLowerCase(),
      1,
      body.min_order_size || null,
      now
    );

    const pair = statements.getPair.get(body.base_token.toLowerCase(), body.quote_token.toLowerCase());

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
    let limit = parseInt(url.searchParams.get("limit") || "24", 10);

    if (!base || !quote) {
      return jsonResponse({ error: "base_token and quote_token required" }, 400);
    }

    // Validate address formats
    if (!isValidAddress(base)) {
      return jsonResponse({ error: "Invalid base_token format" }, 400);
    }
    if (!isValidAddress(quote)) {
      return jsonResponse({ error: "Invalid quote_token format" }, 400);
    }

    // Validate period
    if (!["hourly", "daily", "weekly"].includes(period)) {
      return jsonResponse({ error: "Invalid period (must be hourly, daily, or weekly)" }, 400);
    }

    // Sanitize limit
    if (isNaN(limit) || limit < 1) limit = 24;
    if (limit > 168) limit = 168; // Max 1 week of hourly data

    const pair = statements.getPair.get(base.toLowerCase(), quote.toLowerCase()) as Pair | undefined;
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

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
}

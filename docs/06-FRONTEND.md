# 06-FRONTEND.md - Web Interface (Optional)

## Overview

Build a minimal web UI for Umbra Protocol. This is **optional** - the protocol works fully via CLI.

---

## Quick Setup

```bash
cd packages
bunx create-vite web --template react-ts
cd web
bun add @aztec/aztec.js tailwindcss
bun run dev
```

---

## Key Components Needed

1. **AztecProvider** - Wallet connection context
2. **OrderBook** - Display active orders
3. **CreateOrderForm** - Submit new orders
4. **TradeHistory** - User's past trades

---

## Minimal Implementation

For a working UI, you need:

```tsx
// src/App.tsx
import { useState, useEffect } from 'react';

const API_URL = 'http://localhost:3000';

function App() {
  const [orders, setOrders] = useState([]);
  
  useEffect(() => {
    fetch(`${API_URL}/orders`)
      .then(res => res.json())
      .then(data => setOrders(data.data || []));
  }, []);
  
  return (
    <div className="min-h-screen bg-gray-900 text-white p-8">
      <h1 className="text-3xl font-bold mb-8">Umbra Protocol</h1>
      
      <div className="grid grid-cols-2 gap-8">
        {/* Order Book */}
        <div className="bg-gray-800 rounded-lg p-6">
          <h2 className="text-xl mb-4">Order Book</h2>
          {orders.map((order: any) => (
            <div key={order.id} className="p-2 border-b border-gray-700">
              {order.side} - {order.status}
            </div>
          ))}
        </div>
        
        {/* Create Order */}
        <div className="bg-gray-800 rounded-lg p-6">
          <h2 className="text-xl mb-4">Create Order</h2>
          <p className="text-gray-400">Connect wallet to trade</p>
        </div>
      </div>
    </div>
  );
}

export default App;
```

---

## Full Implementation

For production, see the reference implementations:
- Aztec Starter: https://github.com/AztecProtocol/aztec-starter
- Noir Examples: https://github.com/AztecProtocol/aztec-examples

---

## Skip to Deployment

If you want to skip the frontend:

➡️ Proceed to **`docs/07-DEPLOY.md`** for testnet deployment

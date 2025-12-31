# Environment Setup

Set up your development environment for Umbra Protocol.

---

## Prerequisites

- **Node.js** v20+
- **Bun** v1.1+
- **Docker** (for Aztec sandbox)
- **Git**

---

## Step 1: Install Bun

```bash
curl -fsSL https://bun.sh/install | bash
bun --version
```

---

## Step 2: Install Aztec Toolchain

```bash
bash -i <(curl -s https://install.aztec.network)
aztec --version
aztec-nargo --version
```

---

## Step 3: Install Dependencies

```bash
cd umbra
bun install
```

---

## Step 4: Start Sandbox

The Aztec sandbox is needed for integration testing:

```bash
aztec start --sandbox
# Wait for ready message...
```

---

## Step 5: Verify Setup

```bash
# Compile contracts
cd packages/contracts && ~/.aztec/bin/aztec-nargo compile

# Run tests
cd ../.. && bun test

# Start API
cd packages/api && bun run start
# In another terminal:
curl http://localhost:3000/health
```

---

## Common Issues

### "aztec: command not found"
```bash
export PATH="$HOME/.aztec/bin:$PATH"
```

### "Docker not running"
```bash
sudo systemctl start docker
# Or on macOS: Open Docker Desktop
```

### "Port 8080 in use"
```bash
lsof -i :8080
# Kill the process or use a different port
```

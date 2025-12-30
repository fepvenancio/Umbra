# 00-SETUP.md - Environment Setup

## Overview

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
# Install Bun (if not already installed)
curl -fsSL https://bun.sh/install | bash

# Verify
bun --version
```

---

## Step 2: Install Aztec Toolchain

```bash
# Install Aztec CLI and tools
bash -i <(curl -s https://install.aztec.network)

# Verify
aztec --version
aztec-nargo --version
```

---

## Step 3: Clone and Install

```bash
# Clone the repository
git clone https://github.com/your-org/umbra-protocol.git
cd umbra-protocol

# Install dependencies
bun install
```

---

## Step 4: Start Sandbox (Optional)

The Aztec sandbox is needed for full integration testing:

```bash
# Start the sandbox (requires Docker)
aztec start --sandbox

# Wait for ready message...
```

---

## Step 5: Verify Setup

```bash
# Check CLI works
cd packages/cli
bun run setup:deploy

# Check API works
cd ../api
bun run start
# In another terminal:
curl http://localhost:3000/health
```

---

## Common Issues

### "aztec: command not found"
```bash
# Add to PATH
export PATH="$HOME/.aztec/bin:$PATH"
```

### "Docker not running"
```bash
# Start Docker daemon
sudo systemctl start docker
# Or on macOS: Open Docker Desktop
```

### "Port 8080 in use"
```bash
# Check what's using the port
lsof -i :8080
# Kill the process or use a different port
```

---

## Next Steps

Your environment is ready. Proceed to **`docs/01-CONTRACTS.md`** to build the contracts.

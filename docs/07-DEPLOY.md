# 07-DEPLOY.md - Testnet Deployment

## Overview

Deploy Umbra Protocol to Aztec testnet and production infrastructure.

---

## Quick Deploy Checklist

```
□ Contracts compile: aztec-nargo compile
□ Tests pass: bun test  
□ Sandbox demo works: bun run demo
□ Have testnet tokens for gas
□ API hosting ready (Railway/Fly.io/VPS)
```

---

## Step 1: Testnet Configuration

```bash
cd packages/cli

cat > .env.testnet << 'EOF'
PXE_URL=https://pxe.aztec-testnet.xyz
DEPLOYER_SECRET=your_secret_key_here
EOF
```

---

## Step 2: Deploy Contracts

```bash
# Deploy to testnet
bun run scripts/deploy-testnet.ts

# Verify
cat data/testnet-deployments.json
```

---

## Step 3: Deploy API

### Using Docker

```bash
cd packages/api

# Build
docker build -t umbra-api .

# Run
docker run -d -p 3000:3000 -v umbra-data:/data umbra-api
```

### Using Fly.io

```bash
fly launch --name umbra-api
fly volumes create data --size 1
fly deploy
```

---

## Step 4: Verify Deployment

```bash
# Health check
curl https://your-api.fly.dev/health

# Check pairs
curl https://your-api.fly.dev/pairs
```

---

## Production Checklist

- [ ] Contracts deployed and verified
- [ ] API running with persistent storage
- [ ] HTTPS enabled
- [ ] Rate limiting configured
- [ ] Monitoring set up
- [ ] Backup strategy in place

---

## 🎉 Build Complete!

You now have:
- ✅ Private OTC escrow contracts
- ✅ Dark pool with matching engine
- ✅ Orderflow REST API
- ✅ CLI demo tools
- ✅ Deployment scripts

### Next Steps

1. Join Aztec Discord for support
2. Apply for Aztec Catalyst grants
3. Iterate based on feedback
4. Prepare for mainnet launch

**Built for the Aztec ecosystem 🖤**

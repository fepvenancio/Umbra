# Contributing to Umbra Protocol

Thank you for your interest in contributing to Umbra Protocol!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/umbra-protocol.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Test: `bun run test`
6. Submit a pull request

## Development Setup

```bash
# Install dependencies
bun install

# Start sandbox (for integration tests)
aztec start --sandbox

# Run tests
bun run test

# Run demo
bun run demo
```

## Code Style

- Use TypeScript for all TypeScript files
- Use Noir for smart contracts
- Follow existing code patterns
- Add tests for new features

## Commit Messages

Use clear, descriptive commit messages:
- `feat: add partial fill support`
- `fix: correct fee calculation`
- `docs: update README`
- `test: add escrow tests`

## Pull Request Process

1. Update documentation if needed
2. Add tests for new features
3. Ensure all tests pass
4. Request review from maintainers

## Code of Conduct

Be respectful and constructive. We're all here to build something great.

## Questions?

Open an issue or reach out on Discord.

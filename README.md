# Kai-Sign

[![Actions Status](https://github.com/kaisign/v1-core/workflows/CI/badge.svg)](https://github.com/kaisign/v1-core/actions)

Aggregated curator for trusted transaction metadata registries.

## Overview

Kai-Sign consolidates verified metadata from multiple trusted sources to enhance hardware wallet clear signing reliability.

### Core Contracts

#### KaiSign.sol
The main contract that aggregates and manages trusted transaction metadata from multiple verified sources, enabling clear signing on hardware wallets.

#### MetadataRegistry.sol
A flexible attestation system that allows any user (not limited to KaiSign) to configure their own attesters and run validation checks when signing transactions with metadata. This contract will be deployed across multiple chains to ensure widespread accessibility.

### What to Expect from the Contract

- **Transparent Fee Model:** A small, on-chain fee per registry access or metadata submission that funds infrastructure and security audits.
- **Open Source & Audit-Ready:** Fully Apache‑2.0 licensed with all logic, fee parameters, and upgrade paths public for straightforward third-party reviews.

## Local Development

### Install Dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

## License

Apache-2.0 
# Irion Smart Contracts

![Solidity](https://img.shields.io/badge/Solidity-0.8.x-363636?style=flat-square&logo=solidity)
![Hardhat](https://img.shields.io/badge/Built%20with-Hardhat-fff100?style=flat-square)
![Chainlink CCIP](https://img.shields.io/badge/Chainlink-CCIP-375BD2?style=flat-square)

> Cross-chain Buy-Now-Pay-Later credit protocol: lock collateral on any chain, spend against it on the master chain.

## Overview

Irion is a cross-chain credit and BNPL (Buy Now, Pay Later) protocol built on top of [Chainlink CCIP](https://chain.link/cross-chain). Users deposit collateral into a `CollateralVault` on a **satellite chain** (e.g. Base Sepolia, Ethereum Sepolia). The vault prices the collateral with Chainlink price feeds and sends its USD value cross-chain to a **master chain** (Avalanche Fuji), where a `CreditManager` grants the user a credit limit based on a fixed loan-to-value ratio.

Against that limit, a `BNPLRouter` pays merchants in a stable payment token and records the borrowed amount in a `DebtManager`. If a position's health factor falls below the liquidation threshold, a `LiquidationController` sends a CCIP message back to the originating satellite vault to seize collateral. This lets a user collateralize on one chain and transact on another without bridging the underlying asset.

This repository contains the Solidity contracts, Hardhat deployment/configuration scripts, and a core test suite. It targets testnets and is a working reference implementation rather than an audited production system.

## Features

- **Cross-chain collateral via Chainlink CCIP** — satellite `CollateralVault` contracts message the master chain to update a user's credit as collateral is deposited or withdrawn.
- **Chainlink price feeds** — collateral is valued in USD on-chain using `AggregatorV3Interface` feeds per token.
- **On-chain credit limits** — `CreditManager` tracks per-user, per-chain, per-token collateral value and derives a spendable limit at a 75% LTV.
- **BNPL merchant payments** — `BNPLRouter` pays merchants from a pooled liquidity balance and books the amount as user debt, enforcing the credit limit.
- **Debt tracking & repayment** — `DebtManager` maintains per-user debt with authorized create/repay flows.
- **Cross-chain liquidation** — `LiquidationController` computes a health factor (85% liquidation threshold) and triggers CCIP-driven collateral seizure on the satellite chain.
- **Trusted-sender security** — the `MasterCCIPReceiver` only accepts messages from CCIP senders explicitly whitelisted per source chain.
- **Multi-network config** — Hardhat is preconfigured for Avalanche Fuji, Polygon Amoy, Ethereum Sepolia, and Base Sepolia, with block-explorer verification.

## Tech Stack

- **Solidity** `0.8.19` / `0.8.20`
- **Hardhat** (`@nomicfoundation/hardhat-toolbox`)
- **Chainlink** — `@chainlink/contracts-ccip` (CCIP), `@chainlink/contracts` (price feeds)
- **OpenZeppelin Contracts** `5.x` — `Ownable`, `SafeERC20`, `IERC20`
- **dotenv** for RPC URLs, keys, and API keys

## Getting Started

```bash
# clone
git clone https://github.com/nickthelegend/irion-smart-contracts.git
cd irion-smart-contracts

# install dependencies
npm install

# compile contracts
npx hardhat compile

# run the test suite
npx hardhat test
```

Create a `.env` file with the values referenced in `hardhat.config.js`:

```bash
PRIVATE_KEY=0x...
AVALANCHE_FUJI_RPC_URL=...
POLYGON_AMOY_RPC_URL=...
ETHEREUM_SEPOLIA_RPC_URL=...
BASE_SEPOLIA_RPC_URL=...
# optional block-explorer API keys for verification
ETHERSCAN_API_KEY=...
```

Deploy and wire up the CCIP contracts (master on Fuji, satellites elsewhere):

```bash
# deploy master-chain contracts
npx hardhat run scripts/deploy-ccip.js --network avalancheFuji

# deploy a satellite vault
npx hardhat run scripts/deploy-ccip.js --network baseSepolia

# configure trusted senders / feeds across chains
npx hardhat run scripts/setup-ccip.js --network avalancheFuji
```

Deployed addresses are written to and read from `deployments.json`.

## Project Structure

```
contracts/
  BNPLRouter.sol            # pays merchants against a user's credit limit, books debt
  CreditManager.sol         # per-user collateral value + credit limit (75% LTV)
  DebtManager.sol           # per-user debt accounting
  LiquidationController.sol # health-factor checks + CCIP liquidation trigger
  CollateralVault.sol       # satellite-chain collateral deposits + CCIP messaging
  MasterCCIPReceiver.sol    # master-chain CCIP entry point, trusted-sender gated
  SatelliteCCIPSender.sol   # abstract helper for sending CCIP messages to master
  MockERC20.sol             # test token
scripts/
  deploy-ccip.js            # deploys master/satellite contracts per network
  setup-ccip.js             # configures trusted senders and price feeds
test/
  IrionCore.js              # core credit + BNPL flow tests
hardhat.config.js           # multi-network + compiler config
deployments.json            # recorded deployment addresses
```

## License

The contracts are released under the **MIT** license (see the SPDX headers in `contracts/`).

---

Built by [**nickthelegend**](https://github.com/nickthelegend) · [nickthelegend.tech](https://nickthelegend.tech)

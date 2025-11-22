# AutoLP Hook 🦄

**A Uniswap v4 Hook that enables auto-compounding liquidity for taxable tokens.**

## Overview

The **AutoLP Hook** is designed to transform any regular ERC20 token into a "taxable" token within a Uniswap v4 pool. It introduces a unique mechanism where a fee is collected on swaps and automatically used to deepen the pool's liquidity. This added liquidity is effectively "owned" by the hook but shared among all existing liquidity providers, creating an auto-compounding effect.

### Key Features

*   **Taxable Token Conversion**: Turns standard ERC20 tokens into taxable assets by enforcing a fee on swaps (specifically exact-input swaps).
*   **Auto-Liquidity Generation**: The collected fees are not just burned or sent to a treasury; they are immediately used to add liquidity to the pool.
*   **Shared Liquidity Growth**: The liquidity added by the hook increases the total pool liquidity. When liquidity providers (LPs) remove their positions, they receive a proportional share of this "protocol-owned" liquidity, effectively rewarding them for staying in the pool.

## How It Works

1.  **Fee Collection**: When a user swaps the "taxable" token (defined in the hook), a percentage fee (e.g., 5%) is taken from the input amount.
2.  **Liquidity Provision**: This fee is automatically converted into a liquidity position managed by the hook contract.
3.  **Redistribution**: When a user removes their liquidity from the pool, the hook calculates their share of the total liquidity growth (including the hook's accumulated liquidity) and transfers the extra tokens to them. This ensures that long-term LPs benefit from the trading volume and the resulting tax revenue.

## Getting Started

### Requirements

*   **Foundry**: This project is built with Foundry. Ensure you have it installed.

```bash
foundryup
```

### Installation

```bash
forge install
```

### Running Tests

The project comes with a comprehensive test suite to verify the hook's logic, including the "Happy Path" scenario where fees are collected and redistributed.

```bash
forge test
```

## Local Development

You can deploy and test the hook locally using Anvil.

1.  Start Anvil:
    ```bash
    anvil
    ```

2.  Deploy the hook (example script):
    ```bash
    forge script script/00_DeployHook.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

## Additional Resources

*   [Uniswap v4 Docs](https://docs.uniswap.org/contracts/v4/overview)
*   [v4-periphery](https://github.com/uniswap/v4-periphery)
*   [v4-core](https://github.com/uniswap/v4-core)

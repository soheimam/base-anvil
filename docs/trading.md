# Build a trading app on Base locally

This tutorial takes you from nothing to a working swap against a local market
in a few minutes. One command boots a `base-anvil` node with tokens, seeded AMM
pools, and price feeds already deployed, so you can build a trading app without
writing or deploying any market plumbing first.

## Install

Install `base-foundryup` and the `base-*` commands as described in
[Testing your Base app with base-anvil](./base.md#install). Everything below
assumes `base-anvil`, `base-cast`, and `base-forge` are on your `PATH`.

## Boot a market with one command

```bash
base-anvil --preset trading
```

This starts a local chain (chain id `31337`, Base precompiles live, the usual
10 pre-funded anvil dev accounts) and loads a ready-made market from a state
snapshot:

- **MockUSDC** (6 decimals), **MockWETH** (18 decimals), and **MockCBBTC**
  (8 decimals) test tokens.
- **MiniAMM**, a minimal constant-product AMM, with seeded **USDC/WETH** and
  **cbBTC/WETH** pools.
- Mock **Chainlink-compatible price feeds** for ETH/USD and BTC/USD.
- All 10 dev accounts pre-funded with token balances on top of their ETH.

The deployed addresses are listed in
[`presets/trading/addresses.json`](../presets/trading/addresses.json).

`--preset <name>` resolves the snapshot by checking, in order:
`$BASE_ANVIL_PRESETS_DIR/<name>/state.json`, then `./presets/<name>/state.json`
relative to your working directory, then `~/.foundry/presets/<name>/state.json`.

> Prefer the raw mechanism? Under the `base-anvil` wrapper (which passes
> `--base` for you), `--preset trading` is equivalent to:
>
> ```bash
> base-anvil --load-state presets/trading/state.json
> ```
>
> On a raw `anvil` binary, `--preset` additionally enables the Base
> precompiles — the raw equivalent is
> `anvil --base --load-state presets/trading/state.json`.

## Your first swap

With `base-anvil --preset trading` running, set up your environment in another
terminal. Look up the deployed addresses in `presets/trading/addresses.json`
and export them (the values below are placeholders):

```bash
export RPC=http://127.0.0.1:8545

# From presets/trading/addresses.json:
export USDC=0x...         # MockUSDC
export WETH=0x...         # MockWETH
export AMM=0x...          # MiniAMM
export ETH_USD_FEED=0x... # ETH/USD price feed

# anvil dev account 0 (standard public anvil dev key, safe for local use only)
export DEV0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export DEV0_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Check the account's pre-funded USDC balance (6 decimals):

```bash
base-cast call $USDC "balanceOf(address)(uint256)" $DEV0 --rpc-url $RPC
```

Approve the AMM to spend 1,000 USDC, then swap 500 USDC for WETH. The last
argument is the minimum acceptable output (`minOut`); `0` is fine on a local
chain where nothing front-runs you:

```bash
base-cast send $USDC "approve(address,uint256)" $AMM 1000000000 \
  --private-key $DEV0_KEY --rpc-url $RPC

base-cast send $AMM "swapExactIn(address,address,uint256,uint256)" $USDC $WETH 500000000 0 \
  --private-key $DEV0_KEY --rpc-url $RPC
```

Confirm the WETH arrived, and read the ETH/USD price feed (Chainlink
convention: 8 decimals):

```bash
base-cast call $WETH "balanceOf(address)(uint256)" $DEV0 --rpc-url $RPC
base-cast call $ETH_USD_FEED "latestAnswer()(int256)" --rpc-url $RPC
```

That is the whole loop a trading app needs: balances, approvals, swaps, and a
price oracle, all local and instant. Point your frontend or bot at
`http://127.0.0.1:8545` and iterate.

## What's in the preset

| Contract | Notes | Address |
| --- | --- | --- |
| MockUSDC | ERC-20, 6 decimals | see `presets/trading/addresses.json` |
| MockWETH | ERC-20, 18 decimals | see `presets/trading/addresses.json` |
| MockCBBTC | ERC-20, 8 decimals | see `presets/trading/addresses.json` |
| MiniAMM | Constant-product AMM; seeded USDC/WETH and cbBTC/WETH pools | see `presets/trading/addresses.json` |
| ETH/USD feed | Chainlink-compatible (`latestAnswer()`, 8 decimals) | see `presets/trading/addresses.json` |
| BTC/USD feed | Chainlink-compatible (`latestAnswer()`, 8 decimals) | see `presets/trading/addresses.json` |

All 10 default anvil dev accounts hold balances of every token, plus ETH.

## Writing forge tests against the preset

Run your test suite against the live preset state by forking the local node.
With `base-anvil --preset trading` running:

```solidity
// test/TradingPreset.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IMiniAMM {
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut);
}

contract TradingPresetTest is Test {
    address constant DEV0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    IERC20 usdc;
    IERC20 weth;
    IMiniAMM amm;

    function setUp() public {
        // Addresses from presets/trading/addresses.json, passed via env
        usdc = IERC20(vm.envAddress("USDC"));
        weth = IERC20(vm.envAddress("WETH"));
        amm = IMiniAMM(vm.envAddress("AMM"));
    }

    function test_swapUsdcForWeth() public {
        uint256 amountIn = 500e6; // 500 USDC

        vm.startPrank(DEV0);
        usdc.approve(address(amm), amountIn);
        uint256 out = amm.swapExactIn(address(usdc), address(weth), amountIn, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertGe(weth.balanceOf(DEV0), out);
    }
}
```

```bash
USDC=$USDC WETH=$WETH AMM=$AMM \
  base-forge test --fork-url http://127.0.0.1:8545
```

The test sees exactly the preset's tokens, pools, and funded accounts, and any
Base precompile calls run natively on the node.

## Testing against real Base liquidity

When mocks are not enough, fork a live network instead of loading the preset.
`base-anvil` accepts named aliases for the public Base RPCs:

```bash
base-anvil --fork-url base          # alias for https://mainnet.base.org
base-anvil --fork-url base-sepolia  # alias for https://sepolia.base.org
```

The aliases point at the public, rate-limited Base endpoints — fine for a
first fork, not for sustained testing or CI. For real work, configure your
own RPC provider in `foundry.toml` `[rpc_endpoints]`, which takes precedence
over the built-in aliases; see
[docs/base.md](./base.md#fork-url-aliases-and-your-own-rpc-endpoints).

Your dev accounts have ETH on the fork but no tokens. Use the
`anvil_dealERC20` RPC method to give any account any ERC-20 balance; it finds
the token's balance storage slot and writes it directly, so it works for
tokens you do not control. Parameters are `(account, token, balance)`:

```bash
# 1,000 USDC (6 decimals = 0x3b9aca00) to dev account 0 on a Base mainnet fork
export USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # USDC on Base

base-cast rpc anvil_dealERC20 $DEV0 $USDC 0x3b9aca00 --rpc-url $RPC
base-cast call $USDC "balanceOf(address)(uint256)" $DEV0 --rpc-url $RPC
```

Now the same swap flow from above runs against real Base contracts and real
liquidity, without spending real funds.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| ``no state file found for preset `trading` `` | The snapshot is not on the resolution path. `--preset <name>` checks `$BASE_ANVIL_PRESETS_DIR/<name>/state.json`, then `./presets/<name>/state.json`, then `~/.foundry/presets/<name>/state.json`. Run from the repo root, set `BASE_ANVIL_PRESETS_DIR`, or copy the preset into `~/.foundry/presets/`. |
| Addresses in `addresses.json` do not match what is on chain | The snapshot and the address list are out of sync. Regenerate both with `presets/trading/generate.sh`. |
| Swap or feed calls revert / return empty on a fork | You forked a network where the mock contracts do not exist; the preset contracts only exist under `--preset trading` / `--load-state`. On forks, use the real deployed contracts (and `anvil_dealERC20` for balances). |
| `call to non-contract address 0x...` at a precompile | Base is not enabled on the node. `base-anvil` and `--preset` enable it; if you invoke a raw `anvil` build, add `--base`. See [docs/base.md](./base.md#troubleshooting). |

## Next steps

- **Base precompiles, install, and versioning:** [`docs/base.md`](./base.md).
- **Regenerating or customizing the preset:** `presets/trading/generate.sh`
  rebuilds `state.json` and `addresses.json` from source.
- **Upstream anvil reference** (`--load-state`, `--fork-url`, RPC methods):
  [getfoundry.sh](https://getfoundry.sh) or `base-anvil --help`.

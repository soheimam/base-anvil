# Trading preset

A self-contained mini Foundry project that produces a reusable `base-anvil`
state snapshot with a small trading environment already deployed:

| Name           | Contract           | Notes                                        |
| -------------- | ------------------ | -------------------------------------------- |
| `USDC`         | `MockERC20`        | 6 decimals                                   |
| `WETH`         | `MockERC20`        | 18 decimals                                  |
| `CBBTC`        | `MockERC20`        | 8 decimals                                   |
| `AMM`          | `MiniAMM`          | constant-product AMM, 0.3% fee, multi-pool   |
| `ETH_USD_FEED` | `MockV3Aggregator` | Chainlink-compatible, 8 decimals, `2500e8`   |
| `BTC_USD_FEED` | `MockV3Aggregator` | Chainlink-compatible, 8 decimals, `65000e8`  |

Two pools are seeded so spot prices match the feeds: 2,500,000 USDC / 1,000
WETH (2500 USDC per WETH) and 10 cbBTC / 260 WETH (26 WETH per cbBTC =
65000 / 2500). Every one of the 10 default anvil dev accounts holds
1,000,000 USDC, 1,000 WETH, and 10 cbBTC. All mocks are dev-net only —
`MockERC20.mint` and `MockV3Aggregator.updateAnswer` are unrestricted.

## Layout

```
presets/trading/
├── src/                          # dependency-free ^0.8.x contracts
│   ├── MockERC20.sol
│   ├── MiniAMM.sol
│   └── MockV3Aggregator.sol
├── script/DeployTradingPreset.s.sol  # forge script that deploys + seeds
├── test/TradingPreset.t.sol      # validates a node loaded from state.json
├── generate.sh                   # regenerates state.json + addresses.json
├── state.json                    # anvil snapshot (checked in, regenerable)
├── addresses.json                # name → deployed address map (checked in)
└── foundry.toml
```

The project is deliberately dependency-free (same convention as `smoke/`):
no forge-std, no submodules, no network access needed. The script and test
vendor the couple of cheatcode signatures they use.

## Using the snapshot

```sh
base-anvil --load-state presets/trading/state.json
```

State files are path-independent, so this works from any directory. Look up
contract addresses in `addresses.json`.

## Regenerating

```sh
./generate.sh
```

This starts a throwaway `base-anvil` on port 8946 with `--dump-state`,
broadcasts `DeployTradingPreset` with the default anvil dev key 0, extracts
the deployed addresses from the forge broadcast log into `addresses.json`,
and shuts the node down gracefully so it writes `state.json`. The script is
idempotent; it wipes previous artifacts first and fails fast if port 8946 is
taken.

## Running the test

The test is designed to run against a node started from the snapshot:

```sh
base-anvil --load-state presets/trading/state.json --port 8947 &
base-forge test --fork-url http://127.0.0.1:8947 --root presets/trading
```

It reads `addresses.json` with `vm.readFile` (permission granted in
`foundry.toml`) rather than env vars, so no per-run configuration is needed.
It checks dev account balances, pool reserves, both price feeds, and executes
a real USDC → WETH swap on the AMM, asserting the output lands in the
expected fee-adjusted range.

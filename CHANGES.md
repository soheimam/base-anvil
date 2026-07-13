# Changes on `persona-trading-presets`

Branch: `persona-trading-presets` (based on `base-anvil-fork`)
Remote: `git@github.com:soheimam/base-anvil.git`

This branch adds a persona-driven onboarding path for trading-app developers on
Base: a one-flag way to boot a local Base chain pre-seeded with tokens, an AMM,
and price feeds, plus the docs and tooling around it.

## Summary of commits

1. `6ded411c8` — feat(anvil): trading persona preset, Base fork aliases, and persona docs
2. `fd28fa03f` — chore(presets): drop forge cache artifact, ignore build outputs
3. `1b910f478` — docs: engineer-facing reference for `--preset` and Base fork aliases

## New anvil features (Rust)

### `--preset <NAME>` (`crates/anvil/src/cmd.rs`)

Sugar for `--base --load-state <path>`. The state file is resolved, in order,
from:

1. `$BASE_ANVIL_PRESETS_DIR/<name>/state.json` (if the env var is set)
2. `./presets/<name>/state.json` (relative to the current directory)
3. `~/.foundry/presets/<name>/state.json`

The flag conflicts with `--init`, `--state`, and `--load-state`. A missing
preset fails with the list of paths that were tried and a hint to run the
preset's `generate.sh`. Loading a preset also enables Base network defaults
(`crates/evm/networks/src/lib.rs` gained `Networks::enable_base` / `is_base`
support used by this flow).

### `--fork-url` aliases

`--fork-url base` and `--fork-url base-sepolia` (case-insensitive) resolve to
the public RPC endpoints `https://mainnet.base.org` and
`https://sepolia.base.org`. The `@<block>` suffix still works, e.g.
`--fork-url base@1000000`. Non-alias URLs pass through untouched.

Both features are covered by unit tests in `cmd.rs` (alias resolution, alias
with block pinning, pass-through, preset resolution via the env dir, and the
missing-preset error).

## The trading preset (`presets/trading/`)

A self-contained Foundry project whose deploy script produces the committed
`state.json` snapshot that `anvil --preset trading` boots from:

- `src/MockERC20.sol` — mintable mock tokens (USDC, WETH, cbBTC)
- `src/MiniAMM.sol` — a minimal constant-product AMM with seeded liquidity pools
- `src/MockV3Aggregator.sol` — Chainlink-compatible mock price feeds
- `script/DeployTradingPreset.s.sol` — deploys everything, seeds pools, and
  funds the default dev accounts with tokens
- `test/TradingPreset.t.sol` — 4-test suite validating the deployed world
- `generate.sh` — regenerates `state.json` from scratch
- `addresses.json` — the deterministic addresses of everything deployed
- `foundry.toml`, `README.md`, `.gitignore` (build outputs are ignored; a
  stray `cache/solidity-files-cache.json` artifact was removed in the chore
  commit)

## Documentation

- `docs/trading.md` — "Build a trading app on Base locally" tutorial that walks
  through booting the preset and interacting with the seeded tokens, AMM, and
  feeds
- `docs/base.md` — engineer-facing reference sections for `--preset` and the
  Base fork-url aliases
- `presets/trading/README.md` — what the preset contains and how to regenerate
  it
- `README.md` — pointers to the new docs
- `REASONING.md` — the what/why/how behind every decision in the persona
  initiative

## Stats

17 files changed, 1,299 insertions(+), 3 deletions(-) relative to
`base-anvil-fork`.

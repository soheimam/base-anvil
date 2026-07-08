# Developer persona initiative: design rationale

This branch (`persona-trading-presets`) turns base-anvil from "a Foundry build
that knows Base's precompiles" into "a Foundry build that boots a working Base
market in one command". This document records why each piece exists and how it
is built, for reviewers and future maintainers.

**Target persona:** trading, DeFi, and fintech builders evaluating Base. They
already know Foundry. What they don't have on day one is a chain with tokens,
liquidity, and prices on it — today they spend hours deploying mock USDC,
wiring an AMM, and faking oracle feeds before they can test a single swap.

> Consumer-facing docs live in `docs/base.md` and (on this branch)
> `docs/trading.md`. This file is the maintainer-facing "why".

## 1. Persona presets (`base-anvil --preset trading`)

**What.** A `--preset <name>` flag that boots base-anvil with a working market
already on-chain: mock canonical tokens (USDC with 6 decimals, WETH, cbBTC), a
constant-product AMM with seeded pools, mock Chainlink-compatible price feeds,
and the 10 default dev accounts funded with token balances — not just ETH.

**Why.** A blank chain forces every trading team to rebuild the same
scaffolding before evaluating anything Base-specific. The evaluation window
for a team comparing L2s is short; if the first hour is spent deploying mock
USDC, Base loses the comparison by default. One flag that produces a tradeable
market moves the first meaningful interaction (a swap, a price read, an
indexer pointed at real events) from hours to minutes. Presets also give
dev-rel a stable, versioned artifact to build tutorials and workshops on.

**How.** Presets are *state snapshots*, not Rust code:

1. Each preset is authored as a forge deploy script, run once against a live
   base-anvil instance.
2. The resulting chain state is captured with `--dump-state` into
   `presets/<name>/state.json`.
3. At startup, `--preset <name>` resolves the snapshot and feeds it through
   the existing `--load-state` machinery
   (`crates/anvil/src/cmd.rs:125-169` — the `state` / `dump_state` /
   `load_state` args and their `SerializableState` parser). `--preset` is
   sugar over a code path that already exists and is already tested upstream.

Preset resolution order:

1. `$BASE_ANVIL_PRESETS_DIR/<name>/state.json` (explicit override)
2. `./presets/<name>/state.json` (repo-local, used in this repo and in CI)
3. `~/.foundry/presets/<name>/state.json` (installed artifacts)

Why snapshots instead of baking deployments into Rust:

- **Versionable and auditable.** A preset is a JSON file plus the Solidity
  script that produced it, both reviewable in a PR. No opaque bytecode blobs
  in Rust source.
- **Cheap to extend.** A new persona (e.g. `payments`, `nft`) is a new deploy
  script and snapshot, no anvil code changes.
- **Reuses the release pipeline.** Snapshots ship as release assets through
  the same `.github/workflows/release.yml` flow described in `RELEASES.md`,
  so a preset is pinned to a build the same way the `base/base` rev is.

## 2. B20 market in the trading preset

**What.** The trading preset seeds its tokens as B20 tokens created through
the native token factory precompile at `0x8453...0000`, rather than deploying
vanilla ERC-20 bytecode.

**Why.** "We support the precompiles" is a compatibility claim; "here is a
working market built on them" is a product demo. A trading team that boots the
preset and inspects the tokens sees Base-native primitives in use from the
first block — the factory, B20 balances, the ActivationRegistry
(`0x8453...0001`) already active — without reading a spec first. It also
exercises the fork's core differentiator: stock anvil cannot produce this
preset at all, because the factory call aborts with
`call to non-contract address`.

**How.** The preset's deploy script calls the factory precompile via the
`base/base-std` interfaces (`IB20Factory`, `IB20` — see "Add the Base
interfaces" in `docs/base.md`), then mints balances to the 10 dev accounts.
Because base-anvil starts with activation-gated features already active
(`docs/base.md`, "The local base-anvil node"), the script needs no
`activate()` ceremony. The resulting B20 state serializes into
`presets/trading/state.json` like any other account state.

## 3. Fork-mode aliases (`--fork-url base`, `--fork-url base-sepolia`)

**What.** Named aliases for `--fork-url`: `base` resolves to
`https://mainnet.base.org`, `base-sepolia` to `https://sepolia.base.org`.

**Why.** Serious DEX teams do not evaluate against mocks — they fork mainnet
and test against real Aerodrome/Uniswap liquidity and real oracle prices.
Today that means hunting for an RPC URL before the first command runs. An
alias removes the last piece of setup friction:
`base-anvil --fork-url base` is memorable enough to appear in a tweet-sized
quickstart. Forking pairs with anvil's existing ERC-20 balance-setting RPC,
`anvil_dealERC20` (`crates/anvil/src/eth/api.rs:2251`), so a forked trader
account can hold any token balance in one call — no whale impersonation
scripts.

**How.** Aliases are resolved at the top of `NodeArgs::into_node_config`
(`crates/anvil/src/cmd.rs`), after clap parsing and after
`foundry.toml` `rpc_endpoints` aliases have been applied — so a user-defined
`base` endpoint in `rpc_endpoints` still wins, and the resolution covers every
consumption path. Because `ForkUrl`'s `FromStr` impl splits the `url@block`
suffix first, `--fork-url base@12345678` composes with block pinning.
Case-insensitive lookup lives in a `FORK_URL_ALIASES` table; each resolution
logs the substituted endpoint. Chain-id detection then auto-enables the Base
precompiles as it already does for 8453/84532.

## 4. Market-simulation helpers — **Planned / not yet implemented**

**What.** Two follow-ups, explicitly *not* in this branch:

- `base_setOraclePrice` — an RPC to move the preset's mock price feeds, so
  liquidation and rebalancing logic can be tested without scripting swaps to
  move the AMM price.
- A swap-traffic generator — background transactions against the preset's
  pools, so indexers, charting UIs, and analytics pipelines under development
  have live data to consume.

**Why.** A static market proves a swap works once; trading infra teams need a
*moving* market. But both features require new RPC surface and a background
task in the node, which deserve their own design review — shipping them with
the presets would couple a docs-and-artifacts release to node changes.

**How (sketch, subject to change).** `base_setOraclePrice` would be a
namespaced RPC alongside the existing `anvil_*` handlers in
`crates/anvil/src/eth/api.rs`, writing directly to the mock feed's storage
slots. The traffic generator would likely live behind a
`--preset-traffic` flag driving the dev accounts. Neither is committed until
phase 3 (see Sequencing).

## 5. The tutorial and template story (`docs/trading.md`)

**What.** A tutorial, `docs/trading.md`, that takes a trading builder from
install to a completed swap against the preset market, then on to fork mode
for real liquidity.

**Why.** The dev-rel metric for this persona is **time-to-first-swap**: how
long from "decided to evaluate Base" to "executed a swap against a realistic
market locally". Today that is hours of scaffolding; with the preset plus the
tutorial it should be minutes. A metric this concrete keeps the docs honest —
every step in `docs/trading.md` that isn't copy-pasteable is a regression.
The tutorial also gives a canonical home for the pieces above so they are
discovered together (preset → dealERC20 → fork aliases), rather than as three
disconnected flags in `--help`.

**How.** `docs/trading.md` mirrors the structure and tone of `docs/base.md`
(install, run, verify, troubleshoot) and is linked from the README's
Base-specific section. It doubles as the preset's acceptance test: the smoke
suite (see Testing strategy) executes the same commands the tutorial shows.

## 6. DEX choice: minimal AMM now, fork mode for the real thing

**What.** The trading preset ships a minimal, self-contained constant-product
AMM — one Solidity file, zero external dependencies — rather than a deployment
of Uniswap v4 or Aerodrome.

**Why.** The obvious alternatives both have real costs:

- **Uniswap-v4-style** maximizes reach (most trading teams know the
  interfaces) but drags in a large dependency tree, hooks machinery the
  preset doesn't use, and a licensing/versioning surface we would have to
  track.
- **Aerodrome** maximizes Base ecosystem alignment but couples the preset to
  one protocol's deployment artifacts and upgrade cadence.

A one-file x*y=k AMM is auditable in a single review, cheap to keep in sync
with the preset script, and sufficient for the preset's actual job: giving a
builder something to swap against and events to index in minute one. Teams
that need real Uniswap or Aerodrome behavior are exactly the teams the fork
aliases serve — `--fork-url base` gives them the *actual* deployed contracts
with real liquidity, which no local redeployment can match anyway.

**How.** The AMM source lives with the preset's deploy script under
`presets/trading/`, is deployed by that script, and its pools are seeded with
the B20 tokens from item 2. `docs/trading.md` states plainly that the AMM is
a mock for local iteration and points to fork mode for protocol-accurate
testing.

## Sequencing

| Phase | Scope | Where |
| --- | --- | --- |
| **1 (this branch)** | `docs/trading.md`, preset deploy scripts + `presets/trading/state.json`, `--preset` flag, fork-url aliases | `persona-trading-presets` |
| **2** | Preset artifacts built and versioned in releases; `base-foundryup` installs them to `~/.foundry/presets/`; snapshots regenerated when the `base/base` pin moves | `.github/workflows/release.yml`, `RELEASES.md` |
| **3** | Simulation RPCs: `base_setOraclePrice`, swap-traffic generator | `crates/anvil/src/eth/api.rs` (design review first) |

Phase 1 deliberately contains no new node RPC surface: it is docs, artifacts,
and thin CLI wiring over existing machinery, so it can ship on the normal
release cadence without a protocol-style review.

## Testing strategy

- **Per-preset smoke test.** Each preset gets a forge test suite mirroring
  `smoke/test/BasePrecompile.t.sol`: CI boots `base-anvil --preset trading`,
  then asserts the market is live — token decimals (USDC = 6), dev-account
  token balances, a round-trip swap through the AMM, and a price read from
  the mock feed. This catches stale snapshots whenever the `base/base` pin or
  the deploy scripts change, using the same per-platform CI pattern as the
  existing precompile smoke test.
- **Cargo tests for CLI wiring.** Unit tests in `crates/anvil/src/cmd.rs`
  alongside the existing `ForkUrl` parse tests (around line 805): preset name
  → path resolution across the three lookup locations, the
  `$BASE_ANVIL_PRESETS_DIR` override, alias → URL resolution including
  `base@<block>`, and the error message for an unknown preset name.
- **Docs as tests.** The commands in `docs/trading.md` are the smoke test's
  script; if the tutorial drifts from reality, CI fails.

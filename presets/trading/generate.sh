#!/usr/bin/env bash
# Regenerates the trading preset artifacts:
#   state.json     — anvil state snapshot (load with `base-anvil --load-state`)
#   addresses.json — name → address map of the deployed contracts
#
# Idempotent and CI-friendly: fixed port, strict mode, cleanup trap. Run it
# from anywhere; it always operates on its own directory.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PORT=8946
RPC_URL="http://127.0.0.1:${PORT}"
# Default anvil dev key 0 (public, well-known test key).
DEPLOYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

ANVIL_PID=""
cleanup() {
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill -INT "${ANVIL_PID}" 2>/dev/null || true
    wait "${ANVIL_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Fail fast if the port is already taken (e.g. a leaked anvil from a previous
# run) instead of silently deploying onto stale state.
if lsof -iTCP:"${PORT}" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "error: port ${PORT} is already in use; kill the process holding it and re-run" >&2
  exit 1
fi

# Start from a clean slate so reruns are reproducible.
rm -f state.json addresses.json
rm -rf broadcast cache out

# base-anvil enables --base by itself (passing --base again is rejected as a
# duplicate flag). State is dumped to state.json on graceful shutdown.
echo "==> starting base-anvil (--base, port ${PORT})"
base-anvil --port "${PORT}" --dump-state state.json >anvil.log 2>&1 &
ANVIL_PID=$!

echo "==> waiting for RPC at ${RPC_URL}"
ready=""
for _ in $(seq 1 60); do
  if base-cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done
if [[ -z "${ready}" ]]; then
  echo "error: anvil did not become ready; see anvil.log" >&2
  exit 1
fi

echo "==> deploying trading preset"
base-forge script script/DeployTradingPreset.s.sol:DeployTradingPreset \
  --broadcast \
  --rpc-url "${RPC_URL}" \
  --private-key "${DEPLOYER_KEY}"

echo "==> extracting deployed addresses into addresses.json"
# The deploy script creates contracts in a fixed order (see the comment in
# DeployTradingPreset.run); map the CREATE transactions positionally and
# sanity-check each contract name.
run_latest=$(ls broadcast/DeployTradingPreset.s.sol/*/run-latest.json)
jq '
  [.transactions[] | select(.transactionType == "CREATE")] as $creates
  | [["USDC","MockERC20"], ["WETH","MockERC20"], ["CBBTC","MockERC20"],
     ["AMM","MiniAMM"], ["ETH_USD_FEED","MockV3Aggregator"], ["BTC_USD_FEED","MockV3Aggregator"]] as $expected
  | if ($creates | length) != ($expected | length) then
      error("expected \($expected | length) CREATE transactions, got \($creates | length)")
    else . end
  | reduce range(0; $expected | length) as $i ({};
      if $creates[$i].contractName != $expected[$i][1] then
        error("CREATE #\($i): expected \($expected[$i][1]), got \($creates[$i].contractName)")
      else . + {($expected[$i][0]): $creates[$i].contractAddress} end)
' "${run_latest}" >addresses.json
cat addresses.json

echo "==> shutting anvil down (dumps state.json)"
kill -INT "${ANVIL_PID}"
wait "${ANVIL_PID}" 2>/dev/null || true
ANVIL_PID=""

if [[ ! -s state.json ]]; then
  echo "error: state.json was not written; see anvil.log" >&2
  exit 1
fi
rm -f anvil.log

echo "==> done: $(du -h state.json | cut -f1) state.json, addresses.json"

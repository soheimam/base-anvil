// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "../src/MockERC20.sol";
import {MiniAMM} from "../src/MiniAMM.sol";
import {MockV3Aggregator} from "../src/MockV3Aggregator.sol";

/// @dev Vendored minimal cheatcode interface. This sub-project is
///      deliberately dependency-free (same convention as smoke/), so instead
///      of importing forge-std we declare the one cheatcode pair the script
///      needs against the well-known cheatcode address.
interface Vm {
    function startBroadcast(address sender) external;
    function stopBroadcast() external;
}

/// @title DeployTradingPreset
/// @notice Deploys the trading preset onto a fresh base-anvil node:
///           - MockUSDC (6 dp), MockWETH (18 dp), MockCBBTC (8 dp)
///           - MiniAMM with two seeded pools:
///               USDC/WETH  at ~2500 USDC per WETH
///               cbBTC/WETH at ~26 WETH per cbBTC (65000 / 2500)
///           - ETH/USD feed at 2500e8 and BTC/USD feed at 65000e8 (8 dp)
///           - generous balances for all 10 default anvil dev accounts
///
///         The script writes nothing to disk; generate.sh extracts the
///         deployed addresses from forge's broadcast log into addresses.json.
contract DeployTradingPreset {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Default anvil dev account 0 — the broadcaster used by generate.sh.
    address internal constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // Prices (Chainlink style, 8 decimals).
    int256 internal constant ETH_USD_PRICE = 2500e8;
    int256 internal constant BTC_USD_PRICE = 65000e8;

    // Pool seeds — chosen so pool spot prices match the feed prices:
    //   2,500,000 USDC / 1,000 WETH = 2500 USDC per WETH
    //   10 cbBTC / 260 WETH         = 26 WETH per cbBTC = 65000 / 2500
    uint256 internal constant POOL_USDC = 2_500_000e6;
    uint256 internal constant POOL_WETH = 1_000e18;
    uint256 internal constant POOL_CBBTC = 10e8;
    uint256 internal constant POOL_WETH_BTC = 260e18;

    // Per-dev-account balances.
    uint256 internal constant DEV_USDC = 1_000_000e6;
    uint256 internal constant DEV_WETH = 1_000e18;
    uint256 internal constant DEV_CBBTC = 10e8;

    /// @dev The 10 well-known default anvil dev accounts (mnemonic
    ///      "test test ... junk").
    function devAccounts() public pure returns (address[10] memory accounts) {
        accounts = [
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
            0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
            0x976EA74026E726554dB657fA54763abd0C3a0aa9,
            0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
            0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
        ];
    }

    function run() external {
        vm.startBroadcast(DEPLOYER);

        // 1. Tokens. Deployment order matters: generate.sh maps the CREATE
        //    transactions in the broadcast log to names positionally.
        MockERC20 usdc = new MockERC20("Mock USD Coin", "USDC", 6);
        MockERC20 weth = new MockERC20("Mock Wrapped Ether", "WETH", 18);
        MockERC20 cbbtc = new MockERC20("Mock Coinbase Wrapped BTC", "cbBTC", 8);

        // 2. AMM.
        MiniAMM amm = new MiniAMM();

        // 3. Price feeds.
        new MockV3Aggregator(8, "ETH / USD", ETH_USD_PRICE);
        new MockV3Aggregator(8, "BTC / USD", BTC_USD_PRICE);

        // 4. Seed the pools from the deployer.
        usdc.mint(DEPLOYER, POOL_USDC);
        weth.mint(DEPLOYER, POOL_WETH + POOL_WETH_BTC);
        cbbtc.mint(DEPLOYER, POOL_CBBTC);

        usdc.approve(address(amm), type(uint256).max);
        weth.approve(address(amm), type(uint256).max);
        cbbtc.approve(address(amm), type(uint256).max);

        amm.addLiquidity(address(usdc), address(weth), POOL_USDC, POOL_WETH);
        amm.addLiquidity(address(cbbtc), address(weth), POOL_CBBTC, POOL_WETH_BTC);

        // 5. Fund every default anvil dev account.
        address[10] memory accounts = devAccounts();
        for (uint256 i = 0; i < accounts.length; i++) {
            usdc.mint(accounts[i], DEV_USDC);
            weth.mint(accounts[i], DEV_WETH);
            cbbtc.mint(accounts[i], DEV_CBBTC);
        }

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IMiniAMM {
    function getReserves(address tokenA, address tokenB) external view returns (uint256, uint256);
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256);
}

interface IFeedLike {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (int256);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/// @dev Vendored minimal cheatcode interface (dependency-free by convention,
///      like smoke/test/BasePrecompile.t.sol).
interface Vm {
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function startPrank(address sender) external;
    function stopPrank() external;
}

/// @notice Validates the trading preset snapshot. Run against a node that was
/// started from the generated state, e.g.:
///
///   base-anvil --load-state presets/trading/state.json --port 8947
///   base-forge test --fork-url http://127.0.0.1:8947 --root presets/trading
///
/// Contract addresses are read from addresses.json via vm.readFile +
/// vm.parseJsonAddress rather than env vars: the file is generated next to
/// state.json and checked in, so the test needs zero per-run configuration —
/// more robust than requiring six env vars to be exported correctly. The
/// read permission is granted in foundry.toml (fs_permissions).
contract TradingPresetTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Balances minted per dev account by DeployTradingPreset (account 0 also
    // paid the pool liquidity out of a separate mint, so all 10 hold these).
    uint256 internal constant DEV_USDC = 1_000_000e6;
    uint256 internal constant DEV_WETH = 1_000e18;
    uint256 internal constant DEV_CBBTC = 10e8;

    IERC20Like internal usdc;
    IERC20Like internal weth;
    IERC20Like internal cbbtc;
    IMiniAMM internal amm;
    IFeedLike internal ethUsdFeed;
    IFeedLike internal btcUsdFeed;

    function setUp() public {
        string memory json = vm.readFile("addresses.json");
        usdc = IERC20Like(vm.parseJsonAddress(json, ".USDC"));
        weth = IERC20Like(vm.parseJsonAddress(json, ".WETH"));
        cbbtc = IERC20Like(vm.parseJsonAddress(json, ".CBBTC"));
        amm = IMiniAMM(vm.parseJsonAddress(json, ".AMM"));
        ethUsdFeed = IFeedLike(vm.parseJsonAddress(json, ".ETH_USD_FEED"));
        btcUsdFeed = IFeedLike(vm.parseJsonAddress(json, ".BTC_USD_FEED"));
    }

    function devAccounts() internal pure returns (address[10] memory accounts) {
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

    function test_devAccountsFunded() external view {
        address[10] memory accounts = devAccounts();
        for (uint256 i = 0; i < accounts.length; i++) {
            require(usdc.balanceOf(accounts[i]) >= DEV_USDC, "dev account missing USDC");
            require(weth.balanceOf(accounts[i]) >= DEV_WETH, "dev account missing WETH");
            require(cbbtc.balanceOf(accounts[i]) >= DEV_CBBTC, "dev account missing cbBTC");
        }
    }

    function test_poolsSeeded() external view {
        (uint256 rUsdc, uint256 rWeth) = amm.getReserves(address(usdc), address(weth));
        require(rUsdc == 2_500_000e6, "unexpected USDC reserve");
        require(rWeth == 1_000e18, "unexpected WETH reserve");

        (uint256 rCbbtc, uint256 rWeth2) = amm.getReserves(address(cbbtc), address(weth));
        require(rCbbtc == 10e8, "unexpected cbBTC reserve");
        require(rWeth2 == 260e18, "unexpected WETH reserve (BTC pool)");
    }

    function test_swapUsdcForWeth() external {
        address trader = devAccounts()[1];
        uint256 amountIn = 2_500e6; // 2500 USDC, roughly one WETH at pool price

        uint256 quoted = amm.getAmountOut(address(usdc), address(weth), amountIn);
        uint256 wethBefore = weth.balanceOf(trader);

        vm.startPrank(trader);
        usdc.approve(address(amm), amountIn);
        uint256 amountOut = amm.swapExactIn(address(usdc), address(weth), amountIn, quoted);
        vm.stopPrank();

        // 2500 USDC at spot 2500 USDC/WETH would be exactly 1 WETH; with the
        // 0.3% fee plus price impact on a 2.5M/1000 pool we expect ~0.996 WETH.
        require(amountOut == quoted, "swap output differs from quote");
        require(amountOut > 0.99e18, "swap output too low");
        require(amountOut < 1e18, "swap output above no-fee bound");
        require(weth.balanceOf(trader) == wethBefore + amountOut, "WETH not delivered");
    }

    function test_priceFeeds() external view {
        require(ethUsdFeed.decimals() == 8, "ETH/USD feed decimals");
        require(ethUsdFeed.latestAnswer() == 2500e8, "ETH/USD price");
        require(btcUsdFeed.decimals() == 8, "BTC/USD feed decimals");
        require(btcUsdFeed.latestAnswer() == 65000e8, "BTC/USD price");

        (, int256 ethAnswer,, uint256 ethUpdatedAt,) = ethUsdFeed.latestRoundData();
        require(ethAnswer == 2500e8, "ETH/USD latestRoundData answer");
        require(ethUpdatedAt != 0, "ETH/USD updatedAt unset");

        (, int256 btcAnswer,,,) = btcUsdFeed.latestRoundData();
        require(btcAnswer == 65000e8, "BTC/USD latestRoundData answer");
    }
}

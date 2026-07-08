// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title MiniAMM
/// @notice A minimal constant-product (x * y = k) AMM that manages multiple
///         pools in a single contract, keyed by the (sorted) token pair.
///         Charges a Uniswap-v2 style 0.3% fee on input.
///
///         This is a TEACHING ARTIFACT for the trading preset, not production
///         code: there are no LP tokens, no liquidity removal, no price
///         oracles, and no reentrancy guards. Keep it simple and readable.
contract MiniAMM {
    struct Pool {
        uint256 reserve0; // reserves of the lower-addressed token
        uint256 reserve1; // reserves of the higher-addressed token
    }

    /// @dev pool key = keccak256(token0, token1) with token0 < token1.
    mapping(bytes32 => Pool) internal pools;

    event LiquidityAdded(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event Swap(
        address indexed sender, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @notice Add liquidity to the (tokenA, tokenB) pool. Amounts are pulled
    ///         via transferFrom, so the caller must approve this contract
    ///         first. No LP shares are issued — liquidity is donated.
    function addLiquidity(address tokenA, address tokenB, uint256 amtA, uint256 amtB) external {
        require(tokenA != tokenB, "MiniAMM: identical tokens");
        require(amtA > 0 && amtB > 0, "MiniAMM: zero amount");

        require(IERC20Minimal(tokenA).transferFrom(msg.sender, address(this), amtA), "MiniAMM: transferFrom A failed");
        require(IERC20Minimal(tokenB).transferFrom(msg.sender, address(this), amtB), "MiniAMM: transferFrom B failed");

        (bytes32 key, bool sorted) = _poolKey(tokenA, tokenB);
        Pool storage pool = pools[key];
        if (sorted) {
            pool.reserve0 += amtA;
            pool.reserve1 += amtB;
        } else {
            pool.reserve0 += amtB;
            pool.reserve1 += amtA;
        }
        emit LiquidityAdded(tokenA, tokenB, amtA, amtB);
    }

    /// @notice Swap an exact `amountIn` of `tokenIn` for at least `minOut` of
    ///         `tokenOut`. Caller must approve this contract for `amountIn`.
    /// @return amountOut The amount of `tokenOut` sent to the caller.
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut)
    {
        amountOut = getAmountOut(tokenIn, tokenOut, amountIn);
        require(amountOut >= minOut, "MiniAMM: insufficient output");

        require(
            IERC20Minimal(tokenIn).transferFrom(msg.sender, address(this), amountIn), "MiniAMM: transferFrom failed"
        );

        (bytes32 key, bool sorted) = _poolKey(tokenIn, tokenOut);
        Pool storage pool = pools[key];
        if (sorted) {
            // tokenIn is token0.
            pool.reserve0 += amountIn;
            pool.reserve1 -= amountOut;
        } else {
            pool.reserve0 -= amountOut;
            pool.reserve1 += amountIn;
        }

        require(IERC20Minimal(tokenOut).transfer(msg.sender, amountOut), "MiniAMM: transfer failed");
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Reserves of the (tokenA, tokenB) pool, returned in the order
    ///         the caller passed the tokens.
    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (bytes32 key, bool sorted) = _poolKey(tokenA, tokenB);
        Pool storage pool = pools[key];
        (reserveA, reserveB) = sorted ? (pool.reserve0, pool.reserve1) : (pool.reserve1, pool.reserve0);
    }

    /// @notice Quote the constant-product output for `amountIn`, after the
    ///         0.3% fee: out = Rout * in * 997 / (Rin * 1000 + in * 997).
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "MiniAMM: zero input");
        (uint256 reserveIn, uint256 reserveOut) = getReserves(tokenIn, tokenOut);
        require(reserveIn > 0 && reserveOut > 0, "MiniAMM: pool not seeded");

        uint256 amountInWithFee = amountIn * 997;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * 1000 + amountInWithFee);
    }

    function _poolKey(address tokenA, address tokenB) internal pure returns (bytes32 key, bool sorted) {
        require(tokenA != tokenB, "MiniAMM: identical tokens");
        sorted = tokenA < tokenB;
        (address token0, address token1) = sorted ? (tokenA, tokenB) : (tokenB, tokenA);
        key = keccak256(abi.encodePacked(token0, token1));
    }
}

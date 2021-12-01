//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPoolAddressProvider {

    function getLendingPool()
    external
    view
    returns (address);

}

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
    external
    view
    returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external returns (bool);
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
    external
    view
    returns (address pair);

    function allPairsLength()
    external
    view
    returns (uint);
}

// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#swaptokensforexacttokens
interface IUniswapV2Router02 {

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);

}


// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
    external
    view
    returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );

    function token0()
    external
    view
    returns (address);

    function token1()
    external
    view
    returns (address);
}

// ----------------------IMPLEMENTATION------------------------------

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    //    *** Your code here ***
    uint256 constant amountBorrow = 2916358033172;
    address public immutable uniswapv2FactoryAddress;
    address public immutable uniswapv2RouterAddress;
    address public immutable lendingPoolAddressProvider;
    address public immutable wbtcAddress;
    address public immutable usdtAddress;
    address public immutable wethAddress;
    address public immutable userAddress;
    // END TODO

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    constructor() {
        // TODO: (optional) initialize your contract
        //   *** Your code here ***
        console.log("contract deployment");
        console.log("current block number: ", block.number);
        console.log("current block timestamp: ", block.timestamp);
        uniswapv2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        uniswapv2RouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        lendingPoolAddressProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
        wbtcAddress = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        userAddress = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;

        // END TODO
    }

    // TODO: add a `receive` function so that you can withdraw your WETH
    //   *** Your code here ***
    receive() external payable {
        console.log("received %d eth", msg.value);
    }
    // END TODO

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // TODO: implement your liquidation logic

        // 0. security checks and initializing variables
        //    *** Your code here ***
        // check enough usdt for flash loan (weth-usdt flash swap)
        console.log("calling LiqudationOperator.operate()");
        console.log("current block number: ", block.number);

        IUniswapV2Factory factory = IUniswapV2Factory(uniswapv2FactoryAddress);
        IUniswapV2Pair flashSwapPair = IUniswapV2Pair(factory.getPair(wethAddress, usdtAddress));
        (uint wethUniReserve, uint usdtUniReserve, ) = flashSwapPair.getReserves();
        require(usdtUniReserve >= amountBorrow, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        console.log("uniswapv2 WETH-USDT pool");
        console.log("pool WETH before flash swap: ", wethUniReserve);
        console.log("pool USDT before flash swap: ", usdtUniReserve);

        // 1. get the target user account data & make sure it is liquidatable
        //    *** Your code here ***
        console.log("operate 1");

        ILendingPoolAddressProvider addressProvider = ILendingPoolAddressProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());
        ( , , , , , uint userHealthFactor) = lendingPool.getUserAccountData(userAddress);
        require(userHealthFactor < 10 ** health_factor_decimals, "AaveV2Library: USER NOT LIQUIDATABLE");

        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***
        console.log("operate 2");
        console.log("usdt to borrow from pool: ", amountBorrow);
        flashSwapPair.swap(0, amountBorrow, address(this), abi.encode(1));

        // 3. Convert the profit into ETH and send back to sender
        //    *** Your code here ***
        console.log("operate 3");

        // approve and withdraw WETH
        uint wethProfit = IWETH(wethAddress).balanceOf(address(this));
        //        IWETH(wethAddress).approve(uniswapv2RouterAddress, wethProfit); ??
        IWETH(wethAddress).withdraw(wethProfit);

        // approve and send ETH to contract caller
        console.log("final profit: ", wethProfit);
        (bool sent, ) = msg.sender.call{value: wethProfit}("");
        require(sent, "FAILED TO SEND ETHER TO CONTRACT CALLER");
        // END TODO
    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256,
        uint256 amount1,
        bytes calldata
    ) external override {
        // TODO: implement your liquidation logic

        // 2.0. security checks and initializing variables
        //    *** Your code here ***
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        assert(msg.sender == IUniswapV2Factory(uniswapv2FactoryAddress).getPair(token0, token1));

        uint preliquidationBtcBalance = IERC20(wbtcAddress).balanceOf(address(this));

        // 2.1 liquidate the target user
        //    *** Your code here ***
        console.log("uniswapV2Call 2.1");

        // approve usdt spender => lendingPool
        ILendingPoolAddressProvider addressProvider = ILendingPoolAddressProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());
        IERC20(usdtAddress).approve(address(lendingPool), amount1);

        // call liquidationCall()
        console.log("calling liquidationCall()");
        lendingPool.liquidationCall(wbtcAddress, usdtAddress, userAddress, amount1, false);
        uint btcLiquidated = IERC20(wbtcAddress).balanceOf(address(this)) - preliquidationBtcBalance;
        console.log("WBTC liquidated: ", preliquidationBtcBalance);

        // 2.2 swap WBTC for other things or repay directly
        //    *** Your code here ***
        console.log("uniswapV2Call 2.2");
        // approve wbtc spender = uniswapv2RouterAddress
        IERC20(wbtcAddress).approve(uniswapv2RouterAddress, btcLiquidated);
        // swap WBTC -> WETH
        address[] memory path = new address[](2);
        path[0] = wbtcAddress;
        path[1] = wethAddress;
        // TODD: send WBTC to router / pair address first?
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(uniswapv2RouterAddress);
        swapRouter.swapExactTokensForTokens(btcLiquidated, 0, path, address(this), block.timestamp + 60 * 30);
        // TODO: unrealistic, should check oracle price to avoid slippage

        // print existing contract balance of WBTC, WETH, USDT
        console.log("Contract WETH balance: ", IERC20(wethAddress).balanceOf(address(this)));
        console.log("Contract WBTC balance: ", IERC20(wbtcAddress).balanceOf(address(this))); // should =0?
        console.log("Contract USDT balance: ", IERC20(usdtAddress).balanceOf(address(this))); // should =0?
        require(IERC20(wbtcAddress).balanceOf(address(this)) == 0, "NOT ALL WBTC SWAPPED TO WETH");
        require(IERC20(usdtAddress).balanceOf(address(this)) == 0, "NOT ALL USDT SWAPPED TO WBTC");

        // 2.3 repay
        //    *** Your code here ***
        // calculate flashSwapRepayAmount (weth)
        console.log("uniswapV2Call 2.3");
        IUniswapV2Pair flashSwapPair = IUniswapV2Pair(msg.sender);
        (uint wethUniReserve, uint usdtUniReserve, ) = flashSwapPair.getReserves();
        uint flashSwapRepayAmount = getAmountIn(amount1, wethUniReserve, usdtUniReserve);

        // approve and send WETH back to flash swap pair (weth-usdt)
        IERC20(wethAddress).approve(msg.sender, flashSwapRepayAmount);
        IERC20(wethAddress).transfer(msg.sender, flashSwapRepayAmount);

        // check profit and balances of contract
        console.log("Contract WETH balance: ", IERC20(wethAddress).balanceOf(address(this)));
        console.log("Profit in WETH: ", IERC20(wethAddress).balanceOf(address(this)));
        require(IERC20(wethAddress).balanceOf(address(this)) > 0, "NON-POSITIVE PROFIT");
        // END TODO
    }
}
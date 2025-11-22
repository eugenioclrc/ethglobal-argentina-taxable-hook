// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import "forge-std/console.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AutoLP is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using StateLibrary for IPoolManager;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    address public tokenTaxable;
    uint256 public totalLiquidityAdded;
    constructor(IPoolManager _poolManager, address _tokenTaxable) BaseHook(_poolManager) {
        tokenTaxable = _tokenTaxable;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------


    uint256 transient beforeTotalLiquidity;
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata /*params*/,
        bytes calldata /*hookData*/
    ) external override onlyPoolManager returns (bytes4) {
        require(key.currency0 == Currency.wrap(tokenTaxable) || key.currency1 == Currency.wrap(tokenTaxable), "Wrong hook, not for this token pair");
        
        // ignore math if the sender is the hook itself
        if(sender == address(this)) return BaseHook.beforeAddLiquidity.selector;
        
        // save the total liquidity before the add liquidity
        beforeTotalLiquidity = poolManager.getLiquidity(key.toId());

        return BaseHook.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        require(key.currency0 == Currency.wrap(tokenTaxable) || key.currency1 == Currency.wrap(tokenTaxable), "Wrong hook, not for this token pair");
        
        // ignore math if the sender is the hook itself
        if(sender == address(this)) return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
        
        //console.log("Entering afterAddLiquidity");
        uint256 afterTotalLiquidity = poolManager.getLiquidity(key.toId());
        uint256 liquidityAdded = afterTotalLiquidity - beforeTotalLiquidity;
        //console.log("Liquidity added:", liquidityAdded);
        totalLiquidityAdded += liquidityAdded;

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata /*params*/,
        bytes calldata /*hookData*/
    ) external override onlyPoolManager returns (bytes4) {        
        require(key.currency0 == Currency.wrap(tokenTaxable) || key.currency1 == Currency.wrap(tokenTaxable), "Wrong hook, not for this token pair");

        if (sender == address(this)) return BaseHook.beforeRemoveLiquidity.selector;

        beforeTotalLiquidity = poolManager.getLiquidity(key.toId());

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        require(key.currency0 == Currency.wrap(tokenTaxable) || key.currency1 == Currency.wrap(tokenTaxable), "Wrong hook, not for this token pair");

        if (sender == address(this)) return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));

        uint256 afterTotalLiquidity = poolManager.getLiquidity(key.toId());
        uint256 liquidityRemoved = beforeTotalLiquidity > afterTotalLiquidity
            ? beforeTotalLiquidity - afterTotalLiquidity
            : 0;

        if (liquidityRemoved == 0 || totalLiquidityAdded == 0) {
            return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
        }

        if (liquidityRemoved > totalLiquidityAdded) {
            liquidityRemoved = totalLiquidityAdded;
        }

        bytes32 hookPositionKey =
            Position.calculatePositionKey(address(this), params.tickLower, params.tickUpper, params.salt);
        uint128 hookLiquidity = poolManager.getPositionLiquidity(key.toId(), hookPositionKey);
        if (hookLiquidity == 0) {
            totalLiquidityAdded -= liquidityRemoved;
            return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
        }

        uint128 liquidityToTransfer = uint128((uint256(hookLiquidity) * liquidityRemoved) / totalLiquidityAdded);
        if (liquidityToTransfer == 0) {
            totalLiquidityAdded -= liquidityRemoved;
            return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
        }

        (BalanceDelta hookDelta, ) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: -int256(uint256(liquidityToTransfer)),
                salt: params.salt
            }),
            bytes("")
        );

        if (hookDelta.amount0() > 0) {
            key.currency0.take(poolManager, sender, uint256(uint128(hookDelta.amount0())), false);
        } else if (hookDelta.amount0() < 0) {
            key.currency0.settle(poolManager, address(this), uint256(uint128(-hookDelta.amount0())), false);
        }
        if (hookDelta.amount1() > 0) {
            key.currency1.take(poolManager, sender, uint256(uint128(hookDelta.amount1())), false);
        } else if (hookDelta.amount1() < 0) {
            key.currency1.settle(poolManager, address(this), uint256(uint128(-hookDelta.amount1())), false);
        }

        totalLiquidityAdded -= liquidityRemoved;
        
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata /*hookData*/)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        
        // ignore math if the sender is the hook itself
        if(sender == address(this)) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        
        // Note: Sender must approve the Hook!
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        if (Currency.unwrap(inputCurrency) != address(tokenTaxable)) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Only support exact input for now
        if (params.amountSpecified >= 0) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 fee = amountIn * 5 / 100;

        // user have to approve the hook to spend the fee
        IERC20(Currency.unwrap(inputCurrency)).transferFrom(sender, address(this), fee);
        
        //console.log("add liquidity");
        // Add liquidity with the fee amount.
        _addLiquidity(key, params.zeroForOne, fee);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // ADD LIQUIDITY TO THE POOL, FOR THE FEE AMOUNT
    function _addLiquidity(PoolKey calldata key, bool zeroForOne, uint256 amount) internal {
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(key.toId());
        // Silence unused variable warning
        sqrtPriceX96;
        
        int24 tickSpacing = key.tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        
        uint128 liquidity;

        if (zeroForOne) {
            // We have Token0. Need range above current tick.
            // Align tick to spacing.
            int24 compressed = tick / tickSpacing;
            if (tick < 0 && tick % tickSpacing != 0) compressed--; // Round down
            
            // We want tickLower > tick.
            // Let's start at next usable tick.
            tickLower = (compressed + 1) * tickSpacing;
            tickUpper = tickLower + tickSpacing;
            
            // Calculate liquidity
            uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
            
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount);
            //console.log("TickLower:", int256(tickLower));
            //console.log("TickUpper:", int256(tickUpper));
            //console.log("Liquidity:", uint256(liquidity));
        } else {
            // We have Token1. Need range below current tick.
            int24 compressed = tick / tickSpacing;
            if (tick < 0 && tick % tickSpacing != 0) compressed--;
            
            // We want tickUpper <= tick.
            tickUpper = compressed * tickSpacing;
            tickLower = tickUpper - tickSpacing;
            
            uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
            
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount);
        }
        
        // Modify Liquidity
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            bytes("")
        );
        
        // Settle the debt
        if (zeroForOne) {
            if (delta.amount0() < 0) {
                key.currency0.settle(poolManager, address(this), uint256(uint128(-delta.amount0())), false);
            }
            if (delta.amount1() < 0) {
                 key.currency1.settle(poolManager, address(this), uint256(uint128(-delta.amount1())), false);
            }
        } else {
            if (delta.amount0() < 0) {
                 key.currency0.settle(poolManager, address(this), uint256(uint128(-delta.amount0())), false);
            }
            if (delta.amount1() < 0) {
                key.currency1.settle(poolManager, address(this), uint256(uint128(-delta.amount1())), false);
            }
        }
    }

}

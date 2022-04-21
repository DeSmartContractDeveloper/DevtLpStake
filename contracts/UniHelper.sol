pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './interfaces/IUniswapV2Router01.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import './libraries/UniswapV2Library.sol';

contract UniHelper is ReentrancyGuard {
    using SafeMath for uint256;
    IUniswapV2Router01 public UniswapV2Router01;
    event SwapAdd(
        address sender,
        uint256 sendAmount,
        uint256 swapIn,
        uint256 swapOut,
        uint256 addA,
        uint256 addB,
        uint256 lp,
        uint256 backA,
        uint256 backB
    );

    constructor(address _router1) public {
        UniswapV2Router01 = IUniswapV2Router01(_router1);
    }

    function singleTokenAddLp(
        address pair,
        address inputToken,
        uint256 amount,
        uint256 amountSwapOutMin,
        uint256 deadline
    )
        external
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (address tokenFrom, address tokenTo, bool fromIsToken0) = this.sortToken(pair, inputToken);
        _addApprove(tokenFrom);
        _addApprove(tokenTo);
        SafeERC20.safeTransferFrom(IERC20(tokenFrom), msg.sender, address(this), amount);
        (uint256 swapAmount, ) = this.getSwapAmount(pair, amount, fromIsToken0);
        address[] memory paths = new address[](2);
        paths[0] = tokenFrom;
        paths[1] = tokenTo;
        uint256[] memory amounts = UniswapV2Router01.swapExactTokensForTokens(
            swapAmount,
            amountSwapOutMin,
            paths,
            address(this),
            deadline
        );
        uint256 _amount = amount;
        (uint256 amountA, uint256 amountB, uint256 lp) = UniswapV2Router01.addLiquidity(
            tokenFrom,
            tokenTo,
            _amount.sub(amounts[0]),
            amounts[1],
            _amount.sub(amounts[0]).mul(90).div(100),
            amounts[1].mul(90).div(100),
            msg.sender,
            block.timestamp
        );
        require(lp > 0, 'SA: add lp error');
        uint256 fromBal = IERC20(tokenFrom).balanceOf(address(this));
        if (fromBal > 0) SafeERC20.safeTransfer(IERC20(tokenFrom), msg.sender, fromBal);
        uint256 toBal = IERC20(tokenTo).balanceOf(address(this));
        if (toBal > 0) SafeERC20.safeTransfer(IERC20(tokenTo), msg.sender, toBal);
        emit SwapAdd(msg.sender, _amount, amounts[0], amounts[1], amountA, amountB, lp, fromBal, toBal);
        return (lp, fromBal, toBal);
    }

    function sortToken(address pair, address inputToken)
        external
        view
        returns (
            address from,
            address to,
            bool fromIsToken0
        )
    {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(inputToken == token0 || inputToken == token1, 'UH: token not found');
        address tokenFrom = token0 == inputToken ? token0 : token1;
        address tokenTo = token0 == inputToken ? token1 : token0;
        return (tokenFrom, tokenTo, token0 == inputToken);
    }

    function _addApprove(address token) internal {
        if (IERC20(token).allowance(address(this), address(UniswapV2Router01)) == 0) {
            SafeERC20.safeApprove(IERC20(token), address(UniswapV2Router01), uint256(-1));
        }
    }

    function getSwapAmount(
        address pair,
        uint256 amount,
        bool fromIsToken0
    ) external view returns (uint256 swapAmount, uint256 outAmount) {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 r0 = fromIsToken0 ? reserve0 : reserve1;
        uint256 r1 = fromIsToken0 ? reserve1 : reserve0;
        swapAmount = _getAmount(amount, 0, r0, r1);
        outAmount = UniswapV2Library.getAmountOut(swapAmount, r0, r1);
    }

    function _getAmount(
        uint256 balance0,
        uint256 balance1,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256) {
        uint256 a = 997;
        uint256 b = reserve0.mul(1997);
        uint256 _c = (balance0.mul(reserve1)).sub(balance1.mul(reserve0));
        uint256 c = _c.mul(1000).div(balance1.add(reserve1)).mul(reserve0);
        uint256 d = a.mul(c).mul(4);
        uint256 e = b.mul(b).add(d).sqrt();
        return e.sub(b).div(a.mul(2));
    }
}

pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './interfaces/IUniswapV2Router01.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

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
        uint256 backB,
        uint256 swapB
    );

    constructor(address _router1) public {
        UniswapV2Router01 = IUniswapV2Router01(_router1);
    }

    function swapAdd(
        address pair,
        address inputToken,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        (address tokenA, address tokenB) = _checkToken(pair, inputToken);
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, address(this), amount);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 swapAmount = _getAmount(amount, 0, reserve0, reserve1);
        address[] memory paths = new address[](2);
        paths[0] = tokenA;
        paths[1] = tokenB;
        uint256[] memory amounts = UniswapV2Router01.swapExactTokensForTokens(
            swapAmount,
            1,
            paths,
            address(this),
            block.timestamp
        );
        (uint256 amountA, uint256 amountB, uint256 lp) = UniswapV2Router01.addLiquidity(
            tokenA,
            tokenB,
            swapAmount,
            amounts[1],
            1,
            1,
            msg.sender,
            block.timestamp
        );
        uint256 _amount = amount;
        require(lp > 0, 'SA: add lp error');
        uint256 backA = _amount.sub(amounts[0]).sub(amountA);
        uint256 backB = amounts[1].sub(amountB);
        uint256 swapB;
        if (backB > 0) {
            address[] memory paths_ = new address[](2);
            paths_[1] = tokenA;
            paths_[0] = tokenB;
            uint256[] memory amounts_ = UniswapV2Router01.swapExactTokensForTokens(
                backB,
                0,
                paths_,
                address(this),
                block.timestamp
            );
            swapB = amounts_[1];
        }
        uint256 b = IERC20(tokenA).balanceOf(address(this));
        if (b > 0) SafeERC20.safeTransfer(IERC20(tokenA), msg.sender, b);
        emit SwapAdd(msg.sender, _amount, amounts[0], amounts[1], amountA, amountB, lp, backA, backB, swapB);
        return lp;
    }

    function _checkToken(address pair, address inputToken) internal returns (address from, address to) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(inputToken == token0 || inputToken == token1, 'SA: token not found');
        _addApprove(token0);
        _addApprove(token1);
        address tokenA = token0 == inputToken ? token0 : token1;
        address tokenB = token0 == inputToken ? token1 : token0;
        return (tokenA, tokenB);
    }

    function _addApprove(address token) internal {
        if (IERC20(token).allowance(address(this), address(UniswapV2Router01)) == 0) {
            SafeERC20.safeApprove(IERC20(token), address(UniswapV2Router01), uint256(-1));
        }
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

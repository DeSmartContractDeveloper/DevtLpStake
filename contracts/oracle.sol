pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/UniswapV2Library.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract Oracle is Ownable {
    using FixedPoint for *;

    struct Pair {
        address token0;
        address token1;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }
    mapping(address => Pair) public pairs;

    address[] public allPairs;

    event PairAdd(address pair);
    event PairPriceSync(address pair, uint256 price0With18, uint256 price1With18);

    function setPairPrice(
        address pair,
        uint112 price0Numerator,
        uint112 price0Denominator
    ) external onlyOwner {
        Pair storage _pair = pairs[pair];
        require(_pair.token0 != address(0) && _pair.token1 != address(0), 'Oracle: pair not add');
        _pair.price0Average = FixedPoint.fraction(price0Numerator, price0Denominator);
        _pair.price1Average = FixedPoint.fraction(price0Denominator, price0Numerator);
        _pair.blockTimestampLast = uint32(block.timestamp);
        log(pair);
    }

    function addPair(address pair) external onlyOwner {
        Pair storage _pair_ = pairs[pair];
        require(_pair_.token0 == address(0) || _pair_.token1 == address(0), 'Oracle: pair have been add');
        IUniswapV2Pair _pair = IUniswapV2Pair(pair);
        (uint256 reserve0, uint256 reserve1, uint32 _ts) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'Oracle: NO_RESERVES');
        pairs[pair] = Pair({
            token0: _pair.token0(),
            token1: _pair.token1(),
            blockTimestampLast: _ts,
            price0Average: FixedPoint.encode(0),
            price1Average: FixedPoint.encode(0)
        });
        allPairs.push(pair);
        emit PairAdd(pair);
    }

    function consult(
        address pair,
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bool effect) {
        Pair storage _pair = pairs[pair];
        if (_pair.token0 == address(0)) {
            return (0, false);
        }
        if (token == _pair.token0) {
            amountOut = _pair.price0Average.mul(amountIn).decode144();
        } else {
            require(token == _pair.token1, 'Oracle: INVALID_TOKEN');
            amountOut = _pair.price1Average.mul(amountIn).decode144();
        }
        effect = true;
    }

    function log(address pair) internal {
        (uint256 p0, uint256 p1) = this.tokenPirceWith18(pair);
        emit PairPriceSync(pair, p0, p1);
    }

    function tokenPirceWith18(address pair) external view returns (uint256 token0Price, uint256 token1Price) {
        Pair storage _pair = pairs[pair];
        return (_pair.price0Average.decode112with18(), _pair.price1Average.decode112with18());
    }
}

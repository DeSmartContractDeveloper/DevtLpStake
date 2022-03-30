pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '../libraries/UniswapV2LiquidityMathLibrary.sol';

interface IOracle {
    function consult(
        address pair,
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bool effect);

    function tokenPirceWith18(address pair) external view returns (uint256, uint256);
}

contract Devt is Ownable, ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    mapping(uint256 => string) private _tokenURIs;

    struct ReleaseInfo {
        address maker;
        uint256 index;
        uint256 amount;
        uint256 value;
        uint256 relaseAmount;
        uint256 startTs;
    }

    struct Strategy {
        uint256 percent;
        uint256 duration;
    }

    mapping(address => bool) public pairToken0IsStableToken;
    mapping(address => bool) public pairEnable;
    mapping(address => uint256) public pairMinLpAmount;

    IOracle public Oracle;

    address public stToken;
    address public stPair;
    bool public stIsToken0;

    mapping(uint256 => Strategy) public strategys;
    mapping(uint256 => ReleaseInfo) public relaseInfo;

    event StrategyUpdate(uint256 strategy, uint256 percent, uint256 duration);
    event SetPair(address pair, bool token0IsStableToken, bool enable, uint256 minLpAmount);
    event Stake(
        address player,
        address pair,
        uint256 strategy,
        uint256 lp,
        uint256 tokenId,
        uint256 amount,
        uint256 value,
        uint256 price
    );
    event Unstake(address reciver, uint256 token, uint256 amount);

    constructor(
        address _stToken,
        address _stPair,
        address _oracle,
        bool _stIsToken0
    ) public ERC721('ST', 'ST') {
        stToken = _stToken;
        stPair = _stPair;
        stIsToken0 = _stIsToken0;
        Oracle = IOracle(_oracle);
        strategys[0] = Strategy(7000, 7 * 7 days); // one main strategy , the rest is another main strategy
        strategys[1] = Strategy(9000, 1 * 7 days);
        strategys[2] = Strategy(8800, 2 * 7 days);
    }

    function updateStrategy(
        uint256 index,
        uint256 percent,
        uint256 duration
    ) external onlyOwner {
        strategys[index] = Strategy(percent, duration);
        emit StrategyUpdate(index, percent, duration);
    }

    function setTOkenURI(uint256 tokenId, string calldata _tokenURI) external onlyOwner {
        require(_exists(tokenId), 'ERC721URIStorage: URI set of nonexistent token');
        _tokenURIs[tokenId] = _tokenURI;
    }

    function setPair(
        address pair,
        bool _token0IsStableToken,
        bool enable,
        uint256 minLpAmount
    ) external onlyOwner {
        pairToken0IsStableToken[pair] = _token0IsStableToken;
        pairEnable[pair] = enable;
        pairMinLpAmount[pair] = minLpAmount;
        emit SetPair(pair, _token0IsStableToken, enable, minLpAmount);
    }

    function batchUnstake(uint256[] calldata tokens) external {
        for (uint256 index = 0; index < tokens.length; index++) {
            this.unstake(tokens[index]);
        }
    }

    function unstake(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, 'ST: token owner error');
        ReleaseInfo storage info = relaseInfo[tokenId];
        uint256 amount = calcUnstakeAmount(tokenId);
        require(amount > 0, 'ST: no token to unstake');
        uint256 stBalance = IERC20(stToken).balanceOf(address(this));
        require(stBalance >= amount, 'ST: no enough token to unstake');
        info.relaseAmount += amount;
        SafeERC20.safeTransfer(IERC20(stToken), msg.sender, amount);
        emit Unstake(msg.sender, tokenId, amount);
    }

    function calcUnstakeAmount(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), 'ST: token not found');
        ReleaseInfo storage info = relaseInfo[tokenId];
        uint256 amount = 0;
        if (info.index > 0) {
            require(info.relaseAmount < info.amount, 'ST: release finish');
            uint256 remainAmount = info.amount - info.relaseAmount;
            amount = (info.amount / strategys[info.index].duration) * (block.timestamp - info.startTs);
            if (amount > remainAmount) amount = remainAmount;
        } else {
            require(info.relaseAmount == 0, 'ST: relased finish 2');
            require(
                block.timestamp >= strategys[info.index].duration + info.startTs &&
                    block.timestamp <= strategys[info.index].duration + info.startTs + 1 days,
                'ST: time error'
            );
            uint256 price = (getStPrice() * strategys[info.index].percent) / 10000;
            amount = info.value / price;
        }
        return amount;
    }

    function stake(
        address pair,
        uint256 lp,
        uint256 s
    ) external {
        Strategy storage strategy = strategys[s];
        require(strategy.duration > 0 && strategy.percent > 0, 'ST:strategy not found ');
        require(pairEnable[pair] == true, 'ST: pair not enable');
        require(lp >= pairMinLpAmount[pair], 'ST:lp value must gt the min amount');
        SafeERC20.safeTransferFrom(IERC20(pair), msg.sender, address(this), lp);
        uint256 value = 0;
        (uint256 amount0, uint256 amount1) = UniswapV2LiquidityMathLibrary.getLiquidityValue(
            IUniswapV2Pair(pair).factory(),
            IUniswapV2Pair(pair).token0(),
            IUniswapV2Pair(pair).token1(),
            lp
        );
        if (pairToken0IsStableToken[pair]) {
            (uint256 amount_, bool effect) = Oracle.consult(pair, IUniswapV2Pair(pair).token1(), amount1);
            require(effect == true && amount_ > 0, 'ST:Oracle not update 0 ');
            value = amount0 + amount_;
        } else {
            (uint256 _amount, bool effect) = Oracle.consult(pair, IUniswapV2Pair(pair).token0(), amount0);
            require(effect == true && _amount > 0, 'ST:Oracle not update 1');
            value = amount1 + _amount;
        }
        value = value * 1e18; // for price enlarged 1e18, so the value alse enarge 1e18
        uint256 price = (getStPrice() * strategy.percent) / 10000;
        uint256 amount = value / price;
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _mint(msg.sender, tokenId);
        relaseInfo[tokenId] = ReleaseInfo(msg.sender, s, amount, value, 0, block.timestamp);
        emit Stake(msg.sender, pair, s, lp, tokenId, amount, value, price);
    }

    function getStPrice() internal view returns (uint256) {
        (uint256 token0Price, uint256 token1Price) = Oracle.tokenPirceWith18(stPair);
        uint256 price = stIsToken0 ? token0Price : token1Price;
        require(price > 0, 'ST:price is zero');
        return price;
    }
}

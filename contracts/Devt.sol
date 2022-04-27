pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import './libraries/UniswapV2LiquidityMathLibrary.sol';
import './UniHelper.sol';
import './interfaces/IOracle.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';

contract Devt is Ownable, ReentrancyGuard, ERC721, Pausable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter private _tokenIds;

    struct ReleaseInfo {
        address maker;
        uint256 index;
        uint256 lp;
        uint256 tokenAmount;
        uint256 amount;
        uint256 amount0;
        uint256 amount1;
        uint256 value;
        uint256 releaseAmount;
        uint256 startTs;
    }

    struct Strategy {
        uint256 percent;
        uint256 duration;
    }
    /***************pair config start**************************/
    mapping(address => bool) public pairToken0IsStableToken;
    mapping(address => bool) public pairEnable;
    mapping(address => uint256) public pairMinLpAmount;
    mapping(address => uint256) public pairMinTokenAmount;
    mapping(address => uint256) public pairMaxLpAmount;
    mapping(address => uint256) public pairMaxTokenAmount;
    /***************pair config end**************************/

    IOracle public immutable Oracle;
    UniHelper public immutable uniHelper;
    address public immutable stToken;
    address public immutable stPair;
    bool public immutable stIsToken0;

    uint256 public limitStakeToken;
    uint256 public limitStakeLp;
    uint256 public stakedToken;
    uint256 public stakedLp;
    uint256 public releasedAmount;

    mapping(uint256 => Strategy) public strategys;
    mapping(uint256 => ReleaseInfo) public releaseInfo;
    mapping(uint256 => uint256) public strategy2tvl;
    mapping(address => mapping(uint256 => uint256)) public userStrategyUnstakeAmount;

    event SetLimitValue(uint256 token, uint256 lp);
    event StrategyUpdate(uint256 strategy, uint256 percent, uint256 duration);
    event SetPair(
        address pair,
        bool token0IsStableToken,
        bool enable,
        uint256 minLpAmount,
        uint256 maxLpAmount,
        uint256 minTokenAmount,
        uint256 maxTokenAmount
    );
    event Stake(
        address player,
        address pair,
        uint256 strategy,
        uint256 lp,
        uint256 tokenId,
        uint256 amount,
        uint256 amount0,
        uint256 amount1,
        uint256 value,
        uint256 price
    );
    event Unstake(address reciver, uint256 token, uint256 amount);

    constructor(
        address _stToken,
        address _stPair,
        address _oracle,
        address _router,
        bool _stIsToken0
    ) public ERC721('Devt ST', 'DST') {
        require(address(0) != _stToken, 'set stToken to the zero address.');
        require(address(0) != _stPair, 'set stPair to the zero address.');
        require(address(0) != _oracle, 'set Oracle to the zero address.');
        require(address(0) != _router, 'set router to the zero address.');
        stToken = _stToken;
        stPair = _stPair;
        stIsToken0 = _stIsToken0;
        Oracle = IOracle(_oracle);
        uniHelper = new UniHelper(_router);
        strategys[0] = Strategy(7000, 7 * 7 minutes); // one main strategy , the rest is another main strategy
        strategys[1] = Strategy(9000, 1 * 7 minutes);
        strategys[2] = Strategy(8800, 2 * 7 minutes);
    }

    function updateStrategy(
        uint256 index,
        uint256 percent,
        uint256 duration
    ) external onlyOwner {
        strategys[index] = Strategy(percent, duration);
        emit StrategyUpdate(index, percent, duration);
    }

    function switchStakeEnable() external onlyOwner {
        paused() ? _unpause() : _pause();
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _setBaseURI(uri);
    }

    function setLimitValue(uint256 _limitStakeToken, uint256 _limitStakeLp) external onlyOwner {
        limitStakeToken = _limitStakeToken;
        limitStakeLp = _limitStakeLp;
        emit SetLimitValue(limitStakeToken, limitStakeLp);
    }

    function withdrawExtraToken() external onlyOwner {
        uint256 stBalance = IERC20(stToken).balanceOf(address(this));
        if (stBalance > 0) {
            SafeERC20.safeTransfer(IERC20(stToken), msg.sender, stBalance);
        }
    }

    function getLpAmount(address pair, uint256 lp) external view returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = UniswapV2LiquidityMathLibrary.getLiquidityValue(
            IUniswapV2Pair(pair).factory(),
            IUniswapV2Pair(pair).token0(),
            IUniswapV2Pair(pair).token1(),
            lp
        );
    }

    function getCurrNFTCount() external view returns (uint256) {
        return _tokenIds.current();
    }

    function setPair(
        address pair,
        bool _token0IsStableToken,
        bool enable,
        uint256 minLpAmount,
        uint256 minTokenAmount,
        uint256 maxLpAmount,
        uint256 maxTokenAmount
    ) external onlyOwner {
        pairToken0IsStableToken[pair] = _token0IsStableToken;
        pairEnable[pair] = enable;
        pairMinLpAmount[pair] = minLpAmount;
        pairMinTokenAmount[pair] = minTokenAmount;
        pairMaxLpAmount[pair] = maxLpAmount;
        pairMaxTokenAmount[pair] = maxTokenAmount;
        emit SetPair(pair, _token0IsStableToken, enable, minLpAmount, maxLpAmount, minTokenAmount, maxTokenAmount);
    }

    function batchUnstake(uint256[] calldata tokens) external {
        for (uint256 index = 0; index < tokens.length; index++) {
            require(ownerOf(tokens[index]) == msg.sender, 'ST: token owner error bath unstake');
            this.unstake(tokens[index]);
        }
    }

    function unstake(uint256 tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender || msg.sender == address(this), 'ST: token owner error');
        ReleaseInfo storage info = releaseInfo[tokenId];
        uint256 amount = calcUnstakeAmount(tokenId);
        require(amount > 0, 'ST: no token to unstake');
        uint256 stBalance = IERC20(stToken).balanceOf(address(this));
        require(stBalance >= amount, 'ST: no enough token to unstake');
        info.releaseAmount = info.releaseAmount.add(amount);
        releasedAmount = releasedAmount.add(amount);
        userStrategyUnstakeAmount[ownerOf(tokenId)][info.index] = userStrategyUnstakeAmount[ownerOf(tokenId)][
            info.index
        ].add(amount);
        SafeERC20.safeTransfer(IERC20(stToken), ownerOf(tokenId), amount);
        emit Unstake(ownerOf(tokenId), tokenId, amount);
    }

    function calcUnstakeAmount(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), 'ST: token not found');
        ReleaseInfo storage info = releaseInfo[tokenId];
        uint256 amount = 0;
        if (info.index > 0) {
            if (info.releaseAmount < info.amount) {
                uint256 remainAmount = info.amount.sub(info.releaseAmount);
                amount = info.amount.div(strategys[info.index].duration).mul((block.timestamp.sub(info.startTs)));
                amount = amount.sub(info.releaseAmount);
                if (amount > remainAmount) amount = remainAmount;
            }
        } else {
            uint256 endTs = strategys[info.index].duration + info.startTs;
            if (block.timestamp >= endTs && block.timestamp <= (endTs + 1 days) && info.releaseAmount == 0) {
                uint256 price = getStPrice().mul(strategys[info.index].percent).div(10000);
                amount = info.value.div(price);
            }
        }
        return amount;
    }

    function stakeToken(
        address pair,
        uint256 amount,
        uint256 amountSwapOutMin,
        uint256 deadline,
        uint256 s
    ) external nonReentrant whenNotPaused {
        require(pairEnable[pair] == true, 'ST: pair not enable');
        require(amount >= pairMinTokenAmount[pair], 'ST: token value must gt the min amount');
        require(amount <= pairMaxTokenAmount[pair], 'ST: token value must lt the max amount');
        require(stakedToken.add(amount) <= limitStakeToken, 'ST: overflow limit value');
        stakedToken = stakedToken.add(amount);
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        address tokenA = pairToken0IsStableToken[pair] ? token0 : token1;
        address tokenB = pairToken0IsStableToken[pair] ? token1 : token0;
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, address(this), amount);
        if (IERC20(tokenA).allowance(address(this), address(uniHelper)) == 0) {
            SafeERC20.safeApprove(IERC20(tokenA), address(uniHelper), uint256(-1));
        }
        (uint256 lp, uint256 amountA, uint256 amountB) = uniHelper.singleTokenAddLp(
            pair,
            tokenA,
            amount,
            amountSwapOutMin,
            deadline
        );
        _stake(pair, lp, s);
        if (amountA > 0) SafeERC20.safeTransfer(IERC20(tokenA), msg.sender, amountA);
        if (amountB > 0) SafeERC20.safeTransfer(IERC20(tokenB), msg.sender, amountB);
        ReleaseInfo storage info = releaseInfo[this.getCurrNFTCount()];
        info.tokenAmount = amount.sub(amountA);
    }

    function stake(
        address pair,
        uint256 lp,
        uint256 s
    ) public nonReentrant whenNotPaused {
        require(pairEnable[pair] == true, 'ST: pair not enable');
        require(lp >= pairMinLpAmount[pair], 'ST:lp value must gt the min amount');
        require(lp <= pairMaxLpAmount[pair], 'ST:lp value must lt the max amount');
        require(stakedLp.add(lp) <= limitStakeLp, 'ST: overflow limit value');
        stakedLp = stakedLp.add(lp);
        SafeERC20.safeTransferFrom(IERC20(pair), msg.sender, address(this), lp);
        _stake(pair, lp, s);
    }

    function _stake(
        address pair,
        uint256 lp,
        uint256 s
    ) internal {
        Strategy storage strategy = strategys[s];
        require(strategy.duration > 0 && strategy.percent > 0, 'ST:strategy not found ');
        strategy2tvl[s] = strategy2tvl[s].add(lp);
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
            value = amount0.add(amount_);
        } else {
            (uint256 _amount, bool effect) = Oracle.consult(pair, IUniswapV2Pair(pair).token0(), amount0);
            require(effect == true && _amount > 0, 'ST:Oracle not update 1');
            value = amount1.add(_amount);
        }
        require(value > 0, 'ST: lp value is zero');
        value = value.mul(1e6); // for price enlarged 1e18, but this decimals diff 12 ,so the value just enarge 1e6
        uint256 price = getStPrice().mul(strategy.percent).div(10000);
        uint256 amount = value.div(price);
        uint256 tokenId = _mintToken();
        releaseInfo[tokenId] = ReleaseInfo(msg.sender, s, lp, 0, amount, amount0, amount1, value, 0, block.timestamp);
        emit Stake(msg.sender, pair, s, lp, tokenId, amount, amount0, amount1, value, price);
    }

    function _mintToken() internal returns (uint256) {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _mint(msg.sender, tokenId);
        return tokenId;
    }

    function getStPrice() public view returns (uint256) {
        (uint256 token0Price, uint256 token1Price) = Oracle.tokenPirceWith18(stPair);
        uint256 price = stIsToken0 ? token0Price : token1Price;
        require(price > 0, 'ST:price is zero');
        return price;
    }
}

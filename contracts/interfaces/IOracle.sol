pragma solidity >=0.5.0;
interface IOracle {
    function consult(
        address pair,
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bool effect);

    function tokenPirceWith18(address pair) external view returns (uint256, uint256);
}

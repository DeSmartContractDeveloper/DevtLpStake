pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;
import '@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol';

contract ERC20Me is ERC20Burnable {
    constructor(string memory name,string memory symbol) public ERC20(name, symbol) {
        _mint(msg.sender, 10**9 * 10**18);
    }
}

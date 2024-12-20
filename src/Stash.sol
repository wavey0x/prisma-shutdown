// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Stash {
    address immutable public psm;
    IERC20 immutable public token;

    constructor(address _token) {
        psm = msg.sender;
        token = IERC20(_token);
        token.approve(psm, type(uint256).max);
    }
}
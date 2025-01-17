pragma solidity ^0.8.13;

interface IFeeReceiver {
    function owner() external view returns (address);
    function setTokenApproval(address token, address spender, uint256 amount) external;
}
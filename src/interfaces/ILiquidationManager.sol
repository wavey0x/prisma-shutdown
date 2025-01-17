// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface ILiquidationManager {
    function liquidationManager() external view returns (address);

    function liquidate(address borrower) external;

    function liquidateTroves(
        address troveManager,
        uint256 maxTrovesToLiquidate,
        uint256 maxICR
    ) external;

    function batchLiquidateTroves(
        address troveManager,
        address[] memory _troveArray
    ) external;
}
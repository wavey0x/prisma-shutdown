// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IPrismaFactory {
    struct DeploymentParams {
        uint256 minuteDecayFactor;
        uint256 redemptionFeeFloor;
        uint256 maxRedemptionFee;
        uint256 borrowingFeeFloor;
        uint256 maxBorrowingFee;
        uint256 interestRateInBps;
        uint256 maxDebt;
        uint256 MCR;
    }

    event NewDeployment(address collateral, address priceFeed, address troveManager, address sortedTroves);

    function debtToken() external view returns (address);
    function stabilityPool() external view returns (address);
    function liquidationManager() external view returns (address);
    function borrowerOperations() external view returns (address);
    
    function sortedTrovesImpl() external view returns (address);
    function troveManagerImpl() external view returns (address);
    
    function troveManagers(uint256) external view returns (address);
    function troveManagerCount() external view returns (uint256);

    function deployNewInstance(
        address collateral,
        address priceFeed,
        address customTroveManagerImpl,
        address customSortedTrovesImpl,
        DeploymentParams memory params
    ) external;

    function setImplementations(address _troveManagerImpl, address _sortedTrovesImpl) external;

    function owner() external view returns (address);
}

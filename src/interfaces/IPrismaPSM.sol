// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPrismaPSM {
    // Events
    event DebtTokenBought(address indexed account, bool indexed troveClosed, uint256 amount);
    event DebtTokenSold(address indexed account, uint256 amount);
    event MaxBuySet(uint256 maxBuy);
    event OwnerSet(address indexed owner);
    event Paused();
    event PSMGuardianSet(address indexed psmGuardian);
    event ERC20Recovered(address indexed tokenAddress, uint256 tokenAmount);

    // View Functions
    function debtToken() external view returns (address);
    function buyToken() external view returns (address);
    function borrowerOps() external view returns (address);
    function psmGuardian() external view returns (address);
    function maxBuy() external view returns (uint256);
    function owner() external view returns (address);
    function isValidTroveManager(address _troveManager) external view returns (bool);
    function getRepayAmount(address _troveManager, address _account, uint256 _amount) 
        external view returns (uint256 amount, bool troveClosed);

    // State-Changing Functions
    function repayDebt(
        address _troveManager,
        address _account,
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external returns (uint256);
    
    function sellDebtToken(uint256 amount) external returns (uint256);
    function setMaxBuy(uint256 _maxBuy) external;
    function pause() external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function setPSMGuardian(address _psmGuardian) external;

    // Optional TroveManager Interface Functions
    function fetchPrice() external view returns (uint256);
    function setAddresses(address, address, address) external;
    function setParameters(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external;
    function collateralToken() external view returns (address);
    function getTroveStatus(address) external view returns (uint256);
    function getTroveCollAndDebt(address) external view returns (uint256, uint256);
    function getEntireDebtAndColl(address) external view returns (uint256, uint256, uint256, uint256);
    function getEntireSystemColl() external view returns (uint256);
    function getEntireSystemDebt() external view returns (uint256);
    function getEntireSystemBalances() external view returns (uint256, uint256, uint256);
    function getNominalICR(address) external view returns (uint256);
    function getCurrentICR(address) external view returns (uint256);
    function getTotalActiveCollateral() external view returns (uint256);
    function getTotalActiveDebt() external view returns (uint256);
    function getPendingCollAndDebtRewards(address) external view returns (uint256, uint256);
    function hasPendingRewards(address) external view returns (bool);
    function getRedemptionRate() external view returns (uint256);
    function getRedemptionRateWithDecay(uint256) external view returns (uint256);
    function getRedemptionFeeWithDecay(address) external view returns (uint256);
    function getBorrowingRate(address) external view returns (uint256);
    function getBorrowingRateWithDecay(address) external view returns (uint256);
    function getBorrowingFeeWithDecay(address) external view returns (uint256);
}
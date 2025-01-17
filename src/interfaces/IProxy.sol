// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProxy {

    function CRV() external view returns (address);
    function gaugeController() external view returns (address);
    function minter() external view returns (address);
    function votingEscrow() external view returns (address);
    function feeDistributor() external view returns (address);
    function feeToken() external view returns (address);
    
    function crvFeePct() external view returns (uint64);
    function unlockTime() external view returns (uint64);
    function voteManager() external view returns (address);
    function depositManager() external view returns (address);
    function perGaugeApproval(address caller) external view returns (address);

    function setExecutePermissions(
        address caller,
        address target,
        bytes4[] memory selectors,
        bool permitted
    ) external returns (bool);

    function setCrvFeePct(uint64 _feePct) external returns (bool);
    function setVoteManager(address _voteManager) external returns (bool);
    function setDepositManager(address _depositManager) external returns (bool);
    function setPerGaugeApproval(address caller, address gauge) external returns (bool);
    function claimFees() external returns (uint256);
    function lockCRV() external returns (bool);

    function mintCRV(address gauge, address receiver) external returns (uint256);
    function approveGaugeDeposit(address gauge, address depositor) external returns (bool);
    function setGaugeRewardsReceiver(address gauge, address receiver) external returns (bool);

    function withdrawFromGauge(
        address gauge,
        address lpToken,
        uint256 amount,
        address receiver
    ) external returns (bool);

    function execute(address target, bytes calldata data) external returns (bytes memory);
    function owner() external view returns (address);
}

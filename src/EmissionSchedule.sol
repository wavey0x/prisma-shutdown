// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract EmissionSchedule {
    function getReceiverWeeklyEmissions(
        uint256 id,
        uint256 week,
        uint256 totalWeeklyEmissions
    ) external returns (uint256) {
        return 0;
    }

    function getTotalWeeklyEmissions(
        uint256 week,
        uint256 unallocatedTotal
    ) external returns (uint256 amount, uint256 lock) {
        return (amount, lock);
    }
}
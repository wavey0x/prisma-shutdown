// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract BoostCalculator {

    /**
        @notice Get the adjusted claim amount after applying an account's boost
        @param account Address claiming the reward
        @param amount Amount being claimed (assuming maximum boost)
        @param previousAmount Amount that was already claimed in the current week
        @param totalWeeklyEmissions Total PRISMA emissions released this week
        @return adjustedAmount Amount of PRISMA received after applying boost
     */
    function getBoostedAmount(
        address account,
        uint256 amount,
        uint256 previousAmount,
        uint256 totalWeeklyEmissions
    ) external view returns (uint256 adjustedAmount) {
        return 0;
    }

    /**
        @notice Get the remaining claimable amounts this week that will receive boost
        @param claimant address to query boost amounts for
        @param previousAmount Amount that was already claimed in the current week
        @param totalWeeklyEmissions Total PRISMA emissions released this week
        @return maxBoosted remaining claimable amount that will receive max boost
        @return boosted remaining claimable amount that will receive some amount of boost (including max boost)
     */
    function getClaimableWithBoost(
        address claimant,
        uint256 previousAmount,
        uint256 totalWeeklyEmissions
    ) external view returns (uint256 maxBoosted, uint256 boosted) {
        return (0, 0);
    }

    /**
        @notice Get the adjusted claim amount after applying an account's boost
        @dev Stores lock weights and percents to reduce cost on future calls
        @param account Address claiming the reward
        @param amount Amount being claimed (assuming maximum boost)
        @param previousAmount Amount that was already claimed in the current week
        @param totalWeeklyEmissions Total PRISMA emissions released this week
        @return adjustedAmount Amount of PRISMA received after applying boost
     */
    function getBoostedAmountWrite(
        address account,
        uint256 amount,
        uint256 previousAmount,
        uint256 totalWeeklyEmissions
    ) external returns (uint256 adjustedAmount) {
        return 0;
    }
}

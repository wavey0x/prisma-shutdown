// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract EmissionSchedule {
    event WeeklyPctScheduleSet(uint64[2][] schedule);
    event LockParametersSet(uint256 lockWeeks, uint256 lockDecayWeeks);

    uint256 constant MAX_PCT = 10000;
    uint256 public constant MAX_LOCK_WEEKS = 52;

    uint64 public lockWeeks;
    uint64 public lockDecayWeeks;
    uint64 public weeklyPct;
    uint64[2][] private scheduledWeeklyPct;


    function getWeeklyPctSchedule() external view returns (uint64[2][] memory) {
        return scheduledWeeklyPct;
    }

    function setWeeklyPctSchedule(uint64[2][] memory _schedule) external returns (bool) {}

    function setLockParameters(uint64 _lockWeeks, uint64 _lockDecayWeeks) external returns (bool) {}

    function getReceiverWeeklyEmissions(
        uint256 id,
        uint256 week,
        uint256 totalWeeklyEmissions
    ) external returns (uint256) {}

    function getTotalWeeklyEmissions(
        uint256 week,
        uint256 unallocatedTotal
    ) external returns (uint256 amount, uint256 lock) {}

    function _setWeeklyPctSchedule(uint64[2][] memory _scheduledWeeklyPct) internal {}
}

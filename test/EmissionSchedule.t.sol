// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EmissionSchedule } from "src/EmissionSchedule.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IStabilityPool } from "src/interfaces/IStabilityPool.sol";

contract EmissionScheduleTest is Test {
    EmissionSchedule public emissionsSchedule;
    IERC20 public constant prisma = IERC20(0xdA47862a83dac0c112BA89c6abC2159b95afd71C);
    IVault public constant vault = IVault(0x06bDF212C290473dCACea9793890C5024c7Eb02c);
    IStabilityPool public constant stabilityPool = IStabilityPool(0xed8B26D99834540C5013701bB3715faFD39993Ba);
    IERC20 public constant mkUSD = IERC20(0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28);
    address public constant CONVEX_VOTER = 0x8ad7a9e2B3Cd9214f36Cb871336d8ab34DdFdD5b;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        emissionsSchedule = new EmissionSchedule();
    }

    function test_EmissionsAreZero() public {
        migrateEmissionSchedule();
        depositToSP(10_000_000e18);
        skip(100 weeks); // earn rewards
        (uint256 adjustedAmount, uint256 feeToDelegate) = vault.claimableRewardAfterBoost(address(this), CONVEX_VOTER, CONVEX_VOTER, address(stabilityPool));
        assertEq(adjustedAmount, 0);
        assertEq(feeToDelegate, 0);

        address[] memory rewardContracts = new address[](1);
        rewardContracts[0] = address(stabilityPool);
        vault.batchClaimRewards(address(this), CONVEX_VOTER, rewardContracts, 10_000);
    }

    // migrate and skip by 1 week to enter first epoch with no emissions
    function migrateEmissionSchedule() public {
        vm.prank(vault.owner());
        vault.setEmissionSchedule(address(emissionsSchedule));
        skip(1 weeks);
    }

    function depositToSP(uint256 amount) public {
        deal(address(mkUSD), address(this), amount);
        mkUSD.approve(address(stabilityPool), amount);
        stabilityPool.provideToSP(amount);
    }
}

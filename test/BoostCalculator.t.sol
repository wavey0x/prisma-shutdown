// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BoostCalculator } from "src/BoostCalculator.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IStabilityPool } from "src/interfaces/IStabilityPool.sol";

contract BoostCalculatorTest is Test {
    BoostCalculator public boostCalculator;
    IERC20 public constant prisma = IERC20(0xdA47862a83dac0c112BA89c6abC2159b95afd71C);
    IVault public constant vault = IVault(0x06bDF212C290473dCACea9793890C5024c7Eb02c);
    IStabilityPool public constant stabilityPool = IStabilityPool(0xed8B26D99834540C5013701bB3715faFD39993Ba);
    IERC20 public constant mkUSD = IERC20(0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28);
    address public constant CONVEX_VOTER = 0x8ad7a9e2B3Cd9214f36Cb871336d8ab34DdFdD5b;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        boostCalculator = new BoostCalculator();
        depositToSP(10_000_000e18);
        skip(1 weeks); // earn rewards
    }

    function test_BoostedAmount() public {
        (uint256 adjustedAmount, uint256 feeToDelegate) = vault.claimableRewardAfterBoost(address(this), CONVEX_VOTER, CONVEX_VOTER, address(stabilityPool));
        assertGt(adjustedAmount, 0);
        assertGt(feeToDelegate, 0);
        migrateBoostCalculator();
        (adjustedAmount, feeToDelegate) = vault.claimableRewardAfterBoost(address(this), CONVEX_VOTER, CONVEX_VOTER, address(stabilityPool));
        assertEq(adjustedAmount, 0);
        assertEq(feeToDelegate, 0);

        address[] memory rewardContracts = new address[](1);
        rewardContracts[0] = address(stabilityPool);
        vault.batchClaimRewards(address(this), CONVEX_VOTER, rewardContracts, 10_000);
    }

    function migrateBoostCalculator() public {
        vm.prank(vault.owner());
        vault.setBoostCalculator(address(boostCalculator));
    }

    function depositToSP(uint256 amount) public {
        deal(address(mkUSD), address(this), amount);
        mkUSD.approve(address(stabilityPool), amount);
        stabilityPool.provideToSP(amount);
    }
}

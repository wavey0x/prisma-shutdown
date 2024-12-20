// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";
import { IBorrowerOperations } from "src/interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "src/interfaces/ITroveManager.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";

contract PrismaPSMTest is Test {
    IPrismaFactory public constant factory = IPrismaFactory(0x70b66E20766b775B2E9cE5B718bbD285Af59b7E1);
    address public constant troveManager = 0x1CC79f3F47BfC060b6F761FcD1afC6D399a968B6;
    address public constant borrowerOps = 0x72c590349535AD52e6953744cb2A36B409542719;
    address public constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address public constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    PrismaPSM public psmImpl;

    PrismaPSM public psm;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        psmImpl = new PrismaPSM(mkUSD, crvUSD, borrowerOps);
        vm.prank(factory.owner());
        factory.deployNewInstance(
            address(0), 
            address(0), 
            address(psmImpl), 
            address(0), 
            IPrismaFactory.DeploymentParams({
                minuteDecayFactor: 100,
                redemptionFeeFloor: 0,
                maxRedemptionFee: 0,
                borrowingFeeFloor: 0,
                maxBorrowingFee: 0,
                interestRateInBps: 0,
                maxDebt: 0,
                MCR: 0
        }));
        uint256 troveManagerCount = factory.troveManagerCount();
        psm = PrismaPSM(factory.troveManagers(troveManagerCount - 1));
        console.log("psmAddress", address(psm));
        deal(wsteth, address(this), 100e18);
        deal(crvUSD, address(this), 100_000e18);
        IERC20(wsteth).approve(address(troveManager), type(uint256).max);
        IERC20(wsteth).approve(address(borrowerOps), type(uint256).max);
        IERC20(crvUSD).approve(address(psm), type(uint256).max);
        IERC20(psm.debtToken()).approve(address(psm), type(uint256).max);
        IBorrowerOperations(borrowerOps).setDelegateApproval(address(psm), true);

        console.log("psm owner", psm.owner());
        vm.startPrank(psm.owner());
        psm.setMaxUnlock(100_000e18);
        psm.setRate(100e18);
        vm.stopPrank();

        vm.label(address(psm), "PSM");
    }

    function test_RepayDebtAndCloseTrove() public {
        openTrove(50_000e18);
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        console.log("before repay debt coll", coll);
        console.log("before repay debt debt", debt);
        psm.repayDebt(ITroveManager(troveManager), address(this), 55_000e18);
        (debt, coll) = getCollAndDebt(address(this));
        console.log("after repay debt coll", coll);
        console.log("after repay debt debt", debt);
        assertEq(debt, 0);
        assertEq(coll, 0);
    }

    function test_RepayDebtPartial() public {
        openTrove(50_000e18);
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        console.log("before repay debt coll", coll);
        console.log("before repay debt debt", debt);
        psm.repayDebt(
            ITroveManager(troveManager), 
            address(this), 
            5_000e18
        );
        (debt, coll) = getCollAndDebt(address(this));
        console.log("after repay debt coll", coll);
        console.log("after repay debt debt", debt);
        assertGt(debt, 0);
        assertGt(coll, 0);
    }

    function openTrove(uint256 debtAmount) public {
        uint256 collatAmount = 100e18;
        IBorrowerOperations(borrowerOps).openTrove(
            troveManager,
            address(this),  // account
            10_000,         // maxFeePercentage
            collatAmount,   // collateralAmount
            debtAmount,     // debtAmount
            address(0),     // upperHint
            address(0)      // lowerHint
        );
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        console.log("coll", coll);
        console.log("debt", debt);
        assertGt(coll, 0);
        assertGt(debt, 0);
    }

    function test_SellDebtToken(uint256 amount) public {
        deal(address(psm.buyToken()), address(psm), amount);
        deal(address(psm.debtToken()), address(this), amount);
        psm.sellDebtToken(amount);
        assertEq(IERC20(address(psm.buyToken())).balanceOf(address(psm)), amount);
        assertEq(IERC20(address(psm.debtToken())).balanceOf(address(this)), amount);
    }

    function getCollAndDebt(address account) public view returns (uint256 coll, uint256 debt) {
        (coll, debt) = ITroveManager(troveManager).getTroveCollAndDebt(account);
    }
}

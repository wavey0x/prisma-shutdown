// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";
import { IBorrowerOperations } from "src/interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "src/interfaces/ITroveManager.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";
import { IMultiCollateralHintHelpers } from "src/interfaces/IMultiCollateralHintHelpers.sol";
import { ISortedTroves } from "src/interfaces/ISortedTroves.sol";

contract PrismaPSMTest is Test {
    IPrismaFactory public constant factory = IPrismaFactory(0x70b66E20766b775B2E9cE5B718bbD285Af59b7E1);
    IMultiCollateralHintHelpers public constant hintHelper = IMultiCollateralHintHelpers(0x3C5871D69C8d6503001e1A8f3bF7E5EbE447A9Cd);
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
        IERC20(wsteth).approve(address(troveManager), type(uint256).max);
        IERC20(wsteth).approve(address(borrowerOps), type(uint256).max);
        IERC20(crvUSD).approve(address(psm), type(uint256).max);
        IBorrowerOperations(borrowerOps).setDelegateApproval(address(psm), true);

        psm.setOwner(address(this));
        assertEq(psm.owner(), psm.DEFAULT_OWNER());

        vm.startPrank(psm.owner());
        psm.setMaxBuy(100_000e18);
        psm.setRate(1_000e18 / uint256(60)); // $1k per 60 seconds
        vm.stopPrank();

        console.log("psm owner", psm.owner());
        vm.label(address(psm), "PSM");
    }

    function test_DebtTokenReserve() public {
        for (uint256 i = 0; i < 10; i++) {
            (uint256 debtTokenReserve, uint256 buyTokenReserve) = psm.getReserves();
            console.log("debt token reserves after", i * 10, "minutes", debtTokenReserve);
            console.log("buy token reserves after", i * 10, "minutes", buyTokenReserve);
            skip(10 minutes);
        }
    }

    function test_RepayDebtAndCloseTrove() public {
        deal(crvUSD, address(this), 100_000e18);
        openTrove(50_000e18);
        uint256 toRepay = 55_000e18;
        // allow reserves to grow
        skip(toRepay / psm.rate() + 1);
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        uint256 newDebt = debt > toRepay ? debt - toRepay : 0;
        (address upperHint, address lowerHint) = getHints(coll, newDebt);
        console.log("upperHint", upperHint);
        console.log("lowerHint", lowerHint);
        psm.repayDebt(
            troveManager, 
            address(this), 
            toRepay,
            upperHint,
            lowerHint
        );
        (debt, coll) = getCollAndDebt(address(this));
        assertEq(debt, 0);
        assertEq(coll, 0);
    }

    function test_RepayDebtPartial() public {
        deal(crvUSD, address(this), 100_000e18);
        uint256 toRepay = 20_000e18;
        openTrove(toRepay*3);
        skip(toRepay / psm.rate() + 1);
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        uint256 newDebt = debt > toRepay ? debt - toRepay : 0;
        (address upperHint, address lowerHint) = getHints(coll, newDebt);
        console.log("upperHint", upperHint);
        console.log("lowerHint", lowerHint);
        psm.repayDebt(
            troveManager, 
            address(this), 
            toRepay,
            upperHint,
            lowerHint
        );
        (debt, coll) = getCollAndDebt(address(this));
        assertGt(debt, 0);
        assertGt(coll, 0);
    }

    function test_Pause() public {
        skip(1 days);
        uint256 debtTokenReserve = psm.getDebtTokenReserve();
        assertGt(debtTokenReserve, 0);

        vm.startPrank(psm.owner());
        psm.pause();
        vm.stopPrank();

        assertEq(psm.getDebtTokenReserve(), 0);
        assertEq(psm.rate(), 0);
        assertEq(psm.maxBuy(), 0);
    }


    function test_SellDebtToken(uint256 amount) public {
        amount = bound(amount, 0, type(uint112).max);
        deal(address(psm.buyToken()), address(psm), amount);
        deal(address(psm.debtToken()), address(this), amount);
        uint256 balBefore = debtTokenBalance(address(this));
        psm.sellDebtToken(amount);
        assertEq(buyTokenBalance(address(this)), amount);
        if (amount > 0) assertLt(debtTokenBalance(address(this)), balBefore);
    }

    function test_CannotSellMoreThanOwned() public {
        deal(address(psm.debtToken()), address(this), 1e18);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        psm.sellDebtToken(100_001e18);
    }

    function test_SetOwner() public {
        vm.expectRevert("PSM: !owner");
        psm.setOwner(address(this));

        vm.startPrank(psm.owner());
        psm.setOwner(address(this));
        vm.stopPrank();
        assertEq(psm.owner(), address(this));
    }

    function buyTokenBalance(address account) public view returns (uint256) {
        return IERC20(address(psm.buyToken())).balanceOf(account);
    }

    function debtTokenBalance(address account) public view returns (uint256) {
        return IERC20(address(psm.debtToken())).balanceOf(account);
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
        assertGt(coll, 0);
        assertGt(debt, 0);
    }

    function getCollAndDebt(address account) public view returns (uint256 coll, uint256 debt) {
        (coll, debt) = ITroveManager(troveManager).getTroveCollAndDebt(account);
    }

    function getHints(uint256 coll, uint256 debt) public returns (address upperHint, address lowerHint) {
        ISortedTroves sortedTroves = ISortedTroves(ITroveManager(troveManager).sortedTroves());
        uint256 price = ITroveManager(troveManager).fetchPrice();
        uint256 cr = hintHelper.computeCR(coll, debt, price);
        uint256 NICR = hintHelper.computeNominalCR(coll, debt);

        (address approxHint,,) = hintHelper.getApproxHint(
            troveManager, 
            cr, 
            50,
            1
        );
        
        (upperHint, lowerHint) = sortedTroves.findInsertPosition(
            NICR, 
            approxHint, 
            approxHint
        );
    }
}
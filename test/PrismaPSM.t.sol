// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";
import { IBorrowerOperations } from "src/interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "src/interfaces/ITroveManager.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";
import { IMultiCollateralHintHelpers } from "src/interfaces/IMultiCollateralHintHelpers.sol";
import { ISortedTroves } from "src/interfaces/ISortedTroves.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";

contract PrismaPSMTest is Test {
    address constant GUARDIAN = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    IPrismaFactory public constant factory = IPrismaFactory(0x70b66E20766b775B2E9cE5B718bbD285Af59b7E1);
    IMultiCollateralHintHelpers public constant hintHelper = IMultiCollateralHintHelpers(0x3C5871D69C8d6503001e1A8f3bF7E5EbE447A9Cd);
    address public constant troveManager = 0x1CC79f3F47BfC060b6F761FcD1afC6D399a968B6;
    address public constant borrowerOps = 0x72c590349535AD52e6953744cb2A36B409542719;
    address public constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address public constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant exampleUser = 0x158E7aA19493a7AC5c9C84972fEd6d622bFAB0C8;

    PrismaPSM public psmImpl;

    PrismaPSM public psm;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        IPrismaCore core = IPrismaCore(CORE);
        psmImpl = new PrismaPSM(CORE, mkUSD, crvUSD, borrowerOps);
        assertEq(psmImpl.owner(), core.owner());

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
        assertEq(psm.owner(), core.owner());
        console.log("psmAddress", address(psm));
        deal(wsteth, address(this), 1_000_000e18);
        IERC20(wsteth).approve(address(troveManager), type(uint256).max);
        IERC20(wsteth).approve(address(borrowerOps), type(uint256).max);
        IERC20(crvUSD).approve(address(psm), type(uint256).max);
        IBorrowerOperations(borrowerOps).setDelegateApproval(address(psm), true);

        vm.prank(psm.owner());
        psm.setPSMGuardian(address(this));
        assertEq(psm.psmGuardian(), address(this));

        vm.startPrank(psm.owner());
        psm.setMaxBuy(100_000e18);
        vm.stopPrank();

        console.log("psm owner", psm.owner());
        vm.label(address(psm), "PSM");

        // Debt caps are closed, but we need to open them to test
        ITroveManager tm = ITroveManager(troveManager);
        vm.startPrank(tm.owner());
        tm.setParameters(
            tm.minuteDecayFactor(),
            tm.redemptionFeeFloor(),
            tm.maxRedemptionFee(),
            tm.borrowingFeeFloor(),
            tm.maxBorrowingFee(),
            (tm.interestRate() * 10_000 * 31_536_000) / 1e27, // Convert to BPS
            100_000_000e18,
            tm.MCR()
        );
        vm.stopPrank();

        vm.label(exampleUser, "ExampleUser");
    }

    function test_RepayDebtAndCloseTrove() public {
        deal(crvUSD, address(this), 100_000e18);
        openTrove(50_000e18);
        uint256 toRepay = 55_000e18;
        // allow reserves to grow
        (uint256 startColl, uint256 debt) = getCollAndDebt(address(this));
        uint256 newDebt = debt > toRepay ? debt - toRepay : 0;
        (address upperHint, address lowerHint) = getHints(startColl, newDebt);
        console.log("upperHint", upperHint);
        console.log("lowerHint", lowerHint);
        IERC20 collateralToken = IERC20(ITroveManager(troveManager).collateralToken());
        uint256 preCollateralBalance = collateralToken.balanceOf(address(this));
        requireNoCollateralInPSM(troveManager);
        uint256 repaid = psm.repayDebt(
            troveManager, 
            address(this), 
            toRepay,
            upperHint,
            lowerHint
        );
        requireNoCollateralInPSM(troveManager);
        uint256 postCollateralBalance = collateralToken.balanceOf(address(this));
        uint256 coll;
        (debt, coll) = getCollAndDebt(address(this));
        assertEq(debt, 0, "debt should be 0");
        assertEq(coll, 0, "coll should be 0");
        assertGt(postCollateralBalance, preCollateralBalance, "collateral should be returned to user");
        assertEq(postCollateralBalance - preCollateralBalance, startColl, "collateral should be returned to user");

        if (repaid > 0) {
            deal(address(psm.debtToken()), address(this), repaid);
            vm.expectEmit(true, false, false, true, address(psm));
            emit PrismaPSM.DebtTokenSold(address(this), repaid);
            sellDebtToken(repaid);
        }
    }

    function test_RepayDebtAndCloseTroveRealUser() public {
        vm.startPrank(psm.owner());
        psm.setMaxBuy(type(uint256).max);
        vm.stopPrank();
        vm.startPrank(exampleUser);
        deal(crvUSD, address(exampleUser), 1_000_000e18);
        IBorrowerOperations(borrowerOps).setDelegateApproval(address(psm), true);
        IERC20(crvUSD).approve(address(psm), type(uint256).max);
        uint256 toRepay = 1_500_000e18;
        // allow reserves to grow
        (uint256 coll, uint256 debt) = getCollAndDebt(exampleUser);
        console.log("coll", coll/1e18);
        console.log("debt", debt/1e18);
        (address upperHint, address lowerHint) = getHints(0, 0);
        console.log("upperHint", upperHint);
        console.log("lowerHint", lowerHint);
        requireNoCollateralInPSM(troveManager);
        uint256 repaid = psm.repayDebt(
            troveManager, 
            exampleUser, 
            toRepay,
            upperHint,
            lowerHint
        );
        requireNoCollateralInPSM(troveManager);
        (debt, coll) = getCollAndDebt(exampleUser);
        assertEq(debt, 0, "debt should be 0");
        assertEq(coll, 0, "coll should be 0");

        if (repaid > 0) {
            deal(address(psm.debtToken()), address(exampleUser), repaid);
            vm.expectEmit(true, false, false, true, address(psm));
            emit PrismaPSM.DebtTokenSold(address(exampleUser), repaid);
            sellDebtToken(repaid);
        }
        vm.stopPrank();
    }

    function test_RepayDebtPartial() public {
        deal(crvUSD, address(this), 100_000e18);
        uint256 toRepay = 20_000e18;
        openTrove(toRepay*3);
        (uint256 debt, uint256 coll) = getCollAndDebt(address(this));
        uint256 newDebt = debt > toRepay ? debt - toRepay : 0;
        (address upperHint, address lowerHint) = getHints(coll, newDebt);
        console.log("upperHint", upperHint);
        console.log("lowerHint", lowerHint);
        requireNoCollateralInPSM(troveManager);
        uint256 repaid = psm.repayDebt(
            troveManager, 
            address(this), 
            toRepay,
            upperHint,
            lowerHint
        );
        requireNoCollateralInPSM(troveManager);
        (debt, coll) = getCollAndDebt(address(this));
        assertGt(debt, 0);
        assertGt(coll, 0);


        if (repaid > 0) {
            deal(address(psm.debtToken()), address(this), repaid);
            vm.expectEmit(true, false, false, true, address(psm));
            emit PrismaPSM.DebtTokenSold(address(this), repaid);
            sellDebtToken(repaid);
        }
    }

    function test_SellDebtToken(uint256 amount) public {
        amount = bound(amount, 0, type(uint112).max);
        deal(address(psm.debtToken()), address(this), amount);
        uint256 balBefore = debtTokenBalance(address(this));
        sellDebtToken(amount);
        assertEq(buyTokenBalance(address(this)), amount);
        if (amount > 0) assertLt(debtTokenBalance(address(this)), balBefore);
    }

    function sellDebtToken(uint256 amount) public returns (uint256) {
        if (buyTokenBalance(address(this)) < amount) 
            deal(address(psm.buyToken()), address(psm), amount);
        return psm.sellDebtToken(amount);
    }

    function test_CannotSellMoreThanOwned() public {
        deal(address(psm.debtToken()), address(this), 1e18);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        psm.sellDebtToken(100_001e18);
    }

    function test_Pause() public {
        skip(1 days);
        vm.prank(psm.owner());
        psm.pause();
        assertEq(psm.maxBuy(), 0);
        assertEq(debtTokenBalance(address(psm)), 0);
    }

    function test_SetPSMGuardian() public {
        vm.expectRevert("Only owner");
        psm.setPSMGuardian(address(this));

        vm.startPrank(psm.owner());
        psm.setPSMGuardian(address(this));
        vm.stopPrank();
        assertEq(psm.psmGuardian(), address(this));
    }

    function test_RecoverERC20() public {
        IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint256 amount = 100e18;
        deal(address(DAI), address(psm), amount);

        address owner = psm.owner();
        address debtToken = address(psm.debtToken());
        address buyToken = address(psm.buyToken());

        vm.expectRevert("Only owner");
        psm.recoverERC20(address(DAI), 1e18);

        vm.startPrank(owner);
        vm.expectRevert("PSM: Cannot recover debt token");
        psm.recoverERC20(debtToken, 1e18);
        vm.expectRevert("PSM: Cannot recover buy token");
        psm.recoverERC20(buyToken, 1e18);
        
        assertGt(DAI.balanceOf(address(psm)), 0);
        psm.recoverERC20(address(DAI), DAI.balanceOf(address(psm)));
        assertEq(DAI.balanceOf(address(psm)), 0);
        assertEq(DAI.balanceOf(owner), amount);

        vm.stopPrank();
        assertEq(debtTokenBalance(address(psm)), 0);
    }

    function buyTokenBalance(address account) public view returns (uint256) {
        return IERC20(address(psm.buyToken())).balanceOf(account);
    }

    function debtTokenBalance(address account) public view returns (uint256) {
        return IERC20(address(psm.debtToken())).balanceOf(account);
    }

    function openTrove(uint256 debtAmount) public {
        uint256 price = ITroveManager(troveManager).fetchPrice();
        uint256 targetCr = 3e18;
        uint256 collatAmount = targetCr * price / 1e18;
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

    // use target coll and debt to get hints
    function getHints(uint256 coll, uint256 debt) public view returns (address upperHint, address lowerHint) {
        ISortedTroves sortedTroves = ISortedTroves(ITroveManager(troveManager).sortedTroves());
        uint256 NICR;
        if (debt == 0) {
            NICR = type(uint256).max;
        } else {
            NICR = (coll * 1e20) / debt;
        }

        // Get initial hints
        (address approxHint, uint256 diff, ) = hintHelper.getApproxHint(
            troveManager,
            NICR,
            55,    // Number of trials
            42    // Random seed
        );

        // If no hint found or diff is too large, try with first and last
        if (approxHint == address(0) || diff > 1e20) {
            address first = sortedTroves.getFirst();
            address last = sortedTroves.getLast();
            
            // If list is empty
            if (first == address(0)) {
                return (address(0), address(0));
            }
            
            // Choose hints based on NICR comparison
            uint256 firstNICR = ITroveManager(troveManager).getNominalICR(first);
            if (NICR >= firstNICR) {
                return (address(0), first);
            }
            
            uint256 lastNICR = ITroveManager(troveManager).getNominalICR(last);
            if (NICR <= lastNICR) {
                return (last, address(0));
            }
        }

        (upperHint, lowerHint) = sortedTroves.findInsertPosition(
            NICR,
            approxHint,
            approxHint
        );
    }

    function requireNoCollateralInPSM(address tm) public view {
        IERC20 collateralToken = IERC20(ITroveManager(tm).collateralToken());
        assertEq(collateralToken.balanceOf(address(psm)), 0, "collateral should not be in psm");
    }
}

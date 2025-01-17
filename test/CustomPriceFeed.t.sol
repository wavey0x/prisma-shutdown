pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBorrowerOperations } from "src/interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "src/interfaces/ITroveManager.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { CustomPriceFeed } from "src/CustomPriceFeed.sol";

contract CustomPriceFeedTest is Test {
    address constant GUARDIAN = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    ITroveManager public constant troveManager = ITroveManager(0xe0e255FD5281bEc3bB8fa1569a20097D9064E445); // reETH
    IBorrowerOperations public constant borrowerOps = IBorrowerOperations(0x72c590349535AD52e6953744cb2A36B409542719);
    address public borrower1 = 0x992dac69827A200BA112A0303Fe8F79F03c37D9d;
    address public borrower2 = 0xc4fc07cfEd3E111f09117cDdA1aC8bcD1ff72A75;
    IERC20 public debtToken;
    IERC20 public collateralToken;
    CustomPriceFeed public customPriceFeed;
    IPrismaCore public core;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        debtToken = IERC20(troveManager.debtToken());
        collateralToken = IERC20(troveManager.collateralToken());
        customPriceFeed = new CustomPriceFeed(CORE);
        core = IPrismaCore(CORE);

        vm.label(address(core), "Core");
        vm.label(address(customPriceFeed), "CustomPriceFeed");
        vm.label(address(troveManager), "TroveManager");
        vm.label(address(borrowerOps), "BorrowerOps");
        vm.label(address(debtToken), "DebtToken");
        vm.label(address(collateralToken), "CollateralToken");
    }

    function test_fetchPrice() public {
        uint256 price = customPriceFeed.fetchPrice(address(collateralToken));
        console.log("Price:", price);
    }

    function test_setPriceFeed() public {
        setPriceFeed(address(customPriceFeed));
        assertEq(troveManager.fetchPrice(), type(uint256).max / 100e18);
    }

    function test_BorrowersCanWithdraw() public {
        setPriceFeed(address(customPriceFeed));
        uint256 DUST = 1e2;
        // Withdraw: Borrower 1
        (uint256 coll, ) = troveManager.getTroveCollAndDebt(borrower1);
        console.log("B1 Collateral:", coll);
        uint256 startBalance = collateralToken.balanceOf(borrower1);
        vm.prank(borrower1);
        borrowerOps.withdrawColl(
            address(troveManager),
            borrower1,
            coll - DUST,
            address(0),
            address(0)
        );
        uint256 endBalance = collateralToken.balanceOf(borrower1);
        assertGt(endBalance, startBalance);
        assertEq(endBalance - startBalance, coll - DUST, 'Incorrect amount withdrawn');
        console.log("Collateral withdrawn:", endBalance - startBalance);

        // Withdraw: Borrower 2
        (coll, ) = troveManager.getTroveCollAndDebt(borrower2);
        console.log("B2: Collateral:", coll);
        startBalance = collateralToken.balanceOf(borrower2);
        vm.prank(borrower2);
        borrowerOps.withdrawColl(
            address(troveManager),
            borrower2,
            coll - DUST,
            address(0),
            address(0)
        );
        endBalance = collateralToken.balanceOf(borrower2);
        assertGt(endBalance, startBalance);
        assertEq(endBalance - startBalance, coll - DUST, 'Incorrect amount withdrawn');
        console.log("B2: Collateral withdrawn:", endBalance - startBalance);
    }

    function setPriceFeed(address _priceFeed) public {
        vm.prank(core.owner());
        troveManager.setPriceFeed(_priceFeed);
    }
}

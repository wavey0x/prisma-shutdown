// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";
import { IBorrowerOperations } from "src/interfaces/IBorrowerOperations.sol";

contract PrismaPSMTest is Test {
    address public constant troveManager = 0x1CC79f3F47BfC060b6F761FcD1afC6D399a968B6;
    address public constant borrowerOps = 0x72c590349535AD52e6953744cb2A36B409542719;
    address public constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address public constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    PrismaPSM public psm;

    function setUp() public {
        psm = new PrismaPSM(mkUSD, crvUSD, borrowerOps);
        deal(wsteth, address(this), 100e18);
        IERC20(wsteth).approve(address(troveManager), type(uint256).max);
        IBorrowerOperations(borrowerOps).setDelegateApproval(address(psm), true);
    }

    function test_RepayDebt() public {
        psm.repayDebt();
        assertEq(psm.number(), 1);
    }

    function openTrove() public {
        uint256 collatAmount = 100e18;
        uint256 debtAmount = 50_000e18;
        IBorrowerOperations(borrowerOps).openTrove(
            troveManager,
            address(this), // account
            100e18, // maxFeePercentage
            collatAmount, // collateralAmount
            debtAmount, // debtAmount
            address(0), // upperHint
            address(0) // lowerHint
        );
    }
}

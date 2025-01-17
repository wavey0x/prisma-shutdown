pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITroveManager } from "src/interfaces/ITroveManager.sol";
import { PrismaClaimOperator } from "src/PrismaClaimOperator.sol";
import { IProxy } from "src/interfaces/IProxy.sol";
import { IFeeReceiver } from "src/interfaces/IFeeReceiver.sol";

interface ICurveFeeDistributor {
    function claim(address receiver) external;
    function token() external view returns (address);
}

contract PrismaClaimOperatorTest is Test {
    address constant GUARDIAN = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    IProxy constant PROXY = IProxy(0x490b8C6007fFa5d3728A49c2ee199e51f05D2F7e);
    address constant FEE_DISTRIBUTOR = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;
    IFeeReceiver constant PRISMA_FEE_RECEIVER = IFeeReceiver(0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8);
    address public claimer1 = address(0x1);
    IERC20 public crvUSD;
    PrismaClaimOperator public operator;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        claimer1 = address(0x1);
        operator = new PrismaClaimOperator(
            GUARDIAN, 
            GUARDIAN, 
            FEE_DISTRIBUTOR, 
            address(PROXY),
            address(PRISMA_FEE_RECEIVER)
        );
        crvUSD = IERC20(ICurveFeeDistributor(FEE_DISTRIBUTOR).token());
    }

    function test_CurveFeeClaimOwner() public {
        approveCurveClaims();

        vm.expectRevert("Only authorized");
        operator.claim();
        uint256 balanceBefore = crvUSD.balanceOf(operator.treasury());
        vm.prank(GUARDIAN);
        operator.claim();
        uint256 balanceAfter = crvUSD.balanceOf(operator.treasury());
        assertGt(balanceAfter, balanceBefore);
    }

    function test_CurveFeeClaimTo() public {
        approveCurveClaims();

        vm.expectRevert("Only owner");
        operator.claimTo(address(operator));

        uint256 balanceBefore = crvUSD.balanceOf(address(operator));
        vm.prank(GUARDIAN);
        operator.claimTo(address(operator));
        uint256 balanceAfter = crvUSD.balanceOf(address(operator));
        assertGt(balanceAfter, balanceBefore);
    }

    function test_CurveFeeClaim() public {
        approveCurveClaims();
        vm.expectRevert("Only authorized");
        vm.prank(claimer1);
        operator.claim();

        approveClaimer(true);
        uint256 balanceBefore = crvUSD.balanceOf(operator.treasury());
        vm.prank(claimer1);
        operator.claim();
        uint256 balanceAfter = crvUSD.balanceOf(operator.treasury());
        assertGt(balanceAfter, balanceBefore);

        approveClaimer(false);
        vm.expectRevert("Only authorized");
        vm.prank(claimer1);
        operator.claim();
    }

    function test_Transfers() public {
        deal(address(crvUSD), address(operator), 1000e18);
        approveTokenTransfers(address(crvUSD));
        uint256 balanceBefore = crvUSD.balanceOf(operator.treasury());
        vm.prank(claimer1);
        vm.expectRevert("Only authorized");
        operator.transferFromFeeReceiver(crvUSD);
        approveClaimer(true);
        vm.prank(claimer1);
        operator.transferFromFeeReceiver(crvUSD);
        uint256 balanceAfter = crvUSD.balanceOf(operator.treasury());
        assertEq(balanceAfter, balanceBefore);
    }

    function approveCurveClaims() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("claim(address)"));
        vm.startPrank(PROXY.owner());
        PROXY.setExecutePermissions(
            address(operator),  // user
            FEE_DISTRIBUTOR,    // target
            selectors,          // selectors
            true                // authorized
        );
        selectors[0] = bytes4(keccak256("transfer(address,uint256)"));
        PROXY.setExecutePermissions(
            address(operator),  // user
            address(crvUSD),    // target
            selectors,          // selectors
            true                // authorized
        );
        vm.stopPrank();
    }

    function approveTokenTransfers(address token) public {
        vm.prank(PRISMA_FEE_RECEIVER.owner());
        PRISMA_FEE_RECEIVER.setTokenApproval(
            token, 
            address(operator), 
            type(uint256).max
        );
    }

    function approveClaimer(bool authorized) public {
        vm.prank(GUARDIAN);
        operator.setAuthorized(claimer1, authorized);
    }
}


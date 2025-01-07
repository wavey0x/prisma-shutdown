pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";
import { GasPoolReimburser } from "src/GasPoolReimburser.sol";

contract GasPoolReimburserTest is Test {
    uint256 public constant GAS_POOL_FEE = 200e18;
    address constant GUARDIAN = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    IPrismaFactory public constant factory = IPrismaFactory(0x70b66E20766b775B2E9cE5B718bbD285Af59b7E1);
    address public constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address public constant psm1 = 0x9d7634b2B99c2684611c0Ac3150bAF6AEEa4Ed77; // mkUSD PSM
    address public constant psm2 = 0xAe21Fe5B61998b143f721CE343aa650a6d5EadCe; // ULTRA PSM
    IERC20 public constant crvusd = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    GasPoolReimburser public gpr;
    GasPoolReimburser public gprImpl;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        IPrismaCore core = IPrismaCore(CORE);
        gprImpl = new GasPoolReimburser(CORE, psm1);
        assertEq(gprImpl.owner(), core.owner());

        vm.prank(factory.owner());
        factory.deployNewInstance(
            address(0), 
            address(0), 
            address(gprImpl), 
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
        gpr = GasPoolReimburser(factory.troveManagers(troveManagerCount - 1));
        assertEq(gpr.owner(), core.owner());
        vm.prank(gpr.owner());
        gpr.setGPRGuardian(GUARDIAN);
    }

    function test_reimburse() public {
        uint256 psm1Balance = crvusd.balanceOf(address(psm1));
        address[] memory users = getUsers();
        vm.startPrank(GUARDIAN);
        gpr.reimburse(users);
        assertGt(psm1Balance, 0);
        assertEq(gpr.totalMinted(), GAS_POOL_FEE * users.length);
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(crvusd.balanceOf(users[i]), GAS_POOL_FEE);
        }
        assertGt(gpr.totalMinted(), 0, "totalMinted should be greater than 0");
        assertEq(psm1Balance - crvusd.balanceOf(address(psm1)), gpr.totalMinted(), "totalMinted should be equal to the diff in psm balance");
        assertLt(crvusd.balanceOf(address(psm1)), psm1Balance, "psm1 balance should be less than before");
    }

    function test_ReimburseAuthorization() public {
        address[] memory users = getUsers();
        vm.expectRevert("GPR: !ownerOrGuardian");
        gpr.reimburse(users);
    }

    function test_CannotMintAboveLimit() public {
        address[] memory users = getUsers();
        uint256 maxReimbursements = gpr.MAX_MINT_LIMIT() / GAS_POOL_FEE / users.length;
        console.log("maxReimbursements", maxReimbursements);
        vm.startPrank(GUARDIAN);
        for (uint256 i = 0; i < maxReimbursements; i++) {
            gpr.reimburse(users);
        }
        // Next mint should exceed the limit
        vm.expectRevert("GPR: max mint limit exceeded");
        gpr.reimburse(users);
    }

    function getUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](3);
        users[0] = address(0x1);
        users[1] = address(0x2);
        users[2] = address(0x3);
        return users;
    } 

}

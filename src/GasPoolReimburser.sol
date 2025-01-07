// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDebtToken } from "./interfaces/IDebtToken.sol";
import { PrismaOwnable } from "./PrismaOwnable.sol";
import { IPrismaPSM } from "./interfaces/IPrismaPSM.sol";

contract GasPoolReimburser is PrismaOwnable {
    using SafeERC20 for IERC20;

    uint256 public constant GAS_POOL_FEE = 200e18;
    uint256 public constant MAX_DEBT_LIMIT = 10000e18;
    IPrismaPSM immutable public psm;
    IERC20 immutable public debtToken;
    IERC20 immutable public crvUSD;
    uint256 public allowanceUsed;
    address public gprGuardian;

    event GPRGuardianSet(address indexed gprGuardian);
    event ReimbursementSent(uint256 indexed users, uint256 amount);
    
    modifier onlyOwnerOrGPRGuardian() {
        require(msg.sender == owner() || msg.sender == gprGuardian, "GPR: !ownerOrGuardian");
        _;
    }

    constructor(
        address _prismaCore,
        address _psm
    ) PrismaOwnable(_prismaCore) {
        debtToken = IERC20(IPrismaPSM(_psm).debtToken());
        crvUSD = IERC20(IPrismaPSM(_psm).buyToken());
        psm = IPrismaPSM(_psm);
    }

    function reimburse(address[] memory users) external onlyOwnerOrGPRGuardian {
        uint256 reimbursementAmount = users.length * GAS_POOL_FEE;
        _mint(reimbursementAmount);
        psm.sellDebtToken(reimbursementAmount);
        for (uint256 i = 0; i < users.length; i++) {
            crvUSD.safeTransfer(users[i], GAS_POOL_FEE);
        }
        emit ReimbursementSent(users.length, reimbursementAmount);
    }

    function _mint(uint256 amount) internal {
        allowanceUsed += amount;
        require(allowanceUsed <= MAX_DEBT_LIMIT, "GPR: max debt limit exceeded");
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function setGPRGuardian(address _gprGuardian) external onlyOwner {
        gprGuardian = _gprGuardian;
        emit GPRGuardianSet(_gprGuardian);
    }

    // Required + Optional TM interfaces
    // useful for avoiding reverts on calls from pre-existing helper contracts that rely on standard interface
    function fetchPrice() public view returns (uint256) {}
    function setAddresses(address,address,address) external {}
    function setParameters(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external {}
    function collateralToken() public view returns (address) {return address(debtToken);}
    function getTroveStatus(address) external view returns (uint256) {}
    function getTroveCollAndDebt(address) external view returns (uint256, uint256) {}
    function getEntireDebtAndColl(address) external view returns (uint256, uint256, uint256, uint256) {}
    function getEntireSystemColl() external view returns (uint256) {}
    function getEntireSystemDebt() external view returns (uint256) {}
    function getEntireSystemBalances() external view returns (uint256, uint256, uint256) {}
    function getNominalICR(address) external view returns (uint256) {}
    function getCurrentICR(address) external view returns (uint256) {}
    function getTotalActiveCollateral() external view returns (uint256) {}
    function getTotalActiveDebt() external view returns (uint256) {}
    function getPendingCollAndDebtRewards(address) external view returns (uint256, uint256) {}
    function hasPendingRewards(address) external view returns (bool) {}
    function getRedemptionRate() external view returns (uint256) {}
    function getRedemptionRateWithDecay(uint256) external view returns (uint256) {}
    function getRedemptionFeeWithDecay(address) external view returns (uint256) {}
    function getBorrowingRate(address) external view returns (uint256) {}
    function getBorrowingRateWithDecay(address) external view returns (uint256) {}
    function getBorrowingFeeWithDecay(address) external view returns (uint256) {}
}
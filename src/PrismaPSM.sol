// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import { IBorrowerOperations } from "./interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "./interfaces/ITroveManager.sol";
import { IDebtToken } from "./interfaces/IDebtToken.sol";
import { PrismaOwnable } from "./PrismaOwnable.sol";
contract PrismaPSM is PrismaOwnable {
    using SafeERC20 for IERC20;

    IERC20 immutable public debtToken;
    IERC20 immutable public buyToken;
    IBorrowerOperations immutable public borrowerOps;
    
    address public psmGuardian;
    uint256 public maxBuy; // Maximum debt tokens that can be bought

    event DebtTokenBought(address indexed account, bool indexed troveClosed, uint256 amount);
    event DebtTokenSold(address indexed account, uint256 amount);
    event MaxBuySet(uint256 maxBuy);
    event OwnerSet(address indexed owner);
    event Paused();
    event PSMGuardianSet(address indexed psmGuardian);
    event ERC20Recovered(address indexed tokenAddress, uint256 tokenAmount);
    
    modifier onlyOwnerOrPSMGuardian() {
        require(msg.sender == owner() || msg.sender == psmGuardian, "PSM: !ownerOrGuardian");
        _;
    }

    constructor(
        address _prismaCore,
        address _debtToken, 
        address _buyToken, 
        address _borrowerOps
    ) PrismaOwnable(_prismaCore) {
        require(_debtToken != address(0), "PSM: zero address");
        require(_buyToken != address(0), "PSM: zero address");
        require(_borrowerOps != address(0), "PSM: zero address");
        // No need to set state variables (owner, etc) because this contract will be cloned
        // and clones do not copy state from the original contract
        debtToken = IERC20(_debtToken);
        buyToken = IERC20(_buyToken);
        require(ERC20(_debtToken).decimals() == 18, "PSM: 18 decimals required");
        require(ERC20(_buyToken).decimals() == 18, "PSM: 18 decimals required");
        borrowerOps = IBorrowerOperations(_borrowerOps);
    }

    /// @notice Repays debt for a trove using buy tokens at 1:1 rate
    /// @dev Account with debt must first approve this contract as a delegate on BorrowerOperations
    /// @param _troveManager The trove manager contract where the user has debt
    /// @param _account The account whose trove debt is being repaid
    /// @param _amount The amount of debt to repay - recommended to overestimate!
    /// @param _upperHint The upper hint for the sorted troves
    /// @param _lowerHint The lower hint for the sorted troves
    function repayDebt(
        address _troveManager, 
        address _account, 
        uint256 _amount, 
        address _upperHint, 
        address _lowerHint
    ) external returns (uint256) {
        require(isValidTroveManager(_troveManager), "PSM: Invalid trove manager");
        bool troveClosed;
        (_amount, troveClosed) = getRepayAmount(_troveManager, _account, _amount);
        require(_amount > 0, "PSM: Cannot repay");
        buyToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mintDebtTokens(_amount);
        if (!troveClosed) {
            borrowerOps.repayDebt(
                _troveManager,
                _account,
                _amount,
                _upperHint,
                _lowerHint
            );
        }
        else{
            // When closing a trove, collat is always sent to this contract. Make sure it is sent back to user with trove (not msg.sender).
            IERC20 collatToken = IERC20(ITroveManager(_troveManager).collateralToken());
            uint256 startBalance = collatToken.balanceOf(address(this));
            borrowerOps.closeTrove(_troveManager, _account);
            collatToken.safeTransfer(_account, collatToken.balanceOf(address(this)) - startBalance);
        }
        emit DebtTokenBought(_account, troveClosed, _amount);
        return _amount;
    }

    /// @notice Converts user input amount of debt to the actual amount of debt to be repaid and whether it is enough to close the trove
    /// @param _troveManager The trove manager contract where the user has debt
    /// @param _account The account whose trove debt is being repaid
    /// @param _amount The amount of debt to repay -- overestimates are OK
    /// @return _amount The amount of debt that can be repaid
    /// @return troveClosed Whether the trove should be closed
    function getRepayAmount(address _troveManager, address _account, uint256 _amount) public view returns (uint256, bool troveClosed) {
        (, uint256 debt) = ITroveManager(_troveManager).getTroveCollAndDebt(_account);
        _amount = Math.min(_amount, debt);
        _amount = Math.min(_amount, maxBuy);
        uint256 minDebt = borrowerOps.minNetDebt();
        if (_amount == debt) {
            troveClosed = true;
        } else if (debt - _amount < minDebt) {
            _amount = debt - minDebt;
        }
        return (_amount, troveClosed);
    }

    /// @notice Sells debt tokens to the PSM in exchange for buy tokens at a 1:1 rate
    /// @dev No approval check needed since we can just burn the debt tokens
    /// @param amount The amount of debt tokens to sell
    function sellDebtToken(uint256 amount) public returns (uint256) {
        if (amount == 0) return 0;
        IDebtToken(address(debtToken)).burn(msg.sender, amount);
        buyToken.safeTransfer(msg.sender, amount);      // send buy token to seller
        emit DebtTokenSold(msg.sender, amount);
        return amount;
    }

    function _mintDebtTokens(uint256 amount) internal {
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function setMaxBuy(uint256 _maxBuy) external onlyOwnerOrPSMGuardian {
        maxBuy = _maxBuy;
        emit MaxBuySet(_maxBuy);
    }

    /// @notice Pauses the PSM by burning all debt tokens and setting maxBuy to 0
    function pause() external onlyOwnerOrPSMGuardian {
        IDebtToken(address(debtToken)).burn(address(this), debtToken.balanceOf(address(this)));
        maxBuy = 0;
        emit Paused();
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(debtToken), "PSM: Cannot recover debt token");
        require(tokenAddress != address(buyToken), "PSM: Cannot recover buy token");
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit ERC20Recovered(tokenAddress, tokenAmount);
    }

    function setPSMGuardian(address _psmGuardian) external onlyOwner {
        psmGuardian = _psmGuardian;
        emit PSMGuardianSet(_psmGuardian);
    }

    function isValidTroveManager(address _troveManager) public view returns (bool isValid) {
        return IDebtToken(address(debtToken)).troveManager(_troveManager);
    }

    // Required + Optional TM interfaces
    // useful for avoiding reverts on calls from pre-existing helper contracts that rely on standard interface
    function fetchPrice() public view returns (uint256) {}
    function setAddresses(address,address,address) external {}
    function setParameters(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external {}
    function collateralToken() public view returns (address) {return address(buyToken);}
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
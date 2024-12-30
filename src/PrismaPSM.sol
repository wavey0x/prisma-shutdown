// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import { IBorrowerOperations } from "./interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "./interfaces/ITroveManager.sol";
import { IDebtToken } from "./interfaces/IDebtToken.sol";

contract PrismaPSM {
    using SafeERC20 for IERC20;

    address constant public DEFAULT_OWNER = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    IERC20 immutable public debtToken;
    IERC20 immutable public buyToken;
    IBorrowerOperations immutable public borrowerOps;
    
    bool public ownerInit;
    address public owner;
    uint256 public maxBuy; // Maximum debt tokens that can be bought

    event DebtTokenBought(address indexed account, bool indexed troveClosed, uint256 amount);
    event DebtTokenSold(address indexed account, uint256 amount);
    event MaxBuySet(uint256 maxBuy);
    event OwnerSet(address indexed owner);
    event Paused();

    modifier onlyOwner() {
        require(msg.sender == owner, "PSM: !owner");
        _;
    }

    constructor(
        address _debtToken, 
        address _buyToken, 
        address _borrowerOps
    ) {
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
        _mintDebtTokens(_amount);
        require(_amount > 0, "PSM: Cannot repay");
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
            borrowerOps.closeTrove(_troveManager, _account);
        }
        buyToken.safeTransferFrom(msg.sender, address(this), _amount);
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
        if (amount == 0) return;
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function setMaxBuy(uint256 _maxBuy) external onlyOwner {
        maxBuy = _maxBuy;
        emit MaxBuySet(_maxBuy);
    }

    function setOwner(address _owner) external {
        // owner on init is 0x0 ... allow anyone permissionlessly initialize to DEFAULT_OWNER
        if (!ownerInit) {
            owner = DEFAULT_OWNER;
            ownerInit = true;
            emit OwnerSet(DEFAULT_OWNER);
            return;
        }
        require(msg.sender == owner, "PSM: !owner");
        owner = _owner;
        emit OwnerSet(_owner);
    }

    /// @notice Pauses the PSM by burning all debt tokens and setting maxBuy to 0
    function pause() external onlyOwner {
        IDebtToken(address(debtToken)).burn(address(this), debtToken.balanceOf(address(this)));
        maxBuy = 0;
        emit Paused();
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
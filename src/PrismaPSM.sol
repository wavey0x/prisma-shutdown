// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import { IBorrowerOperations } from "./interfaces/IBorrowerOperations.sol";
import { ITroveManager } from "./interfaces/ITroveManager.sol";
import { IDebtToken } from "./interfaces/IDebtToken.sol";
import { IPrismaFactory } from "./interfaces/IPrismaFactory.sol";
import { ISortedTroves } from "./interfaces/ISortedTroves.sol";

contract PrismaPSM {
    using SafeERC20 for IERC20;

    address public constant DEFAULT_OWNER = 0xfE11a5001EF95cbADd1a746D40B113e4AAA872F8;
    IERC20 immutable public debtToken;
    IERC20 immutable public buyToken;
    IBorrowerOperations immutable public borrowerOps;
    IPrismaFactory immutable public factory;

    address public owner;
    uint256 public rate; // Tokens unlocked per second
    uint256 public maxReserve; // Maximum tokens that can be unlocked
    uint256 public lastPurchaseTime; // Timestamp of last purchase
    uint256 public availableDebtTokens; // Current amount of unlocked tokens

    event RepayDebt(address indexed account, bool indexed troveClosed, uint256 amount);
    event DebtTokenBought(address indexed account, bool indexed troveClosed, uint256 amount);
    event DebtTokenSold(address indexed account, uint256 amount);
    event RateSet(uint256 rate);
    event MaxReserveSet(uint256 maxReserve);
    event OwnerSet(address indexed owner);

    modifier onlyOwner() {
        require(msg.sender == owner, "PSM: !owner");
        _;
    }

    constructor(
        address _debtToken, 
        address _buyToken, 
        address _borrowerOps
    ) {
        owner = IBorrowerOperations(_borrowerOps).owner();
        buyToken = IERC20(_buyToken);
        debtToken = IERC20(_debtToken);
        require(ERC20(_debtToken).decimals() == 18, "PSM: 18 decimals required");
        require(ERC20(_buyToken).decimals() == 18, "PSM: 18 decimals required");
        borrowerOps = IBorrowerOperations(_borrowerOps);
        factory = IPrismaFactory(IBorrowerOperations(_borrowerOps).factory());
        lastPurchaseTime = block.timestamp;
    }

    /// @notice Repays debt for a trove using buy tokens at 1:1 rate
    /// @dev Account with debt must first approve this contract as a delegate on BorrowerOperations
    /// @param _troveManager The trove manager contract where the user has debt
    /// @param _account The account whose trove debt is being repaid
    /// @param _amount The amount of debt to repay
    function repayDebt(address _troveManager, address _account, uint256 _amount) external {
        _repayDebt(_troveManager, _account, _amount, address(0), address(0));
    }

    function repayDebtWithHints(address _troveManager, address _account, uint256 _amount, address _upperHint, address _lowerHint) external {
        _repayDebt(_troveManager, _account, _amount, _upperHint, _lowerHint);
    }

    function _repayDebt(address _troveManager, address _account, uint256 _amount, address _upperHint, address _lowerHint) internal {
        require(isValidTroveManager(_troveManager), "PSM: Invalid trove manager");
        uint256 debtTokenReserve = getDebtTokenReserve();
        require(_amount <= debtTokenReserve, "PSM: Insufficient reserves");
        _mintDebtToken(debtTokenReserve);
        (, uint256 debt) = ITroveManager(_troveManager).getTroveCollAndDebt(_account);
        require(debt > 0, "PSM: Account has no debt");
        _amount = Math.min(_amount, debt);
        bool troveClosed = false;
        if (_amount < debt) { // Determine whether partial repayment, or should close trove
            _amount -= borrowerOps.minNetDebt();
            borrowerOps.repayDebt(
                _troveManager,
                _account,
                _amount,
                _upperHint,
                _lowerHint
            );
        }
        else{
            troveClosed = true;
            borrowerOps.closeTrove(_troveManager, _account);
        }
        
        buyToken.safeTransferFrom(msg.sender, address(this), _amount);
        lastPurchaseTime = block.timestamp; // This value will not transfer to the TM due to clone, must set elsewhere

        emit DebtTokenBought(_account, troveClosed, _amount);
    }

    /// @notice Sells debt tokens to the PSM in exchange for buy tokens at a 1:1 rate
    /// @dev No approval check needed since _transferDebtTokenToSelf handles the transfer
    /// @param amount The amount of debt tokens to sell
    function sellDebtToken(uint256 amount) public {
        if (amount == 0) return;
        _transferDebtTokenToSelf(msg.sender, amount);   // pull debt token from seller
        buyToken.safeTransfer(msg.sender, amount);      // send buy token to seller
        emit DebtTokenSold(msg.sender, amount);
    }

    function getDebtTokenReserve() public view returns (uint256 reserves) {
        uint256 timePassed = block.timestamp - lastPurchaseTime;
        uint256 mintable = timePassed * rate;
        reserves = Math.min(mintable + debtToken.balanceOf(address(this)), maxReserve);
    }

    /// @notice Returns the current reserves of both debt tokens and buy tokens
    /// @return debtTokenReserve The amount of debt tokens available for repaying debt
    /// @return buyTokenReserve The balance of buy tokens available to be sold via `sellDebtToken`
    function getReserves() public view returns (uint256 debtTokenReserve, uint256 buyTokenReserve) {
        debtTokenReserve = getDebtTokenReserve();
        buyTokenReserve = buyToken.balanceOf(address(this));
    }

    // We do this to bypass a Liquity requirement that debt token cannot be transferred to a Trove Manager
    function _transferDebtTokenToSelf(address _account, uint256 amount) internal {
        _mintDebtToken(amount);
        IDebtToken(address(debtToken)).burn(_account, amount);
    }

    function _mintDebtToken(uint256 amount) internal {
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
        // Since this contract is a clone, we cannot initialize with a value for lastPurchaseTime
        if (lastPurchaseTime == 0) lastPurchaseTime = block.timestamp;
        emit RateSet(_rate);
    }

    function setMaxReserve(uint256 _maxReserve) external onlyOwner {
        maxReserve = _maxReserve;
        // Since this contract is a clone, we cannot initialize with a value for lastPurchaseTime
        if (lastPurchaseTime == 0) lastPurchaseTime = block.timestamp;
        emit MaxReserveSet(_maxReserve);
    }

    function setOwner(address _owner) external {
        // owner on init is 0x0 ... allow anyone permissionless setting to DEFAULT_OWNER
        if (owner == address(0)) {
            owner = DEFAULT_OWNER;
            emit OwnerSet(DEFAULT_OWNER);
            return;
        }
        require(msg.sender == owner, "PSM: !owner");
        owner = _owner;
        emit OwnerSet(_owner);
    }

    function isValidTroveManager(address _troveManager) public view returns (bool isValid) {
        return IDebtToken(address(debtToken)).troveManager(_troveManager);
    }

    // Required TM interfaces
    function fetchPrice() public view returns (uint256) {}
    function setAddresses(address,address,address) external {}
    function setParameters(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external {}
    function getEntireSystemBalances() public view returns (uint256 collateral, uint256 debt, uint256 price) {}
}
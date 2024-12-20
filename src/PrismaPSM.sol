// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IBorrowerOperations.sol";
import "./interfaces/ITroveManager.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IPrismaFactory.sol";

contract PrismaPSM {
    using SafeERC20 for IERC20;

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

    function getDebtTokenReserve() public view returns (uint256 reserves) {
        uint256 timePassed = block.timestamp - lastPurchaseTime;
        uint256 mintable = timePassed * rate;
        reserves = Math.min(mintable + debtToken.balanceOf(address(this)), maxReserve);
    }

    function repayDebt(address _troveManager, address _account, uint256 _amount) public {
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
                address(0),
                address(0)
            );
        }
        else{
            troveClosed = true;
            borrowerOps.closeTrove(_troveManager, _account);
        }
        
        buyToken.safeTransferFrom(msg.sender, address(this), _amount);
        lastPurchaseTime = block.timestamp; // This value will not transfer to the TM due to clone, must set elsewhere

        emit RepayDebt(_account, troveClosed, _amount);
    }

    // Add debt tokens to the PSM in return for buy tokens
    function sellDebtToken(uint256 amount) public {
        // Cannot transfer to the PSM because Liquity prohibits Trove Managers from holding debt tokens
        // We can bypass that requirement by minting directly
        if (amount == 0) return;
        _mintDebtToken(amount);
        _burnDebtToken(msg.sender, amount);
        
        buyToken.safeTransfer(msg.sender, amount);
    }

    function getCollateraAndDebt(ITroveManager _troveManager, address _account) public returns (uint256, uint256) {
        return _troveManager.applyPendingRewards(_account);
    }

    function _mintDebtToken(uint256 amount) internal {
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function _burnDebtToken(address _account, uint256 amount) internal {
        IDebtToken(address(debtToken)).burn(_account, amount);
    }

    function getReserves() public view returns (uint256 debtTokenReserve, uint256 buyTokenReserve) {
        debtTokenReserve = getDebtTokenReserve();
        buyTokenReserve = buyToken.balanceOf(address(this));
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
        // Since this contract is a clone, we cannot initialize with a value for lastPurchaseTime
        if (lastPurchaseTime == 0) lastPurchaseTime = block.timestamp;
    }

    function setMaxReserve(uint256 _maxReserve) external onlyOwner {
        maxReserve = _maxReserve;
        // Since this contract is a clone, we cannot initialize with a value for lastPurchaseTime
        if (lastPurchaseTime == 0) lastPurchaseTime = block.timestamp;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
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
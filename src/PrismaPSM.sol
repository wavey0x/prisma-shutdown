// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IBorrowerOperations.sol";
import "./interfaces/ITroveManager.sol";
import "./interfaces/IDebtToken.sol";

contract PrismaPSM {
    using SafeERC20 for IERC20;

    IERC20 immutable public debtToken;
    IERC20 immutable public buyToken;
    IBorrowerOperations immutable public borrowerOps;

    uint256 public rate; // Tokens unlocked per second
    uint256 public maxUnlock; // Maximum tokens that can be unlocked
    uint256 public lastPurchaseTime; // Timestamp of last purchase
    uint256 public availableDebtTokens; // Current amount of unlocked tokens

    constructor(address _debtToken, address _buyToken, address _borrowerOps) {
        require(buyToken.decimals() == 18, "PSM: 18 decimals required");
        require(debtToken.decimals() == 18, "PSM: 18 decimals required");
        buyToken = IERC20(_buyToken);
        debtToken = IERC20(_debtToken);
        borrowerOps = IBorrowerOperations(_borrowerOps);
        lastPurchaseTime = block.timestamp;
        rate = 0; // Will need to be set by admin
        maxUnlock = 0; // Will need to be set by admin
    }

    function getDebtTokenReserve() public view returns (uint256) {
        uint256 timePassed = block.timestamp - lastPurchaseTime;
        uint256 newTokens = timePassed * rate;
        return Math.min(newTokens + debtToken.balanceOf(address(this)), maxUnlock);
    }

    function repayDebt(ITroveManager _troveManager, address _account, uint256 _amount) public {
        uint256 debtTokenReserve = getDebtTokenReserve();
        require(_amount <= debtTokenReserve, "PSM: Insufficient reserves");
        (, uint256 debt) = getCollateraAndDebt(_troveManager, _account);
        _amount = Math.min(_amount, debt);
        buyToken.token.safeTransferFrom(msg.sender, address(this), _amount);
        _mintDebtToken(_amount);
        borrowerOps.repayDebt(_account, _amount);
        lastPurchaseTime = block.timestamp;
    }

    // Add debt tokens to the PSM in return for buy tokens
    function sellDebtToken(uint256 amount) public {     
        debtToken.safeTransfer(msg.sender, amount);
        buyToken.safeTransfer(msg.sender, amount);
    }

    function getCollateraAndDebt(ITroveManager _troveManager, address _account) public view returns (uint256, uint256) {
        return _troveManager.applyPendingRewards(_account);
    }

    function _mintDebtToken(uint256 amount) internal {
        IDebtToken(address(debtToken)).mint(address(this), amount);
    }

    function getReserves() public view returns (uint256 debtTokenReserve, uint256 buyTokenReserve) {
        return (getDebtTokenReserve(), buyToken.balanceOf(address(this)));
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function setMaxUnlock(uint256 _maxUnlock) external onlyOwner {
        maxUnlock = _maxUnlock;
    }
}

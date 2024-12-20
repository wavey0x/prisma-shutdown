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
import {Stash} from "src/Stash.sol";

contract PrismaPSM {
    using SafeERC20 for IERC20;

    
    IERC20 immutable public debtToken;
    IERC20 immutable public buyToken;
    IBorrowerOperations immutable public borrowerOps;
    IPrismaFactory immutable public factory;
    address immutable public stash;

    address public owner;
    uint256 public rate; // Tokens unlocked per second
    uint256 public maxUnlock; // Maximum tokens that can be unlocked
    uint256 public lastPurchaseTime; // Timestamp of last purchase
    uint256 public availableDebtTokens; // Current amount of unlocked tokens

    event RepayDebt(address indexed account, bool indexed troveClosed, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "PSM: !owner");
        _;
    }

    constructor(address _debtToken, address _buyToken, address _borrowerOps) {
        // Liquity systems prohibit Trove Managers from holding debt tokens
        // So we create a simple stash contract to manage those transfers
        stash = address(new Stash(_debtToken));
        owner = IBorrowerOperations(_borrowerOps).owner();
        buyToken = IERC20(_buyToken);
        debtToken = IERC20(_debtToken);
        require(ERC20(_debtToken).decimals() == 18, "PSM: 18 decimals required");
        require(ERC20(_buyToken).decimals() == 18, "PSM: 18 decimals required");
        borrowerOps = IBorrowerOperations(_borrowerOps);
        factory = IPrismaFactory(IBorrowerOperations(_borrowerOps).factory());
        lastPurchaseTime = block.timestamp;
        rate = 0; // Will need to be set by admin
        maxUnlock = 0; // Will need to be set by admin
    }

    function getDebtTokenReserve() public view returns (uint256 reserves, uint256 mintable) {
        uint256 timePassed = block.timestamp - lastPurchaseTime;
        mintable = timePassed * rate;
        reserves = Math.min(mintable + debtToken.balanceOf(stash), maxUnlock);
    }

    function repayDebt(ITroveManager _troveManager, address _account, uint256 _amount) public {
        require(isValidTroveManager(address(_troveManager)), "PSM: Invalid trove manager");
        (uint256 debtTokenReserve, uint256 mintable) = getDebtTokenReserve();
        require(_amount <= debtTokenReserve, "PSM: Insufficient reserves");
        (, uint256 debt) = _troveManager.getTroveCollAndDebt(_account);
        _amount = Math.min(_amount, debt);
        handleBurnMint(mintable, _amount);
        bool troveClosed = false;
        if (_amount < debt) {
            _amount -= borrowerOps.minNetDebt();
            borrowerOps.repayDebt(
                address(_troveManager),
                _account,
                _amount,
                address(0),
                address(0)
            );
        }
        else{
            troveClosed = true;
            borrowerOps.closeTrove(address(_troveManager), _account);
        }
        
        buyToken.safeTransferFrom(msg.sender, address(this), _amount);
        lastPurchaseTime = block.timestamp;

        emit RepayDebt(_account, troveClosed, _amount);
    }

    // Can bypass the trasnfer prohibition by minting directly to the PSM
    function handleBurnMint(uint256 mintable, uint256 amount) internal {
        uint256 stashBalance = debtToken.balanceOf(stash);
        // first burn from stash
        if (stashBalance >= amount) {
            IDebtToken(address(debtToken)).burn(stash, amount);
            IDebtToken(address(debtToken)).mint(address(this), amount);
            return;
        }
        else{
            if (stashBalance > 0) {
                IDebtToken(address(debtToken)).burn(stash, stashBalance);
                IDebtToken(address(debtToken)).mint(address(this), amount);
                if (mintable > amount) IDebtToken(address(debtToken)).mint(stash, mintable - amount);
            }
        }
    }

    // Add debt tokens to the PSM in return for buy tokens
    function sellDebtToken(uint256 amount) public {     
        debtToken.safeTransferFrom(msg.sender, stash, amount);
        buyToken.safeTransfer(msg.sender, amount);
    }

    function getCollateraAndDebt(ITroveManager _troveManager, address _account) public returns (uint256, uint256) {
        return _troveManager.applyPendingRewards(_account);
    }

    function _mintDebtToken(uint256 amount) internal {
        IDebtToken(address(debtToken)).mint(stash, amount);
    }

    function getReserves() public view returns (uint256 debtTokenReserve, uint256 buyTokenReserve) {
        (debtTokenReserve, ) = getDebtTokenReserve();
        buyTokenReserve = buyToken.balanceOf(address(this));
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function setMaxUnlock(uint256 _maxUnlock) external onlyOwner {
        maxUnlock = _maxUnlock;
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
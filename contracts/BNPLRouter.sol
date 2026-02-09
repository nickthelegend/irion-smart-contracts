// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CreditManager} from "./CreditManager.sol";
import {DebtManager} from "./DebtManager.sol";

contract BNPLRouter is Ownable {
    using SafeERC20 for IERC20;

    CreditManager public i_creditManager;
    DebtManager public i_debtManager;
    IERC20 public i_paymentToken; // USDC/USDT on Master Chain

    event MerchantPaid(address indexed user, address indexed merchant, uint256 amount);

    constructor(address _creditManager, address _debtManager, address _paymentToken) Ownable() {
        i_creditManager = CreditManager(_creditManager);
        i_debtManager = DebtManager(_debtManager);
        i_paymentToken = IERC20(_paymentToken);
    }

    /// @notice Merchant calls this or user calls to pay merchant
    /// @dev In a real system, this might be signed by the user or called via account abstraction
    function payMerchant(address _user, address _merchant, uint256 _amount) external {
        // 1. Check Credit Limit
        uint256 creditLimit = i_creditManager.getCreditLimit(_user);
        
        // 2. Check Current Debt
        uint256 currentDebt = i_debtManager.getDebt(_user);
        
        require(currentDebt + _amount <= creditLimit, "Exceeds credit limit");

        // 3. Create Debt
        i_debtManager.createDebt(_user, _amount);

        // 4. Pay Merchant
        // Router must hold liquidity (LP)
        require(i_paymentToken.balanceOf(address(this)) >= _amount, "Insufficient liquidity");
        i_paymentToken.safeTransfer(_merchant, _amount);

        emit MerchantPaid(_user, _merchant, _amount);
    }
    
    // Admin functions to manage liquidity
    function addLiquidity(uint256 _amount) external {
        i_paymentToken.safeTransferFrom(msg.sender, address(this), _amount);
    }
    
    function removeLiquidity(uint256 _amount) external onlyOwner {
        i_paymentToken.safeTransfer(msg.sender, _amount);
    }
}

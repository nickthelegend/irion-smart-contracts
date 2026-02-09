// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DebtManager is Ownable {
    
    mapping(address => uint256) public s_userDebt;
    
    address public s_bnplRouter;
    address public s_masterReceiver; // In case we need it

    event DebtCreated(address indexed user, uint256 amount);
    event DebtRepaid(address indexed user, uint256 amount);

    constructor() Ownable() {}

    modifier onlyAuthorized() {
        require(msg.sender == s_bnplRouter || msg.sender == owner(), "Unauthorized");
        _;
    }

    function setAuthorizedContracts(address _router) external onlyOwner {
        s_bnplRouter = _router;
    }

    function createDebt(address _user, uint256 _amount) external onlyAuthorized {
        s_userDebt[_user] += _amount;
        emit DebtCreated(_user, _amount);
    }

    function repay(address _user, uint256 _amount) external onlyAuthorized {
        if (s_userDebt[_user] < _amount) {
            s_userDebt[_user] = 0;
        } else {
            s_userDebt[_user] -= _amount;
        }
        emit DebtRepaid(_user, _amount);
    }

    function getDebt(address _user) external view returns (uint256) {
        return s_userDebt[_user];
    }
}

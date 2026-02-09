// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CreditManager is Ownable {
    
    // user -> chainId -> token -> usdValue
    mapping(address => mapping(uint64 => mapping(address => uint256))) public s_userCollateralValue;
    // user -> totalCollateralValue (in USD 18 decimals)
    mapping(address => uint256) public s_userTotalCollateralUSD;

    // LTV (Loan to Value) - 75% default
    uint256 public constant LTV_BASIS_POINTS = 7500;
    uint256 public constant MAX_BASIS_POINTS = 10000;

    address public s_masterReceiver;
    address public s_bnplRouter;
    address public s_liquidationController;

    event CollateralUpdated(address indexed user, uint64 indexed chainId, address token, uint256 newUsdValue);
    
    constructor() Ownable() {}

    modifier onlyAuthorized() {
        require(msg.sender == s_masterReceiver || msg.sender == s_bnplRouter || msg.sender == s_liquidationController || msg.sender == owner(), "Unauthorized");
        _;
    }

    function setAuthorizedContracts(address _receiver, address _router, address _liquidator) external onlyOwner {
        s_masterReceiver = _receiver;
        s_bnplRouter = _router;
        s_liquidationController = _liquidator;
    }

    /// @notice Updates collateral value from Satellite chain messages
    function updateCollateral(address _user, uint64 _chainId, address _token, uint256 _newUsdValue) external onlyAuthorized {
        uint256 oldValue = s_userCollateralValue[_user][_chainId][_token];
        
        if (_newUsdValue > oldValue) {
            s_userTotalCollateralUSD[_user] += (_newUsdValue - oldValue);
        } else {
            s_userTotalCollateralUSD[_user] -= (oldValue - _newUsdValue);
        }
        
        s_userCollateralValue[_user][_chainId][_token] = _newUsdValue;
        emit CollateralUpdated(_user, _chainId, _token, _newUsdValue);
    }

    /// @notice Increases collateral value (Deposit)
    function addCollateral(address _user, uint64 _chainId, address _token, uint256 _amountUsd) external onlyAuthorized {
        s_userCollateralValue[_user][_chainId][_token] += _amountUsd;
        s_userTotalCollateralUSD[_user] += _amountUsd;
        emit CollateralUpdated(_user, _chainId, _token, s_userCollateralValue[_user][_chainId][_token]);
    }

    /// @notice Decreases collateral value (Withdraw check should happen before calling this)
    function reduceCollateral(address _user, uint64 _chainId, address _token, uint256 _amountUsd) external onlyAuthorized {
        require(s_userCollateralValue[_user][_chainId][_token] >= _amountUsd, "Insufficient collateral on chain");
        s_userCollateralValue[_user][_chainId][_token] -= _amountUsd;
        s_userTotalCollateralUSD[_user] -= _amountUsd;
        emit CollateralUpdated(_user, _chainId, _token, s_userCollateralValue[_user][_chainId][_token]);
    }

    /// @notice Calculates the credit limit for a user based on LTV
    function getCreditLimit(address _user) public view returns (uint256) {
        return (s_userTotalCollateralUSD[_user] * LTV_BASIS_POINTS) / MAX_BASIS_POINTS;
    }
}

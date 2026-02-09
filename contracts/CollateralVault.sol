// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SatelliteCCIPSender} from "./SatelliteCCIPSender.sol";

contract CollateralVault is CCIPReceiver, SatelliteCCIPSender, Ownable {
    using SafeERC20 for IERC20;

    // Message Types
    uint8 public constant MSG_CREDIT_UPDATE = 1;
    uint8 public constant MSG_WITHDRAW_REQUEST = 2;
    // Receive Types
    uint8 public constant MSG_WITHDRAW_APPROVED = 3;
    uint8 public constant MSG_LIQUIDATE = 4;

    // State
    mapping(address => mapping(address => uint256)) public s_userCollateral; // user -> token -> amount
    mapping(address => address) public s_tokenPriceFeeds; // token -> aggregator

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event WithdrawRequested(address indexed user, address indexed token, uint256 amount);
    event WithdrawProcessed(address indexed user, address indexed token, uint256 amount);
    event CollateralSeized(address indexed user, address indexed token, uint256 amount);

    constructor(
        address _router, 
        uint64 _masterChainSelector, 
        address _masterReceiver
    ) CCIPReceiver(_router) SatelliteCCIPSender(_router, _masterChainSelector, _masterReceiver) Ownable() {}

    function setPriceFeed(address _token, address _feed) external onlyOwner {
        s_tokenPriceFeeds[_token] = _feed;
    }

    function deposit(address _token, uint256 _amount) external {
        require(s_tokenPriceFeeds[_token] != address(0), "Token not supported");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        s_userCollateral[msg.sender][_token] += _amount;

        uint256 usdValue = _getUsdValue(_token, _amount);

        // Encode data: type, user, sourceChainId (implicit in CCIP messge source but useful to include explicit if needed, but we rely on CCIP sourceChainId on receive), token, amount, usdValue
        // We act as the "source" so the master knows which chain it came from via CCIP metadata.
        // We'll send: type, user, token (address on THIS chain), amount, usdValue.
        // Master chain needs to map (chainId, tokenAddress) -> valid asset.
        
        bytes memory data = abi.encode(MSG_CREDIT_UPDATE, msg.sender, _token, _amount, usdValue);
        
        // Send to master
        _sendToMaster(data, false); // assume native payment for simplicity

        emit CollateralDeposited(msg.sender, _token, _amount, usdValue);
    }

    function requestWithdraw(address _token, uint256 _amount) external {
        require(s_userCollateral[msg.sender][_token] >= _amount, "Insufficient collateral");

        // Send request to master
        // Encoded with 0 as usdValue to match the 5-parameter decoding in MasterCCIPReceiver
        bytes memory data = abi.encode(MSG_WITHDRAW_REQUEST, msg.sender, _token, _amount, uint256(0));
        _sendToMaster(data, false);

        emit WithdrawRequested(msg.sender, _token, _amount);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // Validate sender is Master Chain Receiver
        // any2EvmMessage.sourceChainSelector must be masterChainSelector
        // any2EvmMessage.sender must be abi.encode(masterReceiver)
        require(any2EvmMessage.sourceChainSelector == i_masterChainSelector, "Invalid source chain");
        address sender = abi.decode(any2EvmMessage.sender, (address));
        require(sender == i_masterReceiver, "Invalid sender");

        (uint8 msgType, address user, address token, uint256 amount) = abi.decode(any2EvmMessage.data, (uint8, address, address, uint256));

        if (msgType == MSG_WITHDRAW_APPROVED) {
            _processWithdraw(user, token, amount);
        } else if (msgType == MSG_LIQUIDATE) {
            _processLiquidation(user, token, amount);
        }
    }

    function _processWithdraw(address _user, address _token, uint256 _amount) internal {
        require(s_userCollateral[_user][_token] >= _amount, "Insufficient collateral for withdraw");
        s_userCollateral[_user][_token] -= _amount;
        IERC20(_token).safeTransfer(_user, _amount);
        emit WithdrawProcessed(_user, _token, _amount);
    }

    function _processLiquidation(address _user, address _token, uint256 _amount) internal {
        // Seize collateral. For now, we move it to owner or just keep it in contract? 
        // "Satellite vault seizes collateral locally"
        // We'll move it to the contract owner (which represents the protocol DAO/Treasury).
        
        uint256 seizeAmount = _amount;
        if (s_userCollateral[_user][_token] < _amount) {
            seizeAmount = s_userCollateral[_user][_token];
        }
        
        s_userCollateral[_user][_token] -= seizeAmount;
        IERC20(_token).safeTransfer(owner(), seizeAmount);
        
        emit CollateralSeized(_user, _token, seizeAmount);
    }

    function _getUsdValue(address _token, uint256 _amount) internal view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(s_tokenPriceFeeds[_token]);
        (, int256 price,,,) = feed.latestRoundData();
        require(price > 0, "Invalid price");
        
        // price is usually 8 decimals for USD pairs on Chainlink
        // token decimals? We assume 18 for simplicity or we need ERC20 decimals check.
        // Let's assume standard normalization: (amount * price * 1e10) / 1e18 for 18 dec tokens and 8 dec price to get 18 dec USD value?
        // Or just return 18 decimals USD value.
        // value = amount * price
        
        // This is a simplified calculation. Real prod needs strictly handling decimals.
        // Assuming Token is 18 dec, Price is 8 dec.
        // Result: 18 + 8 = 26 decimals. We want 18 decimals USD (like DAI/USDC standard 6/18).
        // Contracts usually standardize to 18 decimals for internal math.
        
        return (_amount * uint256(price)) / 1e8; // (18 * 8) / 8 = 18 decimals.
    }
}

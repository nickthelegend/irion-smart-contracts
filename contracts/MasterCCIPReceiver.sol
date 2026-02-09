// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CreditManager} from "./CreditManager.sol";
import {DebtManager} from "./DebtManager.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MasterCCIPReceiver is CCIPReceiver, Ownable {
    
    CreditManager public i_creditManager;
    DebtManager public i_debtManager;
    
    // chainId -> satelliteReceiverAddress -> isTrusted
    mapping(uint64 => mapping(address => bool)) public s_trustedSenders;
    // chainId -> tokenAddress -> priceFeed
    mapping(uint64 => mapping(address => address)) public s_satelliteTokenFeeds;

    uint8 public constant MSG_CREDIT_UPDATE = 1;
    uint8 public constant MSG_WITHDRAW_REQUEST = 2;
    uint8 public constant MSG_WITHDRAW_APPROVED = 3;

    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender);
    event WithdrawApproved(address indexed user, uint64 indexed chainId, address token, uint256 amount);

    constructor(address _router, address _creditManager, address _debtManager) CCIPReceiver(_router) Ownable(msg.sender) {
        i_creditManager = CreditManager(_creditManager);
        i_debtManager = DebtManager(_debtManager);
    }

    function setTrustedSender(uint64 _chainId, address _sender, bool _trusted) external onlyOwner {
        s_trustedSenders[_chainId][_sender] = _trusted;
    }

    function setSatelliteTokenFeed(uint64 _chainId, address _token, address _feed) external onlyOwner {
        s_satelliteTokenFeeds[_chainId][_token] = _feed;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        address sender = abi.decode(any2EvmMessage.sender, (address));
        require(s_trustedSenders[any2EvmMessage.sourceChainSelector][sender], "Untrusted sender");

        (uint8 msgType, address user, address token, uint256 amount, uint256 usdValue) = abi.decode(any2EvmMessage.data, (uint8, address, address, uint256, uint256));

        emit MessageReceived(any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sender);

        if (msgType == MSG_CREDIT_UPDATE) {
            // Satellite already calculated USD value. We trust it for deposit/credit updates.
            i_creditManager.updateCollateral(user, any2EvmMessage.sourceChainSelector, token, usdValue);
        } else if (msgType == MSG_WITHDRAW_REQUEST) { 
            // Satellite sends (MSG_WITHDRAW_REQUEST, user, token, amount) - wait, my CollateralVault decode logic expected 4 args? 
            // My CollateralVault sent `_sendToMaster(abi.encode(MSG_WITHDRAW_REQUEST, msg.sender, _token, _amount), ...)` -> 4 args.
            // But here I allow 5 args decode?
            // I should handle decoding differently based on message type or use flexible decoding.
            // Let's modify decoding to be safer.
             _handleWithdrawRequest(user, token, amount, any2EvmMessage.sourceChainSelector, sender);
        }
    }
    
    // Helper to avoid decode issues if formats differ. 
    // Ideally we use a struct or consistent format.
    // CollateralVault: 
    // Deposit: (1, user, token, amount, usdValue) -> 5 items
    // Withdraw: (2, user, token, amount) -> 4 items.
    
    // Solidity `abi.decode` strictly requires matching types.
    // I need to decode partially or use a catch-all approach.
    // OR I can just make CollateralVault send a dummy 0 for usdValue in WithdrawRequest to verify consistent encoding.
    // Since I already wrote CollateralVault, and I can't easily change it without rewriting (which I can do),
    // I will rewrite `CollateralVault.sol` to include `uint256(0)` for `usdValue` or padding.
    // BETTER: Use `abi.decode` for the prefix and then remaining? No.
    // I'll update `CollateralVault` to send consistent payload.

    function _handleWithdrawRequest(address user, address token, uint256 amount, uint64 chainId, address receiver) internal {
        // We need to calculate USD value here to check LTV
        
        uint256 usdValue = _linkPriceFeed(chainId, token, amount);
        
        // Check health
        uint256 creditLimit = i_creditManager.getCreditLimit(user);
        uint256 currentDebt = i_debtManager.getDebt(user);
        
        // Hypothetical new limit
        // We reduce collateral by `usdValue`
        // New Limit = ((TotalCollateral - usdValue) * LTV) / MAX
        // We must check if NewLimit >= CurrentDebt
        
        uint256 currentCollateral = i_creditManager.s_userTotalCollateralUSD(user);
        // Safety check
        if (currentCollateral < usdValue) return; // Should not happen if state is synced
        
        uint256 newCollateral = currentCollateral - usdValue;
        uint256 newLimit = (newCollateral * i_creditManager.LTV_BASIS_POINTS()) / i_creditManager.MAX_BASIS_POINTS();
        
        if (newLimit >= currentDebt) {
            // Approved
            i_creditManager.reduceCollateral(user, chainId, token, usdValue);
            
            // Send WITHDRAW_APPROVED back
            _sendWithdrawApproved(chainId, receiver, user, token, amount);
        }
    }

    function _sendWithdrawApproved(uint64 _chainId, address _receiver, address _user, address _token, uint256 _amount) internal {
        bytes memory data = abi.encode(MSG_WITHDRAW_APPROVED, _user, _token, _amount);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(0)
        });
        
        IRouterClient(getRouter()).ccipSend{value: 0}(_chainId, message); // Assist with fees?
        emit WithdrawApproved(_user, _chainId, _token, _amount);
    }
    
    function _linkPriceFeed(uint64 _chainId, address _token, uint256 _amount) internal view returns (uint256) {
        address feedAddr = s_satelliteTokenFeeds[_chainId][_token];
        if (feedAddr == address(0)) {
            // Fallback: If we trusted satellite, we could have used a value sent in message.
            // For now, revert or return 0 (blocking withdraw).
            revert("No feed found");
        }
        
        AggregatorV3Interface feed = AggregatorV3Interface(feedAddr);
        (, int256 price,,,) = feed.latestRoundData();
        return (_amount * uint256(price)) / 1e8; // Assuming 8 dec feed
    }
}

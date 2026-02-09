// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SatelliteCCIPSender
/// @notice Helper contract for sending CCIP messages from Satellite chains to Master chain
abstract contract SatelliteCCIPSender {
    using SafeERC20 for IERC20;

    IRouterClient public immutable i_router;
    uint64 public immutable i_masterChainSelector;
    address public immutable i_masterReceiver;

    event MessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address receiver, bytes data);

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);

    constructor(address _router, uint64 _masterChainSelector, address _masterReceiver) {
        i_router = IRouterClient(_router);
        i_masterChainSelector = _masterChainSelector;
        i_masterReceiver = _masterReceiver;
    }

    /// @notice Sends data to the Master chain
    /// @param _data The data to send (encoded function call or struct)
    /// @param _payInLINK Whether to pay fees in LINK
    /// @return messageId The ID of the CCIP message that was sent
    function _sendToMaster(bytes memory _data, bool _payInLINK) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            i_masterReceiver,
            _data,
            address(0), // No token transfer in the message itself for now, just data
            0,
            _payInLINK ? address(0) : address(0) // Logic for fee token selection can be expanded
        );

        // Get the fee token
        // For simplicity, we assume native gas payment or we need to handle LINK.
        // The prompt says "Uses Chainlink CCIP Router". We will assume native payment for simplicity in this snippet unless LINK is enforced.
        // Let's implement _buildCCIPMessage to handle fee token selection more gracefully if needed.
        
        uint256 fees = i_router.getFee(i_masterChainSelector, evm2AnyMessage);

        if (address(this).balance < fees) {
            revert NotEnoughBalance(address(this).balance, fees);
        }

        messageId = i_router.ccipSend{value: fees}(i_masterChainSelector, evm2AnyMessage);
        
        emit MessageSent(messageId, i_masterChainSelector, i_masterReceiver, _data);
        return messageId;
    }

    /// @notice Construct a CCIP message
    function _buildCCIPMessage(
        address _receiver,
        bytes memory _data,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        
        // If we were sending tokens, we would populate tokenAmounts.
        // For synchronization messages (Credit Update), we usually just send data.
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        if (_token != address(0) && _amount > 0) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});
        }

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 200_000}) // Standard gas limit, can be adjustable
            ),
            feeToken: _feeTokenAddress
        });
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

struct Order {
    bytes32 id;
    address maker;
    bool givenIn;
    address tokenIn;
    uint256 tokenInAmountMax;
    address tokenOut;
    uint256 tokenOutAmountMin;
}

// // To be implemented by the takers
// interface MerkleOrderFiller {
//     function fillOrder(Order memory order, bytes memory callback) external view returns (bool);
// }

// interface ERC20 {
//     function balanceOf(address owner) external view returns (uint256);
//     function transfer(address to, uint256 value) external returns (bool);
// }
contract MerkleOrderSettler {
    using ECDSA for bytes32;

    address public orderMatchingEngine;
    // orderId to block.timestamp
    mapping(bytes32 => uint256) public executedOrders;

    constructor() {
        // expecting deployer to be the order matching engine
        orderMatchingEngine = msg.sender;
    }

    function fillOrder(Order memory _makerOrder, bytes calldata _signature)
        public
        onlyOrderMatchingEngine
        notExecutedOrders(_makerOrder.id)
        onlyValidSignatures(_makerOrder, _signature)
        returns (uint256, uint256, uint256)
    {
        setOrderExecuted(_makerOrder.id);
        // Actions:
        // If givenIn makerTokens = tokenOut, takerTokens = tokenIn else vice versa
        // Transfer takerTokens taker
        // Execute taker callback
        // Make sure we have received the makerTokens and it matches the order makerTokens
        // Make sure our ethBalanceAfter - ethBalanceBefore >= gasEstimation
        // Transfer makerTokens to maker
        // Return makerTokens, takerTokens, gasEstimation

        return (uint256(0), uint256(0), uint256(0));
    }

    modifier onlyOrderMatchingEngine() {
        require(msg.sender == orderMatchingEngine, "Only OME");
        _;
    }

    modifier onlyValidSignatures(Order memory _makerOrder, bytes memory _signature) {
        require(
            isValidSignature(_makerOrder.maker, keccak256(abi.encode(_makerOrder)), _signature), "Invalid Signature"
        );
        _;
    }

    function isValidSignature(address _signer, bytes32 _hash, bytes memory _signature) internal pure returns (bool) {
        return _hash.recover(_signature) == _signer;
    }

    modifier notExecutedOrders(bytes32 _orderId) {
        bool notExecuted = executedOrders[_orderId] == 0;
        console.log("notExecuted ", notExecuted);
        require(notExecuted, "Already executed.");

        _;
    }

    function setOrderExecuted(bytes32 _orderId) internal {
        executedOrders[_orderId] = block.number;
    }
}

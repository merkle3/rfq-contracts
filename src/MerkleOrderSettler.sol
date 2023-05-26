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

    constructor() {
        // expecting deployer to be the order matching engine
        orderMatchingEngine = msg.sender;
    }

    function fillOrder(Order memory _makerOrder, bytes calldata _signature)
        public
        view
        onlyOrderMatchingEngine
        onlyValidSignatures(_makerOrder, _signature)
        returns (uint256, uint256, uint256)
    {
        // TODO: Actions
        // Transfer tokenIn to taker
        // Execute taker callback
        // Make sure we have received the tokenOut and it matches the order tokenOut
        // Make sure our ethBalanceAfter - ethBalanceBefore >= gasEstimation
        // Transfer tokenOut to maker

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

    function isValidSignature(address signer, bytes32 hash, bytes memory signature) internal pure returns (bool) {
        require(signer != address(0), "Signer cannot be address(0)");

        bytes32 signedHash = hash.toEthSignedMessageHash();
        return signedHash.recover(signature) == signer;
    }
}

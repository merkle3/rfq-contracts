// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

struct Order {
    bytes32 id;
    address maker;
    bool givenIn;
    address tokenIn;
    uint256 tokenInAmountMax;
    address tokenOut;
    uint256 tokenOutAmountMin;
}

// To be implemented by the takers
interface MerkleOrderFiller {
    function fillOrder(Order memory order, bytes memory callback) external view returns (bool);
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

contract MerkleAuctionSettler {
    function fillOrder(
        bytes memory orderBytes,
        bytes memory signature,
        address filler,
        uint256 minimumEthBalance,
        bytes memory fillerCallback
    ) public returns (uint256, uint256, uint256) {
        // Validation:
        // Only Order Matching Engine can call this
        // Signature verification

        // Actions:
        // Transfer tokenIn to taker
        // Execute taker callback
        // Make sure we have received the tokenOut and it matches the order tokenOut
        // Make sure our ethBalanceAfter - ethBalanceBefore >= gasEstimation
        // Transfer tokenOut to maker

        return (uint256(0), uint256(0), uint256(0));
    }
}

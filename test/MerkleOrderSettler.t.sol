// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MerkleOrderSettler.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MerkleOrderSettlerTest is Test {
    using ECDSA for bytes32;

    MerkleOrderSettler public merkleOrderSettler;

    uint256 makerPrivateKey = 1;
    address maker = vm.addr(makerPrivateKey);

    function setUp() public {
        merkleOrderSettler = new MerkleOrderSettler();
    }
    // TODO: implement full flow tests
    // function testValidSignature() public {
    //     (Order memory order, bytes memory signature) = getOrderAndSignature(maker, bytes32(""));
    //     merkleOrderSettler.settle(order, signature, "0x");
    // }
    // function testNotExecutedOrders() public {
    //     (Order memory order, bytes memory signature) = getOrderAndSignature(maker, bytes32("test"));
    //     merkleOrderSettler.settle(order, signature, "0x");
    //     vm.expectRevert("Already executed.");
    //     merkleOrderSettler.settle(order, signature, "0x");
    // }

    function testInvalidSignature() public {
        // expect revert since signer does not match the private key used to sign
        vm.expectRevert("Invalid Signature");
        (Order memory order, bytes memory signature) = getOrderAndSignature(address(0x1), bytes32(""));
        merkleOrderSettler.settle(order, signature, "0x");
    }

    function testSignerZeroAddr() public {
        vm.expectRevert("Invalid Signature");
        (Order memory order, bytes memory signature) = getOrderAndSignature(address(0), bytes32(""));
        merkleOrderSettler.settle(order, signature, "0x");
    }

    function testOnlyOme() public {
        // only Order Matching Engine can call fillOrder
        vm.expectRevert("Only OME");
        vm.prank(address(0x1));
        (Order memory order, bytes memory signature) = getOrderAndSignature(maker, bytes32(""));
        merkleOrderSettler.settle(order, signature, "0x");
    }

    function getOrderAndSignature(address signer, bytes32 orderId) public view returns (Order memory, bytes memory) {
        Order memory order = Order({
            id: orderId,
            maker: signer,
            taker: address(0),
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0),
            amountOut: 0,
            maximizeOut: false
        });
        bytes32 digest = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, digest);
        return (order, abi.encodePacked(r, s, v));
    }
}

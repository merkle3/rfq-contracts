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

    function testValidSignature() public view {
        (Order memory order, bytes memory signature) = getOrderAndSignature(maker);
        merkleOrderSettler.fillOrder(order, signature);
    }

    function testInvalidSignature() public {
        // expect revert since signer does not match the private key used to sign
        vm.expectRevert("Invalid Signature");
        (Order memory order, bytes memory signature) = getOrderAndSignature(address(0x1));
        merkleOrderSettler.fillOrder(order, signature);
    }

    function testSignerZeroAddr() public {
        vm.expectRevert("Signer cannot be address(0)");
        (Order memory order, bytes memory signature) = getOrderAndSignature(address(0));
        merkleOrderSettler.fillOrder(order, signature);
    }

    function testOnlyOme() public {
        // only Order Matching Engine can call fillOrder
        vm.expectRevert("Only OME");
        vm.prank(address(0x1));
        (Order memory order, bytes memory signature) = getOrderAndSignature(maker);
        merkleOrderSettler.fillOrder(order, signature);
    }

    function getOrderAndSignature(address signer) public view returns (Order memory, bytes memory) {
        Order memory order = Order({
            id: bytes32(0),
            maker: signer,
            givenIn: false,
            tokenIn: address(0),
            tokenInAmountMax: 0,
            tokenOut: address(0),
            tokenOutAmountMin: 0
        });
        bytes32 digest = keccak256(abi.encode(order)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, digest);
        return (order, abi.encodePacked(r, s, v));
    }
}

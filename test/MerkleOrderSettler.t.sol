// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MerkleOrderSettler.sol";
import "../src/MerkleOrderTaker.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MerkleOrderSettlerTest is Test {
    using ECDSA for bytes32;

    Settler public merkleOrderSettler;
    Taker public taker;

    uint256 makerPrivateKey = 1;
    address maker = vm.addr(makerPrivateKey);

    function setUp() public {
        string memory forkUrl = vm.rpcUrl("fork_url");
        vm.createSelectFork(forkUrl);
        merkleOrderSettler = new Settler();
        taker = new Taker();
    }

    function testInvalidSignature() public {
        // expect revert since signer does not match the private key used to sign
        vm.expectRevert("Invalid Signature");
        Order memory order = getDummyOrder(address(0x1), bytes32("testOrder"));
        merkleOrderSettler.settle(order, getSig(order), "0x");
    }

    function testSignerZeroAddr() public {
        vm.expectRevert("Invalid Signature");
        Order memory order = getDummyOrder(address(0), bytes32("testOrder"));
        merkleOrderSettler.settle(order, getSig(order), "0x");
    }

    function testOnlyOme() public {
        // only Order Matching Engine can call fillOrder
        vm.expectRevert("Only OME");
        vm.prank(address(0x1));
        Order memory order = getDummyOrder(maker, bytes32("testOrder"));
        merkleOrderSettler.settle(order, getSig(order), "0x");
    }

    function getDummyOrder(address makerAddr, bytes32 orderId) public pure returns (Order memory) {
        Order memory order = Order({
            id: orderId,
            maker: makerAddr,
            taker: address(0),
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0),
            amountOut: 0,
            maximizeOut: false
        });
        return order;
    }

    function testValidUsdcUsdtSettle() public {
        Order memory order = getUsdcUstOrder(maker, bytes32("testOrder"));
        // taker is required to refund the gas
        // setting dummy 1 eth for now
        uint256 gasToRefund = uint256(1 ether);
        vm.deal(address(taker), 1 ether);

        merkleOrderSettler.settle(order, getSig(order), abi.encodePacked(gasToRefund));
    }

    // same orderId should revert with already executed
    function testNotExecutedOrders() public {
        Order memory order = getUsdcUstOrder(maker, bytes32("testOrder"));
        uint256 gasToRefund = uint256(1 ether);
        vm.deal(address(taker), 1 ether);
        merkleOrderSettler.settle(order, getSig(order), abi.encodePacked(gasToRefund));
        vm.expectRevert("Already executed.");
        merkleOrderSettler.settle(order, getSig(order), abi.encodePacked(gasToRefund));
    }

    function getSig(Order memory order) public view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function getUsdcUstOrder(address makerAddr, bytes32 orderId) public returns (Order memory) {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt = 0xa47c8bf37f92aBed4A126BDA807A7b7498661acD;
        uint256 amountIn = 10 * 1e6; // maker needs to have this
        uint256 amountOut = 10 * 1e6; // taker needs to have this
        // setup balances
        deal(usdc, makerAddr, amountIn);
        deal(usdt, address(taker), amountIn);

        // setup approval
        vm.startPrank(address(makerAddr));
        ERC20(usdc).approve(address(merkleOrderSettler), amountIn);
        vm.stopPrank();

        Order memory order = Order({
            id: orderId,
            maker: makerAddr,
            taker: address(taker),
            tokenIn: usdc,
            amountIn: amountIn,
            tokenOut: usdt,
            amountOut: amountOut,
            maximizeOut: true
        });
        return order;
    }
}

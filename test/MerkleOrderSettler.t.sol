// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MerkleOrderSettler.sol";
import "../src/MerkleOrderTaker.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MerkleOrderSettlerTest is Test {
    using ECDSA for bytes32;

    MerkleOrderSettler public merkleOrderSettler;
    Taker public taker;

    uint256 makerPrivateKey = 1;
    address maker = vm.addr(makerPrivateKey);
    string name = "MBS";
    string version = "test";

    function setUp() public {
        string memory forkUrl = vm.rpcUrl("fork_url");
        vm.createSelectFork(forkUrl);
        merkleOrderSettler = new MerkleOrderSettler(name, version);
        taker = new Taker();
    }

    function testOnlyOwnerUpdateOrderMatchingEngine() public {
        vm.expectRevert("Only owner");
        merkleOrderSettler.updateOrderMatchingEngine(address(0x1));
    }

    function testUpdateOrderMatchingEngine() public {
        vm.prank(0x65D072964AF7DdBC25cDb726A97B4d1a04A32242);
        address _orderMatchingEngine = address(0x1);
        merkleOrderSettler.updateOrderMatchingEngine(_orderMatchingEngine);
        bool isUpdated = merkleOrderSettler.getOrderMatchingEngine(_orderMatchingEngine);
        assert(isUpdated);
    }

    function testByPassValidation() public {
        // maker address in order != maker address in signature, should trigger invalid sig
        address fakeMaker = address(0x1);
        Order memory order = getUsdcUsdtOrder(fakeMaker, bytes16("testOrder"));
        // taker is required to refund the gas
        // setting dummy 1 eth for now
        uint256 minEthPayment = uint256(1 ether);
        vm.deal(address(taker), minEthPayment);
        // msg.sender is 0 address shold trigger only ome validation
        vm.prank(address(0));
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", minEthPayment);
    }

    function testInvalidSignature() public {
        // expect revert since signer does not match the private key used to sign
        vm.expectRevert("Invalid Signature");
        Order memory order = getDummyOrder(address(0x1), bytes16("testOrder"));
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", 0);
    }

    function testSignerZeroAddr() public {
        vm.expectRevert("Invalid Signature");
        Order memory order = getDummyOrder(address(0), bytes16("testOrder"));
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", 0);
    }

    function testOnlyOme() public {
        // only Order Matching Engine can call fillOrder
        vm.expectRevert("Only OME");
        vm.prank(address(0x1));
        Order memory order = getDummyOrder(maker, bytes16("testOrder"));
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", 0);
    }

    function getDummyOrder(address makerAddr, bytes16 orderId) public pure returns (Order memory) {
        Order memory order = Order({
            id: orderId,
            maker: makerAddr,
            taker: address(0),
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0),
            amountOut: 0,
            maximizeOut: false,
            expiration: uint256(0)
        });
        return order;
    }

    function testValidUsdcUsdtSettle() public {
        Order memory order = getUsdcUsdtOrder(maker, bytes16("testOrder"));
        // taker is required to refund the gas
        // setting dummy 1 eth for now
        uint256 minEthPayment = uint256(1 ether);
        vm.deal(address(taker), minEthPayment);

        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", minEthPayment);
        finalBalanceChecks(order);
    }

    function finalBalanceChecks(Order memory _order) public {
        uint256 makerFinalTokenOutBalance = ERC20(_order.tokenOut).balanceOf(_order.maker);
        uint256 takerFinalTokenInBalance = ERC20(_order.tokenIn).balanceOf(_order.taker);
        // maker sure maker has tokenOut
        assertEq(_order.amountOut, makerFinalTokenOutBalance);
        // maker sure taker has tokenIn
        assertEq(_order.amountIn, takerFinalTokenInBalance);
    }

    // same orderId should revert with already executed
    function testNotExecutedOrders() public {
        Order memory order = getUsdcUsdtOrder(maker, bytes16("testOrder"));

        uint256 minEthPayment = uint256(1 ether);
        vm.deal(address(taker), minEthPayment);
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", minEthPayment);
        vm.expectRevert("Already executed.");
        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", minEthPayment);
    }

    function getSig(Order memory order) public view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function getEIP712Sig(Order memory order) public view returns (bytes memory) {
        bytes32 digest = getTypedDataHash(
            buildDomainSeparatorV4(keccak256(bytes(name)), keccak256(bytes(version))),
            keccak256(
                abi.encode(
                    keccak256(
                        "Order(bytes16 id, address maker, address taker, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, uint256 expiration,bool maximizeOut)"
                    ),
                    order.id,
                    order.maker,
                    order.taker,
                    order.tokenIn,
                    order.amountIn,
                    order.tokenOut,
                    order.amountOut,
                    order.expiration,
                    order.maximizeOut
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function buildDomainSeparatorV4(bytes32 _hashedName, bytes32 _hashedVersion) public view returns (bytes32) {
        bytes32 _TYPE_HASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return
            keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(merkleOrderSettler)));
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(bytes32 DOMAIN_SEPARATOR, bytes32 digest) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, digest));
    }

    function getUsdcUsdtOrder(address _maker, bytes16 _orderId) public returns (Order memory) {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt = 0xa47c8bf37f92aBed4A126BDA807A7b7498661acD;
        uint256 amountIn = 10 * 1e6; // maker needs to have this
        uint256 amountOut = 10.02 * 1e6; // taker needs to have this

        orderSetup(_maker, address(taker), usdc, usdt, amountIn, amountOut);
        vm.warp(1641070800);

        Order memory order = Order({
            id: _orderId,
            maker: _maker,
            taker: address(taker),
            tokenIn: usdc,
            amountIn: amountIn,
            tokenOut: usdt,
            amountOut: amountOut,
            maximizeOut: true,
            expiration: uint256(1641070800)
        });
        return order;
    }

    function orderSetup(
        address _maker,
        address _taker,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut
    ) public {
        // setup balances
        deal(_tokenIn, _maker, _amountIn);
        deal(_tokenOut, address(_taker), _amountOut);

        // setup approval
        vm.startPrank(address(_maker));
        ERC20(_tokenIn).approve(address(merkleOrderSettler), _amountIn);
        vm.stopPrank();
    }

    function testValidWethWbtcSettle() public {
        Order memory order = getWethWbtcOrder(maker, bytes16("testOrder"), true);
        // taker is required to refund the gas
        // setting dummy 1 eth for now
        uint256 minEthPayment = uint256(1 ether);
        vm.deal(address(taker), minEthPayment);

        merkleOrderSettler.settle(order, getEIP712Sig(order), "0x", minEthPayment);

        finalBalanceChecks(order);
    }

    function getWethWbtcOrder(address _maker, bytes16 _orderId, bool _maximizeOut) public returns (Order memory) {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        uint256 amountIn = 1 * 1e18; // maker needs to have this
        uint256 amountOut = 0.5 * 1e8; // taker needs to have this

        orderSetup(_maker, address(taker), weth, wbtc, amountIn, amountOut);

        vm.warp(1641070800);
        Order memory order = Order({
            id: _orderId,
            maker: _maker,
            taker: address(taker),
            tokenIn: weth,
            amountIn: amountIn,
            tokenOut: wbtc,
            amountOut: amountOut,
            maximizeOut: _maximizeOut,
            expiration: uint256(1641070800)
        });
        return order;
    }
}

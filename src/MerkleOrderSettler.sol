// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

// To be implemented by the takers
interface MerkleOrderTaker {
    function take(Order memory order, uint256 minPayment, bytes calldata data) external returns (bool);
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external;
    function transferFrom(address from, address to, uint256 value) external;
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

struct Order {
    bytes32 id;
    address maker;
    address taker;
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    uint256 amountOut;
    uint256 expiration;
    bool maximizeOut;
}

contract MerkleOrderSettler {
    using ECDSA for bytes32;

    address public owner = 0x65D072964AF7DdBC25cDb726A97B4d1a04A32242;

    mapping(address => bool) orderMatchingEngine;

    // orderId to block.timestamp
    mapping(bytes32 => uint256) public executedOrders;

    constructor() {
        // enable deployer to call settle
        orderMatchingEngine[msg.sender] = true;
    }

    // avoiding stack too deep error
    struct SettleLocalVars {
        Order order;
        ERC20 tokenIn;
        ERC20 tokenOut;
        uint256 minzdAmountIn;
        uint256 maxzdAmountOut;
        bytes takerData;
        uint256 minPayment;
    }

    function settle(Order memory _order, bytes calldata _signature, bytes calldata _takerData, uint256 minPayment)
        public
        onlyOrderMatchingEngine
        onlyValidSignatures(_order, _signature)
        notExecutedOrders(_order.id)
        notExpiredOrders(_order.expiration)
        returns (uint256, uint256)
    {
        uint256 balanceBefore = address(this).balance;

        SettleLocalVars memory vars;
        vars.order = _order;
        vars.takerData = _takerData;
        vars.minPayment = minPayment;

        // maker sends tokenIn and receives tokenOut
        (vars.minzdAmountIn, vars.tokenIn, vars.tokenOut) =
            (_order.amountIn, ERC20(vars.order.tokenIn), ERC20(vars.order.tokenOut));

        // Pull taker tokens out from maker and send to taker, assume erc20.approve is already called
        vars.tokenIn.transferFrom(vars.order.maker, vars.order.taker, vars.minzdAmountIn);

        uint256 tokenOutBalanceBefore = vars.tokenOut.balanceOf(address(this));

        // Executes take callback which transfers tokenOut to settler
        bool success = MerkleOrderTaker(vars.order.taker).take(vars.order, vars.minPayment, vars.takerData);
        require(success, "Taker callback failed.");

        uint256 tokenOutBalanceAfter = vars.tokenOut.balanceOf(address(this));
        // Assume we already simulated taker callback and we know the maxzdAmountToMaker that will be transfered in the callback
        require(tokenOutBalanceAfter > tokenOutBalanceBefore, "Not enough tokenOut.");

        vars.maxzdAmountOut = tokenOutBalanceAfter - tokenOutBalanceBefore;

        vars.tokenOut.transfer(vars.order.maker, vars.maxzdAmountOut);

        if (vars.order.maximizeOut) {
            // The output must be at least what the user expected
            require(vars.maxzdAmountOut >= vars.order.amountOut, "Not enough tokenOut.");
        } else {
            require(vars.maxzdAmountOut == vars.order.amountOut, "Output must be what user expected.");
            bool isTokenInDustLeft = vars.tokenIn.balanceOf(address(this)) > 0;
            if (isTokenInDustLeft) {
                vars.tokenIn.transfer(vars.order.maker, vars.tokenIn.balanceOf(address(this)));
            }
        }

        // Minimum payment check
        uint256 balanceAfter = address(this).balance;
        bool takerTransferedMinPayment = (balanceAfter - balanceBefore >= vars.minPayment);

        require(takerTransferedMinPayment, "Taker payment did not cover minimum payment.");

        setOrderExecuted(vars.order.id);

        return (vars.minzdAmountIn, vars.maxzdAmountOut);
    }

    function updateOrderMatchingEngine(address _orderMatchingEngine) public onlyOwner {
        orderMatchingEngine[_orderMatchingEngine] = true;
    }

    function getOrderMatchingEngine(address _orderMatchingEngine) public view returns (bool) {
        return orderMatchingEngine[_orderMatchingEngine];
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier notExpiredOrders(uint256 expiration) {
        require(block.timestamp <= expiration, "Order expired.");
        _;
    }

    modifier onlyOrderMatchingEngine() {
        // address(0) allowed to by pass this check in order to perform eth_call simulations
        require(msg.sender == address(0) || orderMatchingEngine[msg.sender], "Only OME");
        _;
    }

    modifier onlyValidSignatures(Order memory _makerOrder, bytes memory _signature) {
        // address(0) allowed to by pass this check in order to perform eth_call simulations
        require(
            msg.sender == address(0)
                || isValidSignature(_makerOrder.maker, keccak256(abi.encode(_makerOrder)), _signature),
            "Invalid Signature"
        );
        _;
    }

    function isValidSignature(address _signer, bytes32 _hash, bytes memory _signature) internal pure returns (bool) {
        return _hash.recover(_signature) == _signer;
    }

    modifier notExecutedOrders(bytes32 _orderId) {
        bool notExecuted = executedOrders[_orderId] == 0;
        require(notExecuted, "Already executed.");

        _;
    }

    function setOrderExecuted(bytes32 _orderId) internal {
        executedOrders[_orderId] = block.number;
    }

    receive() external payable {}
}

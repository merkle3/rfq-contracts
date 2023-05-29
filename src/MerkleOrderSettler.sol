// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

// // To be implemented by the takers
interface MerkleOrderTaker {
    function take(Order memory order, bytes calldata callback) external view returns (bool);
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

struct Order {
    bytes32 id;
    address maker;
    address taker;
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    uint256 amountOut;
    bool maximizeOut; // if true maker sends tokenIn and receives tokenOut else vice versa
}

contract MerkleOrderSettler {
    using ECDSA for bytes32;

    address public orderMatchingEngine;
    // orderId to block.timestamp
    mapping(bytes32 => uint256) public executedOrders;

    uint256 startGas;

    constructor() {
        // expecting deployer to be the order matching engine
        orderMatchingEngine = msg.sender;
    }

    struct SettleLocalVars {
        Order _order;
        ERC20 makerErc20;
        ERC20 takerErc20;
        uint256 maxzdAmountToMaker;
        uint256 minzdAmountToTaker;
        uint256 gasEstimation;
    }

    function settle(Order memory _order, bytes calldata _signature, bytes calldata _takeCallback)
        public
        startGasTracker
        onlyOrderMatchingEngine
        notExecutedOrders(_order.id)
        onlyValidSignatures(_order, _signature)
        returns (uint256, uint256, uint256)
    {
        // avoiding stack too deep error
        SettleLocalVars memory vars;
        vars._order = _order;
        setOrderExecuted(vars._order.id);

        // If maximizeOutput is true => maker sends tokenIn and receives tokenOut else vice versa
        (, vars.minzdAmountToTaker, vars.makerErc20, vars.takerErc20) = vars._order.maximizeOut
            ? (vars._order.amountOut, vars._order.amountIn, ERC20(vars._order.tokenOut), ERC20(vars._order.tokenIn))
            : (vars._order.amountIn, vars._order.amountOut, ERC20(vars._order.tokenIn), ERC20(vars._order.tokenOut));

        // Pull taker tokens out from maker and send to taker
        vars.takerErc20.transferFrom(vars._order.maker, vars._order.taker, vars.minzdAmountToTaker);

        uint256 makerBalanceBefore = vars.makerErc20.balanceOf(address(this));
        uint256 orderSettlerEthBalanceBefore = address(this).balance;

        // Executes take callback
        bool success = MerkleOrderTaker(vars._order.taker).take(vars._order, _takeCallback);
        require(success, "Taker callback failed.");

        uint256 makerBalanceAfter = vars.makerErc20.balanceOf(address(this));
        // Assume we already simulated taker callback and we know the maxzdAmountToMaker that will be transfered in the callback
        require(makerBalanceAfter > makerBalanceBefore, "Not enough amount to maker.");

        // here we could just transfer what the maker asked for and maybe pickpocket difference?
        uint256 maxzdAmountToMaker = makerBalanceAfter - makerBalanceBefore;

        vars.makerErc20.transfer(vars._order.maker, maxzdAmountToMaker);

        // Gas check
        (bool enoughGasSentByTaker, uint256 gasEstimation) = estimateGas(orderSettlerEthBalanceBefore);
        require(enoughGasSentByTaker, "Not enough gas sent by taker.");

        return (maxzdAmountToMaker, vars.minzdAmountToTaker, gasEstimation);
    }

    function estimateGas(uint256 ethBalanceBefore) internal view returns (bool, uint256) {
        uint256 ethBalanceAfter = address(this).balance;
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        uint256 gasSpentWei = gasUsed * tx.gasprice;
        return (ethBalanceAfter - ethBalanceBefore >= gasSpentWei, gasUsed);
    }

    modifier startGasTracker() {
        startGas = gasleft();
        _;
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
        require(notExecuted, "Already executed.");

        _;
    }

    function setOrderExecuted(bytes32 _orderId) internal {
        executedOrders[_orderId] = block.number;
    }
}

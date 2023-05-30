// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

// To be implemented by the takers
interface MerkleOrderTaker {
    function take(Order memory order, bytes calldata data) external returns (bool);
}

interface MerkleOrderSettler {
    function getOrderDetail(Order memory _order) external pure returns (uint256, uint256, ERC20, ERC20);
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
    bool maximizeOut; // if true maker sends tokenIn and receives tokenOut else vice versa
}

contract Settler is MerkleOrderSettler {
    using ECDSA for bytes32;

    address public owner = 0x65D072964AF7DdBC25cDb726A97B4d1a04A32242;

    address public orderMatchingEngine;
    // orderId to block.timestamp
    mapping(bytes32 => uint256) public executedOrders;

    // gas used tracker variable
    uint256 startGas;

    constructor() {
        // expecting deployer to be the order matching engine
        orderMatchingEngine = msg.sender;
    }

    // avoiding stack too deep error
    struct SettleLocalVars {
        Order _order;
        ERC20 makerErc20;
        ERC20 takerErc20;
        uint256 maxzdAmountToMaker;
        uint256 minzdAmountToTaker;
        uint256 gasEstimation;
    }

    function settle(Order memory _order, bytes calldata _signature, bytes calldata _takerData)
        public
        startGasTracker
        onlyOrderMatchingEngine
        notExecutedOrders(_order.id)
        onlyValidSignatures(_order, _signature)
        returns (uint256, uint256, uint256)
    {
        SettleLocalVars memory vars;
        vars._order = _order;
        setOrderExecuted(vars._order.id);

        // If maximizeOutput is true => maker sends tokenIn and receives tokenOut else vice versa
        (, vars.minzdAmountToTaker, vars.makerErc20, vars.takerErc20) = getOrderDetail(_order);

        // Pull taker tokens out from maker and send to taker, assume erc20.approve is already called
        vars.takerErc20.transferFrom(vars._order.maker, vars._order.taker, vars.minzdAmountToTaker);

        uint256 makerBalanceBefore = vars.makerErc20.balanceOf(address(this));
        uint256 orderSettlerEthBalanceBefore = address(this).balance;

        // Executes take callback
        bool success = MerkleOrderTaker(vars._order.taker).take(vars._order, _takerData);
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

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function updateOrderMatchingEngine(address _orderMatchingEngine) public onlyOwner {
        orderMatchingEngine = _orderMatchingEngine;
    }

    function getOrderDetail(Order memory _order) public pure returns (uint256, uint256, ERC20, ERC20) {
        return _order.maximizeOut
            ? (_order.amountOut, _order.amountIn, ERC20(_order.tokenOut), ERC20(_order.tokenIn))
            : (_order.amountIn, _order.amountOut, ERC20(_order.tokenIn), ERC20(_order.tokenOut));
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

    receive() external payable {}
}

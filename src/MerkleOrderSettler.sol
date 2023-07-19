// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

// To be implemented by the takers that fill the orders
interface MerkleOrderTaker {
    function take(
        // the order to fill
        Order memory order, 
        // the minimum payment, in native token, that the taker must pay before the callback is done
        uint256 minPayment, 
        // the optional custom data that a taker can pass to their callback
        bytes calldata data
    ) external returns (
        // return true if everything worked
        bool
    );
}

// basic ERC20 interface
interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external;
    function transferFrom(address from, address to, uint256 value) external;
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

// a basic order for the RFQ settlement contract
struct Order {
    // the order maker
    address maker;

    // the token in for the order
    address tokenIn;

    // only when maximizeOut=true, the amout in
    uint256 amountIn;

    // the output token expected
    address tokenOut;

    // only when maximizeOut=false, the amount of token out
    uint256 amountOut;

    // when the order expires, in seconds
    uint256 expiration;

    // when maximizeOut=true, the amount of tokenOut is maximized, otherwise the amount of tokenIn is minimized
    bool maximizeOut;
}

contract MerkleOrderSettler is EIP712 {
    using ECDSA for bytes32;

    address public owner = 0x65D072964AF7DdBC25cDb726A97B4d1a04A32242;

    // a mapping of authorized matching engine.
    mapping(address => bool) public orderMatchingEngine;

    // orderId to block.timestamp
    mapping(bytes16 => bool) public executedOrders;

    // authorized swappers for makers
    mapping(address => mapping(address => bool)) public authorizedSwappers;

    constructor(string memory name, string memory version) EIP712(name, version) {
        // enable deployer to call settle
        orderMatchingEngine[msg.sender] = true;
    }

    // avoiding stack too deep error
    struct SettleLocalVars {
        Order order;

        // token data
        ERC20 tokenIn;
        ERC20 tokenOut;
        uint256 minzdAmountIn;
        uint256 maxzdAmountOut;

        // filler data
        address taker;
        bytes takerData;
        uint256 minPayment;
    }

    // events
    event OrderExecuted(bytes16 indexed orderId, uint256 input, uint256 output);

    /**
     * @notice Settles an order from the RFQ
     * @param _order The order to settle
     * @param _signature The signature of the order
     * @param taker The address of the taker
     * @param _takerData The optional data to pass to the taker callback     
     * @param minPayment The minimum payment, in native token, that the taker must pay before the callback is done
     */
    function settle(
        Order memory _order, 
        bytes calldata _signature, 
        address taker,
        bytes calldata _takerData, 
        uint256 minPayment
    )
        public
        onlyOrderMatchingEngine
        notExpiredOrders(_order.expiration)
        _notExecutedOrders(_order)
        onlyValidSignatures(_order, _signature)
        returns (uint256, uint256)
    {
        // keep track of the balance before the settlement to track filler payment
        uint256 balanceBefore = address(this).balance;

        SettleLocalVars memory vars;
        bytes32 orderHash = getOrderHash(_order);

        vars.order = _order;
        vars.takerData = _takerData;
        vars.taker = taker;
        vars.minPayment = minPayment;

        // maker sends tokenIn and receives tokenOut
        (vars.minzdAmountIn, vars.tokenIn, vars.tokenOut) =
            (_order.amountIn, ERC20(vars.order.tokenIn), ERC20(vars.order.tokenOut));

        // ------- TRANSFER INPUT TOKEN ------

        // save output balance before the callback
        uint256 tokenOutBalanceBefore = vars.tokenOut.balanceOf(address(this));
        uint256 tokenInBalanceBefore = vars.tokenIn.balanceOf(address(this));

        // (1) if we are minimizing input, we still need to transfer and the filler will send the max amount that can be used
        // (2) if we are maximizing output, we need to transfer the amount in that can be used by the filler
        vars.tokenIn.transferFrom(vars.order.maker, vars.order.taker, vars.minzdAmountIn);

        // ------- PERFORM CALLBACK -------

        // executes take callback which transfers tokenOut to settler
        bool success = MerkleOrderTaker(taker).take(vars.order, vars.minPayment, vars.takerData);

        // check that the callback succeeded
        require(success, "Taker callback failed.");

        // ------- TRANSFER OUTPUT TOKEN -------

        // save balances after the callback
        uint256 tokenOutBalanceAfter = vars.tokenOut.balanceOf(address(this));
        uint256 tokenInBalanceAfter = vars.tokenIn.balanceOf(address(this));

        // make sure we received something
        require(tokenOutBalanceAfter > tokenOutBalanceBefore, "OUTPUT_ZERO");

        // calculate the output we got
        vars.maxzdAmountOut = tokenOutBalanceAfter - tokenOutBalanceBefore;

        // calculate how much input we used
        vars.minzdAmountIn = tokenInBalanceBefore - tokenInBalanceAfter;

        // transfer the output to the maker
        vars.tokenOut.transfer(vars.order.maker, vars.maxzdAmountOut);

        if (vars.order.maximizeOut) {
            // the output must be at least what the user expected
            require(vars.maxzdAmountOut >= vars.order.amountOut, "Not enough tokenOut.");
        } else {
            // make sure the output is exactly what the user expected
            require(vars.maxzdAmountOut == vars.order.amountOut, "Output must be what user expected.");

            // return the input amount not consumed by the filler
            if (tokenInBalanceAfter > 0) {
                // clear the dust back to the user
                vars.tokenIn.transfer(vars.order.maker, tokenInBalanceAfter);
            }
        }

        // payment check
        uint256 totalPayment = address(this).balance - balanceBefore;

        // the taker must pay at least the minimum payment
        require(totalPayment >= vars.minPayment, "TAKER_UNDERPAID");

        // mark the order as executed
        setOrderExecuted(orderHash);

        return (vars.minzdAmountIn, vars.maxzdAmountOut);
    }

    // checks that the order has not expired
    modifier notExpiredOrders(uint256 expiration) {
        require(block.timestamp <= expiration, "Order expired.");
        _;
    }

    // checks that the order has not been executed
    modifier onlyOrderMatchingEngine() {
        // address(0) allowed to by pass this check in order to perform eth_call simulations
        require(
            // it's a simulation
            msg.sender == address(0) 
            // or the sender is an authorized order matching engine
            || orderMatchingEngine[msg.sender], 
        "Only OME");

        _;
    }

    // checks that the signature is valid
    modifier onlyValidSignatures(Order memory _makerOrder, bytes memory _signature) {
        // address(0) allowed to bypass this check in order to perform eth_call simulations
        require(
            // if the sender is address(0), it's a simulation 
            msg.sender == address(0) 
            // otherwise confirm the signature is valid
            || _confirmSignature(_makerOrder, _signature), 
        "Invalid Signature");

        _;
    }

    /**
     * @notice Returns the hash for an order
     * @param Order The order to hash
     */
    function getOrderHash(Order memory _order) public pure returns (bytes32 orderHash) {
        orderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "Order(address maker, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, uint256 expiration,bool maximizeOut)"
                    ),
                    _order.maker,
                    _order.tokenIn,
                    _order.amountIn,
                    _order.tokenOut,
                    _order.amountOut,
                    _order.expiration,
                    _order.maximizeOut
                )
            )
        );
    }

    /**
     * @notice Checks if a signature is valid
     * @param _order The order to check
     * @param _signature The signature to check
     */
    function _confirmSignature(Order memory _order, bytes memory _signature) internal view returns (bool) {
        bytes32 orderHash = getOrderHash(_order);
       
        address signer = ECDSA.recover(orderHash, _signature);
        
        // if the signature is the maker, it's valid
        if (signer == _order.maker) {
            return true;
        }

        // if the signature is from an authorized swapper
        if (authorizedSwappers[_order.maker][signer]) {
            return true;
        }

        return false;
    }

    /**
     * @notice checks if an order has already been executed
     * @param _order The order to check
     */
    modifier _notExecutedOrders(Order memory _order) {
        require(!executedOrders[getOrderHash(_order)], "Already executed.");
        _;
    }

    /**
     * @notice makes an order as executed
     * @param _order The order to check
     */
    function _setOrderExecuted(bytes32 orderHash) internal {
        executedOrders[orderHash] = block.number;
    }

    /**
     * @notice authorize a swapper
     * @param _swapper The address of the swapper
     */
    function setApprovalForAll(address _swapper, bool isApproved) public {
        authorizedSwappers[msg.sender][_swapper] = isApproved;
    }

    // --------------- ADMIN FUNCTIONS ---------------

    /**
     * @notice update the order matching engine status for an address
     * @param _orderMatchingEngine The address of the order matching engine
     * @param status The status of the order matching engine
     */
    function updateOrderMatchingEngine(address _orderMatchingEngine, bool status) public onlyOwner {
        orderMatchingEngine[_orderMatchingEngine] = status;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // --------------- RECEIVE ETHER --------------- 

    receive() external payable {}
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/MerkleOrderSettler.sol";

contract Taker is MerkleOrderTaker {
    // perform a trade
    function take(Order memory _order, uint256 minPayment, bytes calldata data) external returns (bool) {
        // make sure calldata isn't empty
        require(data.length > 0, "data is empty");

        ERC20 tokenIn = ERC20(_order.tokenIn);
        ERC20 tokenOut = ERC20(_order.tokenOut);

        bool isMaximizingOutput = _order.maximizeOut;
        uint256 inputAmount = tokenIn.balanceOf(address(this)); // calculate this somehow

        // .... DO SWAPPING ....

        uint256 outputAmount = _order.amountOut; // placeholder for tests

        // transfer the output token to the settler contract
        tokenOut.transfer(msg.sender, outputAmount);

        // if not maximize out, return the ununsed input token to the settler contract
        if (!isMaximizingOutput) {
            tokenIn.transfer(msg.sender, inputAmount);
        }

        // transfer eth payment to settler contract
        address payable caller = payable(msg.sender);

        caller.transfer(minPayment);

        // make sure to return trues
        return true;
    }
}

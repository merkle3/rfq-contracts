// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/MerkleOrderSettler.sol";

contract Taker is MerkleOrderTaker {
    function take(Order memory _order, uint256 minEthPayment, bytes calldata data) external returns (bool) {
        (uint256 amountOut, ERC20 tokenOut) = (_order.amountOut, ERC20(_order.tokenOut));
        // Transfer maker tokens to settler
        tokenOut.transfer(msg.sender, amountOut);

        // Transfer minEthPayment to msg.sender (settler)
        address payable caller = payable(msg.sender);
        caller.transfer(minEthPayment);

        // do more things: backruns, liquidations, etc.
        //  (...) = abi.decode(data, (...));
        return true;
    }
}

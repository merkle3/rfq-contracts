// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/MerkleOrderSettler.sol";

contract Taker is MerkleOrderTaker {
    function take(Order memory _order, bytes calldata data) external returns (bool) {
        (uint256 amountOut, ERC20 tokenOut) = (_order.amountOut, ERC20(_order.tokenOut));
        // Transfer maker tokens to settler
        tokenOut.transfer(msg.sender, amountOut);

        // Transfer gas required to msg.sender (caller)
        address payable caller = payable(msg.sender);
        (uint256 gasToRefund) = abi.decode(data, (uint256));
        caller.transfer(gasToRefund);

        // do more things: backruns, liquidations, etc.
        return true;
    }
}

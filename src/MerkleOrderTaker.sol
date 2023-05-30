// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/MerkleOrderSettler.sol";

contract Taker is MerkleOrderTaker {
    function take(Order memory _order, bytes calldata data) external returns (bool) {
        MerkleOrderSettler settler = MerkleOrderSettler(msg.sender);
        (uint256 amountToMaker,, ERC20 makerErc20,) = settler.getOrderDetail(_order);
        // Transfer maker tokens to settler
        makerErc20.transfer(msg.sender, amountToMaker);

        // Transfer gas required to msg.sender (caller)
        address payable caller = payable(msg.sender);
        (uint256 gasToRefund) = abi.decode(data, (uint256));
        caller.transfer(gasToRefund);
        // do more things: backruns, liquidations, etc.
        return true;
    }
}

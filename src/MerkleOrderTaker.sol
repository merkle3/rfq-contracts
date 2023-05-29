// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/MerkleOrderSettler.sol";

contract MerkleOrderTakerSample is MerkleOrderTaker {
    function take(Order memory _order, bytes calldata callback) external returns (bool) {
        MerkleOrderSettler settler = MerkleOrderSettler(msg.sender);
        (uint256 amountToMaker,, ERC20 makerErc20,) = settler.getAmounts(_order);
        // Transfer tokens to maker
        makerErc20.transfer(_order.maker, amountToMaker);
        // Transfer gas required to msg.sender (caller)
        address payable caller = payable(msg.sender);
        caller.transfer(1 * 1e18);
        // decode callback data and execute it
        return true;
    }
}

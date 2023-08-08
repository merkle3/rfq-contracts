// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MerkleOrderSettler.sol";

// To be implemented by the takers that fill the orders
interface MerkleOrderTaker {
    function take(
        // the order to fill
        Order memory order,
        // the minimum payment, in native token, that the taker must pay before the callback is done
        uint256 minPayment,
        // the optional custom data that a taker can pass to their callback
        bytes calldata data
    )
        external
        returns (
            // return true if everything worked
            bool
        );
}
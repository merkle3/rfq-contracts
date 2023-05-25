// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Order {
    bytes32 id;
    address maker;
    bool givenIn;
    address tokenIn;
    uint256 tokenInAmountMax;
    address tokenOut;
    uint256 tokenOutAmountMin;
}

// THE FILLERS IMPLEMENT THIS
interface MerkleOrderFiller {
    function fillOrder(Order memory order, bytes memory callback) external view returns (bool);
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

contract MerkleAuctionSettler {
    // make sure we fill a single order per id
    mapping(bytes32 => bool) usedOrders;
    address merkleEoA = address(0x123);

    // function testFillOrder(Order order, address filler, bytes fillerCallback) {
    // 	return fillOrder(order, null, filler, address(this).balance, fillerCallback)
    // }

    function verifySignature(bytes memory signature, bytes32 messageHash, address signer)
        internal
        pure
        returns (bool)
    {
        // Check that the signature is 65 bytes long
        require(signature.length == 65, "Invalid signature length");
        // Split the signature into r, s and v values
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        // Recover the address from the signature
        address recovered = ecrecover(messageHash, v, r, s);
        // Compare with the expected signer
        return (recovered == signer);
    }

    function fillOrder(
        bytes memory orderBytes,
        bytes memory signature,
        address filler,
        uint256 minimumEthBalance,
        bytes memory fillerCallback
    ) public returns (uint256, uint256, uint256) {
        require(msg.sender == merkleEoA || tx.origin == address(0));

        Order memory order = abi.decode(orderBytes, (Order));

        if (tx.origin != address(0)) {
            // verify signature
            require(verifySignature(signature, bytes32(orderBytes), order.maker), "Invalid signature");
        }

        // transfer input token to the filler
        ERC20(order.tokenIn).transfer(filler, order.tokenInAmountMax);

        // fill the order
        bool success = MerkleOrderFiller(filler).fillOrder(order, fillerCallback);

        require(success, "Filler callback failed");
        // make sure we have received the tokens required to fill the order
        // make sure we have received the tokens to cover the gas price of the call

        uint256 inputBalance = ERC20(order.tokenIn).balanceOf(address(this));
        uint256 outputBalance = ERC20(order.tokenOut).balanceOf(address(this));

        // flush all tokens on contract for both
        ERC20(order.tokenIn).transfer(order.maker, inputBalance);
        ERC20(order.tokenOut).transfer(order.maker, outputBalance);

        // make sure the customer has the promised tokens
        require(ERC20(order.tokenOut).balanceOf(order.maker) >= order.tokenOutAmountMin, "Invalid");

        uint256 finalEthBalance = address(this).balance;

        require(finalEthBalance > minimumEthBalance, "Underpayment of native token");

        return (inputBalance, outputBalance, address(this).balance);
    }
}

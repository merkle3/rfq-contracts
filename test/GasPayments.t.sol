// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MerkleOrderSettler.sol";
import "./mocks/Taker.sol";

contract GasPaymentTests is Test {
    MerkleOrderSettler merkleOrderSettler;
    Taker taker;
    address owner = address(0x5);

    function setUp() public {
        string memory forkUrl = vm.rpcUrl("fork_url");
        vm.createSelectFork(forkUrl);
        merkleOrderSettler = new MerkleOrderSettler(owner);
        taker = new Taker();
    }

    function testTakerShouldBeAbleToManageGas(uint256 gasAmount, uint256 withdrawAmount) public {
        vm.assume(gasAmount > withdrawAmount);

        address payable gasEOA = payable(vm.addr(30));

        // send some gas to the taker
        deal(gasEOA, gasAmount);

        // deposit the gas into the settler for the taker contract
        vm.startPrank(gasEOA);
        merkleOrderSettler.depositGas{value: gasAmount}(address(taker));

        // prepaid gas should be the same as the amount deposited
        uint256 prepaidGas = merkleOrderSettler.prepaidGas(address(taker));
        assertEq(prepaidGas, gasAmount);

        // withdraw the gas
        vm.startPrank(address(taker));
        merkleOrderSettler.withdrawGas(gasEOA,withdrawAmount);
        vm.stopPrank();

        // gas should be in the taker contract
        assertEq(gasEOA.balance, withdrawAmount);

        // prepaid gas should be zero
        uint256 prepaidGasAfter = merkleOrderSettler.prepaidGas(address(taker));
        assertEq(prepaidGasAfter, gasAmount - withdrawAmount);
    }

    function testOwnerShouldBeAbleToRecover(uint256 gasAmount) public {
        address payable gasEOA = payable(vm.addr(30));

        // send some gas to the taker
        deal(gasEOA, gasAmount);

        // deposit the gas into the settler for the taker contract
        vm.startPrank(gasEOA);
        merkleOrderSettler.depositGas{value: gasAmount}(gasEOA);
        vm.stopPrank();

        // prepaid gas should be the same as the amount deposited
        vm.expectRevert("Only owner");
        merkleOrderSettler.recoverGas(gasEOA, payable(address(1)));

        // make sure owner can recover
        deal(payable(owner), 0);
        vm.prank(owner);
        merkleOrderSettler.recoverGas(gasEOA, payable(owner));
        assertEq(owner.balance, gasAmount);
    }
}
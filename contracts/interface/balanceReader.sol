// SPDX-License-Identifier: MIT
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

pragma solidity ^0.8.0;

interface BalanceReader {
    function balanceOf(address user) view external returns(uint256);
}    
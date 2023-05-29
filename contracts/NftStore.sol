// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./library/LinkedList.sol";

contract NftStore{
    using LinkedListLib for LinkedListLib.UintLinkedList;


    mapping(address => LinkedListLib.UintLinkedList) nft;

    mapping(address => bool) NftIsExist;

    function checkNftSeries(address nftAddress) internal view returns(bool){
        return NftIsExist[nftAddress];
    }

    function addNftChain(address nftAddress) external {

    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./library/LinkedList.sol";

contract NftAuctionStorage {
    enum NftType {
        ERC721,
        ERC1155,
        Others
    }

    struct NFT {
        address nftAddress;
        uint256 tokenId;
        address owner;
        NftType nftType;
    }

    struct Listing {
        NFT nft;
        uint256 id;
        uint256 price;
        uint256 startTimestamp;
        address highestBidder;
        uint256 highestBidPrice;
    }

    
    uint256 public AUCTION_DURATION = 48 hours;

    uint256 public TIME_BUYING = 96 hours;

    LinkedListLib.UintLinkedList Nodes;

    address public vicDAO;

    address public VicAddress;

    mapping(uint256 => Listing) public listings;

    mapping(address => mapping(uint256 => uint256)) nftToIndex;

    uint256 public listingIdCounter;
}

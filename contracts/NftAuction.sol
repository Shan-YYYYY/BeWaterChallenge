// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./NftAuctionStorage.sol";
import "./interface/INftAuction.sol";
import "./library/LinkedList.sol";

contract NFTAuction is INftAuction, NftAuctionStorage {
    using LinkedListLib for LinkedListLib.UintLinkedList;

    constructor(address _vicDAO, address _VicAddress) {
        vicDAO = _vicDAO;
        VicAddress = _VicAddress;
    }

    using SafeMath for uint256;

    modifier onlyVicDao() {
        require(msg.sender == vicDAO, "only VicDao");
        _;
    }

    function _safeTransfer(
        address _nftAddress,
        uint256 _tokenId,
        NftType nftType,
        address _sender,
        address _recipient
    ) internal {
        if (nftType == NftType.ERC721) {
            IERC721(_nftAddress).transferFrom(_sender, _recipient, _tokenId);
        } else if (nftType == NftType.ERC1155) {
            IERC1155(_nftAddress).safeTransferFrom(
                _sender,
                _recipient,
                _tokenId,
                1,
                ""
            );
        } else {
            revert();
        }
    }

    function _getNftType(address nftAddress) internal view returns (NftType) {
        if (IERC721(nftAddress).supportsInterface(0x80ac58cd)) {
            return NftType.ERC721;
        } else if (IERC1155(nftAddress).supportsInterface(0xd9b67a26)) {
            return NftType.ERC1155;
        } else {
            return NftType.Others;
        }
    }

    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price
    ) external override onlyVicDao {
        require(_price > 0, "Price must be positive");
        require(nftToIndex[_nftAddress][_tokenId] == 0, "Already listed");
        NftType nftType = _getNftType(_nftAddress);
        _safeTransfer(
            _nftAddress,
            _tokenId,
            nftType,
            msg.sender,
            address(this)
        );
        listingIdCounter++;
        uint256 timestamp = block.timestamp;
        Nodes.add(listingIdCounter);
        listings[listingIdCounter] = Listing(
            NFT(_nftAddress, _tokenId, msg.sender, nftType),
            listingIdCounter,
            _price,
            timestamp,
            address(0),
            _price
        );
        emit ListingCreated(
            listingIdCounter,
            _nftAddress,
            _tokenId,
            timestamp,
            msg.sender,
            _price
        );
    }

    function getListing(
        uint256 _listingId
    )
        external
        view
        override
        returns (address, uint256, uint256, address, uint256)
    {
        Listing memory listing = listings[_listingId];
        return (
            listing.nft.nftAddress,
            listing.nft.tokenId,
            listing.highestBidPrice,
            listing.highestBidder,
            listing.startTimestamp
        );
    }

    function bid(uint256 _listingId, uint256 _price) external override {
        Listing storage listing = listings[_listingId];
        require(listing.id > 0, "Invalid listing");
        require(
            IERC20(VicAddress).balanceOf(msg.sender) > _price,
            "not enough vic balance"
        );
        uint256 timestamp = block.timestamp;
        require(
            timestamp < (listing.startTimestamp).add(AUCTION_DURATION),
            "beyond the auction time"
        );
        require(
            _price > listing.highestBidPrice,
            "less than the current maximum price"
        );
        IERC20(VicAddress).transferFrom(msg.sender, address(this), _price);
        if (listing.highestBidder != address(0)) {
            IERC20(VicAddress).transferFrom(
                address(this),
                listing.highestBidder,
                listing.highestBidPrice
            );
        }
        listing.highestBidPrice = _price;
        listing.highestBidder = msg.sender;

        emit Bid(
            _listingId,
            listing.nft.nftAddress,
            listing.nft.tokenId,
            _price,
            msg.sender
        );
    }

    function cancelListing(uint256 _listingId) external override onlyVicDao {
        Listing memory listing = listings[_listingId];
        require(listing.id > 0, "Invalid listing");
        require(
            listings[_listingId].nft.owner == msg.sender,
            "Only owner can cancel"
        );
        address nftAddress = listing.nft.nftAddress;
        uint256 tokenId = listing.nft.tokenId;
        if (listing.highestBidder != address(0)) {
            IERC20(VicAddress).transferFrom(
                address(this),
                listing.highestBidder,
                listing.highestBidPrice
            );
        }
        _removeListing(_listingId);
        emit ListingCanceled(_listingId, nftAddress, tokenId, msg.sender);
    }

    function _removeListing(uint _listingId) internal {
        Listing memory listing = listings[_listingId];
        Nodes.remove(_listingId);
        delete nftToIndex[listing.nft.nftAddress][listing.nft.tokenId];
        delete listings[_listingId];
    }

    function endAuction(uint256 _listingId) external override {
        Listing memory listing = listings[_listingId];
        require(
            block.timestamp > (listing.startTimestamp).add(AUCTION_DURATION),
            "Can not finish the auction yet"
        );
        require(
            listing.highestBidder != address(0),
            "there is currently no bid"
        );

        IERC20(VicAddress).transfer(listing.nft.owner, listing.highestBidPrice);
        uint price = listing.highestBidPrice;
        uint tokenId = listing.nft.tokenId;
        address nftAddress = listing.nft.nftAddress;
        NftType nftType = listing.nft.nftType;
        address bidder = listing.highestBidder;
        address owner = listing.nft.owner;
        _safeTransfer(nftAddress, tokenId, nftType, address(this), bidder);

        _removeListing(_listingId);
        emit NftSold(_listingId, nftAddress, tokenId, owner, bidder, price);
    }

    function buyNFT(uint256 _listingId, uint _price) external override {
        require(
            IERC20(VicAddress).balanceOf(msg.sender) >= _price,
            "not enough vic balance"
        );
        Listing memory listing = listings[_listingId];
        require(_price == (listing.price.mul(9)).div(10), "Invalid price");
        require(listing.id > 0, "Invalid listing");
        require(
            block.timestamp > (listing.startTimestamp).add(AUCTION_DURATION) &&
                block.timestamp < (listing.startTimestamp).add(TIME_BUYING),
            "Listing expired"
        );
        require(listing.highestBidder == address(0));
        IERC20(VicAddress).transferFrom(msg.sender, listing.nft.owner, _price);
        address nftAddress = listing.nft.nftAddress;
        uint tokenId = listing.nft.tokenId;
        NftType nftType = listing.nft.nftType;
        address owner = listing.nft.owner;
        _safeTransfer(nftAddress, tokenId, nftType, address(this), msg.sender);
        _removeListing(_listingId);
        emit NftSold(
            _listingId,
            nftAddress,
            tokenId,
            owner,
            msg.sender,
            _price
        );
    }

    function unsold(uint256 _listingId) external override {
        Listing memory listing = listings[_listingId];
        require(
            block.timestamp > listing.startTimestamp.add(TIME_BUYING),
            "the current time cannot be unsold"
        );
        address nftAddress = listing.nft.nftAddress;
        uint256 tokenId = listing.nft.tokenId;
        uint256 price = listing.price;
        _removeListing(_listingId);
        emit Unsold(_listingId, nftAddress, tokenId, price);
    }

    function getExpiredListingWithoutBid()
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory quantity = new uint256[](listingIdCounter);
        uint256 count = 0;
        uint256 index = 0;
        uint256 timestamp = block.timestamp;
        LinkedListLib.UintNode memory currentNode = Nodes.getNode(count);
        while (true) {
            count = currentNode.next;
            Listing memory listing = listings[count];
            currentNode = Nodes.getNode(count);
            if (currentNode.current == 0) {
                break;
            } else if (
                listing.startTimestamp.add(TIME_BUYING) < timestamp &&
                listing.highestBidder == address(0)
            ) {
                quantity[index++] = count;
            }
        }
        return quantity;
    }
}

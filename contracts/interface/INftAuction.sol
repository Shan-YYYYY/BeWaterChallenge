// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INftAuction {
    event ListingCreated(
        uint256 indexed listingId,
        address nftAddress,
        uint256 tokenId,
        uint256 createTime,
        address seller,
        uint256 price
    );

    event NftSold(
        uint256 indexed listingId,
        address nftAddress,
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    event ListingCanceled(
        uint256 indexed listingId,
        address nftAddress,
        uint256 tokenId,
        address seller
    );

    event Bid(
        uint256 indexed listingId,
        address nftAddress,
        uint256 tokenId,
        uint256 bidPrice,
        address bidder
    );

    event Unsold(
        uint256 indexed listingId,
        address nftAddress,
        uint256 tokenId,
        uint256 price
    );

    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price
    ) external;

    function bid(uint256 _listingId, uint256 _price) external;

    function cancelListing(uint256 _listingId) external;

    function getListing(
        uint256 _listingId
    ) external view returns (address, uint256, uint256, address, uint256);

    function endAuction(uint256 _listingId) external;

    function buyNFT(uint256 _listingId, uint _price) external;

    function unsold(uint256 _listingId) external;

    function getExpiredListingWithoutBid()
        external
        view
        returns (uint256[] memory);
}

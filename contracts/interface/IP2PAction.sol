// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IP2PAction{

    event createOrder(
        address indexed sender,
        uint256 price,
        uint256 loanTime,
        uint256 createTime,
        uint256 nftAmount
        );

    event varietyNft(
        address [] addr,
        uint256 [] Id,
        uint256 price,
        uint256 index
    );

    event setOffer(
        address indexed lender,
        uint256 expectPrice,
        uint256 offerCreateTime
        );


    //创建借钱需求 由borrow调用 上架NFT
    function createP2POrder(
        address sender,
        address[] memory addr,
        uint256[] memory Id,
        uint256 _price,
        uint256 _loanTime
    ) external;

    //make offer 由众多lender 报价
    function makeOffer(address lender,uint256 index, uint256 _price) external;

    //lender撤销offer
    function revokeOffer(address lender,uint256 index, uint256 offerId) external;

    //borrower撤回NFT
    function revokeOrder(address sender,uint256 index) external;

    //前端调用 获得NFT要插入的位置ID
    function getLastOneNftId(address addr,uint256 _price) external view returns(uint256);

    //borrow确认Offer
    function confirmOffer(address sender,uint256 index, uint256 offerIndex,uint256 lastOneId) external;

    // 前端调用 判断offer是否过期
    function judgeOfferTime(uint256 index,uint256 offerIndex) external view returns(bool);
    
    //offer过期后 lender需要手动提取代币
    function lenderFetch(address sender,uint256 index,uint256 offerIndex) external;

    //borrower正常还钱
    function borrow(address sender,uint256 index) external;

    //nft跌破安全阈值被迫还钱
    function forceBorrow(address sender,uint256 index) external;
    
    //超时未还钱后lender可随时将nft从本合约提走
    function lenderWithDraw(address sender,uint256 index) external;

    //设置还钱的利息
    function setAPR() external;

    //预言机调用 NFT跌破安全阈值 由预言机检测价格变化并调用
    function urgentDown(address nftaddr, uint256 _price) external;

    //预言机调用 NFT回价 由预言机检测价格变化并调用
    function urgentUp(address nftaddr, uint256 _price) external;

     //预言机调用 NFT跌破安全阈值后 borrower未在 48h内对NFT进行操作
    function timeOutWhenUrgent(address nftaddr) external;




}

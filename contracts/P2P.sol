// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interface/IP2PAction.sol";

contract P2P{

    IP2PAction public P2PAction;

    constructor(address _actionAddress){
        P2PAction = IP2PAction(_actionAddress);
    }

    //创建借钱需求 由borrow调用 上架NFT
    function createOrder(
        address[] memory addr,
        uint256[] memory Id,
        uint256 _price,
        uint256 _loanTime
    ) external {
        P2PAction.createP2POrder(msg.sender,addr,Id,_price,_loanTime);
    }

    //make offer 由众多lender 报价
    function makeOffer(uint256 inderx,uint256 _price) external{
        P2PAction.makeOffer(msg.sender,inderx,_price);
    }

    //lender撤销offer
    function revokeOffer(uint256 index, uint256 offerId) external{
        address sender = msg.sender;
        P2PAction.revokeOffer(sender,index,offerId);
    }

    //borrower撤回NFT
    function revokeOrder(uint256 index) external {
        address sender = msg.sender;
        P2PAction.revokeOrder(sender,index);
    }

    //前端调用 获得NFT要插入的位置ID
    function getLastOneNftId(address addr,uint256 _price) external view returns(uint256){
        return P2PAction.getLastOneNftId(addr,_price);
    }

    //borrow确认Offer
    function confirmOffer(uint256 index, uint256 offerIndex,uint256 lastOneId) external {
        address sender = msg.sender;
        P2PAction.confirmOffer(sender,index,offerIndex,lastOneId);
    }
    
    //offer过期后 lender需要手动提取代币
    function lenderFetch(uint256 index,uint256 offerIndex) external{
        address sender = msg.sender;
        P2PAction.lenderFetch(sender,index,offerIndex);
    }

    //borrower正常还钱
    function borrow(uint256 index) external{
        address sender = msg.sender;
        P2PAction.borrow(sender,index);
    }

    //nft跌破安全阈值被迫还钱
    function forceBorrow(uint256 index) external{
        address sender = msg.sender;
        P2PAction.forceBorrow(sender,index);
    }
    
    //超时未还钱后lender可随时将nft从本合约提走
    function lenderWithDraw(uint256 index) external{
        address sender = msg.sender;
        P2PAction.lenderWithDraw(sender,index);
    }


}
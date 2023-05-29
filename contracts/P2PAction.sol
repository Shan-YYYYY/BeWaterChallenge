// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./library/LinkedList.sol";
import "./interface/IP2PAction.sol";

contract P2PAction is IP2PAction, Ownable {
    using LinkedListLib for LinkedListLib.UintLinkedList;

    IERC20 public token;

    address private oracle;

    uint256 public APR;

    constructor(address _token) {
        token = IERC20(_token);
    }

    modifier onlyOracle() {
        require(msg.sender == oracle);
        _;
    }

    LinkedListLib.UintLinkedList Nodes;
    mapping(address => LinkedListLib.UintLinkedList) nftChain;
    mapping(address => mapping(uint256 => nftInformation)) nftChainMapping;
    mapping(address => mapping(uint256 => uint256)) orderIndex;
    mapping(uint256 => Order) orderList; //所有订单
    mapping(uint256 => Offer[]) offerList; //每个订单存在的offer

    // 订单计数器
    uint256 nftCounter;

    // 用于单个NFT清算
    struct nftInformation {
        address nftaddress;
        uint256 nftId;
        uint256 warnTime;
    }

    uint256[] varietyNftOrderIndexArray;

    enum States {
        created, //NFt已上架等待lender报价创建offer
        lended, //borrower已选择offer ptp借贷成功 等待到期还款
        borrowed, //borrower已经正常还钱
        warning, //nft跌破安全阈值 需要提前还款
        error1, //异常情况1 borrower取消上架已NFT 所有已报价offer均撤销
        error2, //异常情况2 borrower逾期不还钱 NFT已经转入lender
        error3, //异常情况3 NFT跌破安全阈值 borrowed提前还钱
        error4, //异常情况4 NFT跌破安全阈值 borrower选择不还钱 NFT已转入lender
        finished //本次借贷已结束
    }

    struct Order {
        uint256 orderIndex; // 订单编号
        uint256 blockNumber; // 区块号
        address borrower; // 申请借款的人
        uint256 price; // 申请借贷价格
        uint256 loanTime; // 借贷时间
        uint256 borrowTime; // 拨款时间
        address lender; // 借款人
        address[] tokenAddress; // NFT地址
        uint256[] tokenID; // NFTID
        uint256 coefficient; // 借贷率系数
        States state; //状态
    }

    struct Offer {
        uint256 orderIndex; // 订单编号
        address lender; // 出价人
        uint256 price; // 出价
        uint256 creatTime; // 创建时间
    }

    //获取地板价
    function getFloorPrice(
        address tokenAddress
    ) internal view returns (uint256) {
        //调用预言机合约
    }

    function _addNftToChain(
        address addr,
        uint256 Id,
        uint256 lastOneId
    ) internal {
        nftChain[addr].insertAfter(lastOneId, Id);
        nftChainMapping[addr][Id].nftaddress = addr;
        nftChainMapping[addr][Id].nftId = Id;
    }

    function _removeNftToChain(uint256 index) internal {
        address[] memory addr = getNftAddressByIndex(index);
        uint256[] memory Id = getTokenIdByIndex(index);
        require(addr.length == 1);
        nftChain[addr[0]].remove(Id[0]);
        delete nftChainMapping[addr[0]][Id[0]];
    }

    //计算借贷率系数
    function getCoefficient(
        address[] memory addr,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 sumFloor = 0;

        for (uint i; i < addr.length; i++) {
            sumFloor += getFloorPrice(addr[i]);
        }

        return (sumFloor / _price) * 10000;
    }

    //创建借钱需求 由borrow调用 上架NFT
    function createP2POrder(
        address sender,
        address[] memory addr,
        uint256[] memory id,
        uint256 _price,
        uint256 _loanTime
    ) public {
        require(addr.length == id.length);

        nftCounter++;
        uint coefficients = getCoefficient(addr, _price);

        Order memory order = Order({
            orderIndex: nftCounter,
            blockNumber: block.number,
            borrower: sender,
            price: _price,
            loanTime: _loanTime,
            borrowTime: 0,
            lender: address(0x0),
            state: States.created,
            tokenAddress: addr,
            tokenID: id,
            coefficient: coefficients
        });

        orderList[nftCounter] = order;
        _transfer(nftCounter, sender, address(this));
        Nodes.add(nftCounter);

        bool temp = _judgeIsMultiple(addr);

        if (temp) {
            for (uint i; i < addr.length; i++) {
                orderIndex[addr[i]][id[i]] = nftCounter;
            }
        } else {
            varietyNftOrderIndexArray.push(nftCounter);
        }

        orderList[nftCounter].state = States.created;

        //TODO event
        emit createOrder(
            sender,
            _price,
            _loanTime,
            block.timestamp,
            addr.length
        );
    }

    function _judgeIsMultiple(
        address[] memory addr
    ) internal pure returns (bool) {
        bool temp = true;

        for (uint i; i < addr.length - 1; i++) {
            if (addr[i] != addr[i + 1]) {
                temp = false;
            }
        }

        return temp;
    }

    //make offer 由众多lender 报价
    function makeOffer(address lender, uint256 index, uint256 _price) external {
        require(orderList[index].state == States.created);
        _erc20TransferFrom(lender, address(this), _price);

        Offer memory offer = Offer({
            orderIndex: index,
            lender: lender,
            price: _price,
            creatTime: block.timestamp
        });

        offerList[index].push(offer);

        emit setOffer(lender, _price, block.timestamp);
    }

    //lender撤销offer
    function revokeOffer(
        address lender,
        uint256 index,
        uint256 offerId
    ) external {
        require(lender == offerList[index][offerId].lender);

        _repealOffer(index, offerId);
    }

    //borrower撤回NFT
    function revokeOrder(address sender, uint256 index) external {
        require(sender == orderList[index].borrower);

        Nodes.remove(index);
        _removeNftToChain(index);
        _transfer(index, address(this), sender);

        uint256 length = offerList[index].length;

        for (uint i = 0; i < length; i++) {
            _repealOffer(index, i);
        }

        orderList[index].state = States.error1;
    }

    //前端调用 获得NFT要插入的位置ID
    function getLastOneNftId(
        address addr,
        uint256 _price
    ) public view returns (uint256) {
        uint256 current;
        LinkedListLib.UintNode memory tempList = nftChain[addr].getNode(0);
        current = tempList.next;
        while (_price < orderList[orderIndex[addr][current]].price) {
            current = nftChain[addr].getNode(current).next;
        }

        return nftChain[addr].getNode(current).prev;
    }

    //borrow确认Offer
    function confirmOffer(
        address sender,
        uint256 index,
        uint256 offerIndex,
        uint256 lastOneId
    ) external {
        require(offerList[index].length > 0);
        require(sender == orderList[index].borrower);
        uint256 _price = offerList[index][offerIndex].price;
        address _lender = offerList[index][offerIndex].lender;

        orderList[index].price = _price;
        orderList[index].lender = _lender;
        orderList[index].borrowTime = block.timestamp;
        _erc20TransferFrom(address(this), sender, _price);

        address[] memory addr = orderList[index].tokenAddress;
        uint256[] memory Id = orderList[index].tokenID;

        bool temp = _judgeIsMultiple(addr);
        if (temp) {
            for (uint i; i < addr.length; i++) {
                _addNftToChain(addr[i], Id[i], lastOneId);
            }
        } else {
            emit varietyNft(addr, Id, _price, index);
        }

        uint256 length = offerList[index].length;
        for (uint i = 0; i < length; i++) {
            if (i != offerIndex) {
                _repealOffer(index, i);
            }
        }

        orderList[index].state = States.lended;
    }

    uint256 public constant SECONDS_IN_WEEK = 604800;
    uint256 public constant SECONDS_IN_DAY = 86400;

    // 前端调用 判断offer是否过期
    function judgeOfferTime(
        uint256 index,
        uint256 offerIndex
    ) external view returns (bool) {
        uint256 offerTime = offerList[index][offerIndex].creatTime;
        if ((block.timestamp - offerTime) > SECONDS_IN_WEEK) {
            return true;
        } else {
            return false;
        }
    }

    //offer过期后 lender需要手动提取代币
    function lenderFetch(
        address sender,
        uint256 index,
        uint256 offerIndex
    ) external {
        require(sender == offerList[index][offerIndex].lender);
        uint256 offerTime = offerList[index][offerIndex].creatTime;

        if ((block.timestamp - offerTime) > SECONDS_IN_WEEK) {
            _repealOffer(index, offerIndex);
        }
    }

    // 删除offer
    function _repealOffer(uint256 index, uint256 offerIndex) internal {
        address _master = offerList[index][offerIndex].lender;
        uint256 _price = offerList[index][offerIndex].price;

        token.transfer(_master, _price);

        delete offerList[index][offerIndex];
    }

    function _erc20TransferFrom(
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        token.transferFrom(sender, receiver, amount);
    }

    function _transfer(
        uint256 index,
        address sender,
        address receiver
    ) internal {
        address[] memory addr = getNftAddressByIndex(index);
        uint256[] memory Id = getTokenIdByIndex(index);

        for (uint i; i < addr.length; i++) {
            address _nftAddress = addr[i];
            uint256 _tokenId = Id[i];
            _nftTransfer(_nftAddress, _tokenId, sender, receiver);
        }
    }

    //borrower正常还钱
    function borrow(address sender, uint256 index) external {
        require(
            (block.timestamp - orderList[index].borrowTime) <=
                orderList[index].loanTime
        );

        require(orderList[index].state == States.lended);

        _borrow(sender, index);
    }

    //nft跌破安全阈值被迫还钱
    function forceBorrow(address sender, uint256 index) external {
        require(orderList[index].state == States.warning);

        _borrow(sender, index);
        orderList[index].state = States.error3;
    }

    //还钱
    function _borrow(address sender, uint256 index) internal {
        require(sender == orderList[index].borrower);

        uint256 _price = orderList[index].price;
        uint256 _time = orderList[index].loanTime;
        uint256 price = _getBorrowPrice(_price, _time);
        address _lender = orderList[index].lender;

        _erc20TransferFrom(sender, _lender, price);

        orderList[index].state = States.borrowed;
        Nodes.remove(index);
        _removeNftToChain(index);
        _transfer(index, address(this), sender);
        orderList[index].state = States.borrowed;
        delete orderList[index];
    }

    //获取还钱的利息
    function _getBorrowPrice(
        uint256 _price,
        uint256 _time
    ) internal pure returns (uint256) {
        return _price;
    }

    //设置还钱的利息
    function setAPR() external onlyOwner {}

    //记录一系列NFT中价格变化角标
    mapping(address => uint256) priceChangeIndex;

    // NFT跌破安全阈值 由预言机检测价格变化并调用
    function urgentDown(address nftaddr, uint256 _price) external onlyOracle {
        uint256 index = priceChangeIndex[nftaddr];

        LinkedListLib.UintNode memory tempList = nftChain[nftaddr].getNode(
            index
        );

        uint256 tempId = tempList.current;

        while (orderList[orderIndex[nftaddr][tempId]].price > _price) {
            nftChainMapping[nftaddr][tempId].warnTime = block.timestamp;
            orderList[orderIndex[nftaddr][tempId]].state = States.warning;
            tempId = nftChain[nftaddr].getNode(tempId).next;
        }

        priceChangeIndex[nftaddr] = nftChain[nftaddr].getNode(index).prev;
    }

    // NFT回价  由预言机检测价格变化并调用
    function urgentUp(address nftaddr, uint256 _price) external onlyOracle {
        uint256 index = priceChangeIndex[nftaddr];

        LinkedListLib.UintNode memory tempList = nftChain[nftaddr].getNode(
            index
        );

        uint256 tempId = tempList.current;

        while (orderList[orderIndex[nftaddr][tempId]].price < _price) {
            nftChainMapping[nftaddr][tempId].warnTime = 0;
            orderList[orderIndex[nftaddr][tempId]].state = States.lended;
            tempId = nftChain[nftaddr].getNode(tempId).prev;
        }

        priceChangeIndex[nftaddr] = nftChain[nftaddr].getNode(index).next;
    }

    // NFT跌破安全阈值后 borrower未在 48h内对NFT进行操作
    function timeOutWhenUrgent(address nftaddr) external {
        uint256 tempId = priceChangeIndex[nftaddr];
        uint256 time = block.timestamp -
            nftChainMapping[nftaddr][tempId].warnTime;

        while (time > 172800 && time < 259200) {
            time = block.timestamp - nftChainMapping[nftaddr][tempId].warnTime;
            tempId = nftChain[nftaddr].getNode(tempId).prev;
            uint256 index = orderIndex[nftaddr][tempId];
            address lender = orderList[index].lender;
            _transfer(index, address(this), lender);
            orderList[index].state = States.error4;
        }
    }

    //超时未还钱后lender可随时将nft从本合约提走
    function lenderWithDraw(address sender, uint256 index) external {
        require(
            (block.timestamp - orderList[index].borrowTime) >
                orderList[index].loanTime
        );

        require(sender == orderList[index].lender);

        _transfer(index, address(this), sender);
        orderList[index].state = States.error2;
        delete orderList[index];
    }

    //通过下标获取该订单所有NFT地址
    function getNftAddressByIndex(
        uint256 index
    ) public view returns (address[] memory NftAddress) {
        NftAddress = orderList[index].tokenAddress;
    }

    //通过下标获取该订单所有代币ID
    function getTokenIdByIndex(
        uint256 index
    ) public view returns (uint256[] memory tokenId) {
        tokenId = orderList[index].tokenID;
    }

    //设置预言机合约地址
    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    //NFT转账
    function _nftTransfer(
        address _nftAddress,
        uint256 _tokenId,
        address _sender,
        address _recipient
    ) internal {
        IERC721 Nft = IERC721(_nftAddress);
        Nft.transferFrom(_sender, _recipient, _tokenId);
    }

    function liquidation(address sender, uint256 index) internal {
        address[] memory addr = getNftAddressByIndex(index);
        uint256[] memory Id = getTokenIdByIndex(index);

        for (uint i; i < addr.length; i++) {
            address _nftAddress = addr[i];
            uint256 _tokenId = Id[i];
            _nftTransfer(_nftAddress, _tokenId, address(this), sender);
        }
    }

    //获取目标节点后目标数量节点
    function getNodes(
        uint256 current,
        uint256 number
    ) external view returns (Order[] memory) {
        Order[] memory orders = new Order[](number);
        Order memory orderGet;
        LinkedListLib.UintNode memory nodeGet;

        for (uint i; i <= number; i++) {
            nodeGet = Nodes.getNode(current);
            orderGet = orderList[nodeGet.current];
            orders[i + 1] = orderGet;
            current = nodeGet.next;
        }

        return orders;
    }

    struct varietyNfts {
        address[] nftAddr;
        uint256[] nftId;
        uint256 _price;
    }

    //获取多种NFT数据
    function getAllVarietyNftOrder()
        external
        view
        returns (varietyNfts[] memory)
    {
        varietyNfts[] memory varietyNft = new varietyNfts[](
            varietyNftOrderIndexArray.length
        );
        for (uint i = 0; i < varietyNftOrderIndexArray.length; i++) {
            uint256 index = varietyNftOrderIndexArray[i];
            varietyNft[i] = varietyNfts({
                nftAddr: orderList[index].tokenAddress,
                nftId: orderList[index].tokenID,
                _price: orderList[index].price
            });
        }
        return varietyNft;
    }
}

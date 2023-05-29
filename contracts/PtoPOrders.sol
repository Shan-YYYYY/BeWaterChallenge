// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ProposalLinkedList.sol";
import  "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract PtoP{
    IERC20 public token;
    address private administrator;

    constructor(address _token,address _administrator){
        token = IERC20(_token);
        administrator = _administrator;
    }

    modifier onlyadministrator{
        require(msg.sender == administrator);
        _;
    }

    mapping(address => mapping(uint256 => Order)) orders;
    mapping(uint256 => NFT) nfts;
    uint length = 0;

    struct NFT{
        address nftAddress;     //NFT地址
        uint256 tokenId;        //tokenID
        NftType nftType;            // NFT类型
        uint256 amount;             // NFT代币数量 
    }

    enum NftType {              //记录NFT的类型
        ERC721,
        ERC1155,
        Others
    }

    enum States{
        created,            //借贷已创建
        lended,             //借款人已拨款
        borrowed,           //还钱人已还钱
        finished            //本次借贷已结束  
    }

    struct Order{
        uint256 blockNumber;        // 区块号         
        address borrower;           // 申请借款的人
        uint256 price;              // 申请借贷价格
        uint256 loanTime;           // 借贷时间
        uint256 borrowTime;         // 拨款时间
        address lender;             // 借款人
        NFT nft;                   // NFT信息
        States state;
    }

    //创建借钱需求
    function createP2POrder(address _nftAddress,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _price,
        uint256 _loanTime)public {
        NftType types = identifyNFT(_nftAddress);
        NFT memory nft = NFT(_nftAddress,_tokenId,types,_amount);
        Order memory order = Order({
                blockNumber: block.number,
                borrower: msg.sender,
                price:_price,
                loanTime:_loanTime,
                borrowTime: 0,
                lender:address(0x0),
                state:States.created,
                nft:nft
        });
        orders[_nftAddress][_tokenId] = order;
        nftTransfer(_nftAddress,_tokenId,msg.sender,address(this),_amount);
        nfts[length + 1] = (nft);
        length ++;

        //TODO event
    }

    //借钱者撤回NFT
    function revokeOrder(address _nftAddress,uint256 _tokenId,uint256 index) external{
        require(msg.sender == orders[_nftAddress][_tokenId].borrower);
        uint256 amount = orders[_nftAddress][_tokenId].nft.amount;
        nftTransfer(_nftAddress,_tokenId,address(this),msg.sender,amount);
        orders[_nftAddress][_tokenId].state = States.finished;
        nfts[index] = nfts[length];

    }

    //借钱
    function lend(address _nftAddress,uint256 _tokenId) external {
        require(orders[_nftAddress][_tokenId].state == States.created);
        token.transferFrom(
            orders[_nftAddress][_tokenId].lender,
            orders[_nftAddress][_tokenId].borrower,
            orders[_nftAddress][_tokenId].price
        );
        orders[_nftAddress][_tokenId].lender = msg.sender;
        orders[_nftAddress][_tokenId].borrowTime = block.timestamp;
        orders[_nftAddress][_tokenId].state = States.lended;


    }

    //还钱
    function borrow(address _nftAddress,uint256 _tokenId,uint256 index) external {
        require(
            (block.timestamp - 
            orders[_nftAddress][_tokenId].borrowTime) <= 
            orders[_nftAddress][_tokenId].loanTime   
        );
        require(msg.sender == orders[_nftAddress][_tokenId].borrower);
        uint256 price = getBorrowPrice(orders[_nftAddress][_tokenId].price);
        token.transferFrom(
            orders[_nftAddress][_tokenId].borrower,
            orders[_nftAddress][_tokenId].lender,
            price
        );
        orders[_nftAddress][_tokenId].state = States.borrowed;
        nfts[index] = nfts[length];
        length --;
        uint256 amount = orders[_nftAddress][_tokenId].nft.amount;
        nftTransfer(_nftAddress,_tokenId,address(this),msg.sender,amount);
    
    }

    //获取还钱的利息
    function getBorrowPrice(uint256 price) internal pure returns(uint256) {
        return price;
    }

    //设置还钱的利息
    function setBorrowPricePercentage() external onlyadministrator {

    }
    
    //超时后lender可随时将nft从本合约提走
    function timeOut(address _nftAddress,uint256 _tokenId) external {
        require(
            (block.timestamp - 
            orders[_nftAddress][_tokenId].borrowTime) > 
            orders[_nftAddress][_tokenId].loanTime   
        );
        require(msg.sender == orders[_nftAddress][_tokenId].lender);
        uint256 amount = orders[_nftAddress][_tokenId].nft.amount;
        nftTransfer(_nftAddress,_tokenId,address(this),msg.sender,amount);
        orders[_nftAddress][_tokenId].state = States.finished;

    }

    //通过NFT地址和代币ID获取下标
    function getIndexByNftAddressAndId(address _nftAddress,uint256 _tokenId) external view returns(uint256 index){
        NFT memory nft;
        NFT memory compareNft = orders[_nftAddress][_tokenId].nft;
        uint i;
        for(i = 0; i <= length; i++){
            nft = nfts[i];
            if(nft.nftAddress == compareNft.nftAddress && nft.tokenId == compareNft.tokenId){
                return i;
            }
        }
    }

    //通过下标获取NFT地址
    function getNftAddressByIndex(uint256 index) public view returns(address NftAddress){
        NftAddress = nfts[index].nftAddress;
    }

    //通过下标获取代币ID
    function getTokenIdByIndex(uint256 index) public view returns(uint256 tokenId){
        tokenId = nfts[index].tokenId;
    }

    function setAdministrator(address _address)external onlyadministrator returns(address){
        return administrator = _address;
    }

    //NFT转账
    function nftTransfer(address _nftAddress,
        uint256 _tokenId,
        address _sender,
        address _recipient,
        uint256 amount
    ) internal {
        if(orders[_nftAddress][_tokenId].nft.nftType == NftType.ERC721){
            IERC721 Nft = IERC721(_nftAddress);
            Nft.transferFrom(_sender, _recipient, _tokenId);
        }else if(orders[_nftAddress][_tokenId].nft.nftType == NftType.ERC1155){
            IERC1155 Nft = IERC1155(_nftAddress);
            Nft.safeTransferFrom(_sender, _recipient, _tokenId,amount,"");
        }else{
            revert();
        }
    }

    //查询一个NTF是721还是1155
    function identifyNFT(address nftAddress) public view returns (NftType) {
        ERC165 nftInterface = ERC165(nftAddress);
        // NftType storage nftType;
        if (nftInterface.supportsInterface(type(IERC721).interfaceId)) {
            return NftType.ERC721;
        } else if (nftInterface.supportsInterface(type(IERC1155).interfaceId)) {
            return NftType.ERC1155;
        } else {
            return NftType.Others;
        }
    }

    //获取目标节点后目标数量节点
    function getNodes(uint256 current,uint256 number)external view returns(Order[] memory){
        Order[] memory orderList = new Order[](number);
        Order memory orderGet;
        for(uint i ;i <= number ;i++){
            address _address = nfts[current].nftAddress;
            uint256 _tokenId = nfts[current].tokenId;
            orderGet = orders[_address][_tokenId];
            orderList[i + 1] = orderGet;
            current++;
        }
        return orderList;
    }
}
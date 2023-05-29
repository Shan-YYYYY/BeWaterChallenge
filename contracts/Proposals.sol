// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ProposalLinkedList.sol";
import  "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";


contract Proposals{

    bytes32 public ramdomNumber =
        keccak256(abi.encodePacked(block.number, block.timestamp));
    bytes4 constant ERC721_INTERFACE_ID = 0x80ac58cd;
    IERC20 public token;
    ProposalLinkedList public proposalLinkedList;
    address public signer=0x41c2481B5acd58De9336b56A881b5D914f517064;
    uint256 public voteNumber = 100;
    address public VicDAO ;
    address private administrator;

    constructor(address _token,address _vicDAO,address _administrator){
        token = IERC20(_token);
        VicDAO = _vicDAO;
        administrator = _administrator;
        proposalLinkedList = new ProposalLinkedList(address(this));
    }

    mapping(address => mapping(uint256 => uint)) public proposalTable;
    mapping(uint => mapping(address => bool)) isVoted;
    Proposal[] public proposals;


    modifier onlyadministrator{
        require(msg.sender == administrator);
        _;
    }


    enum ProposalStatus{
        P2D_INIT,   //P2D 发起提案
            // 提案被拒绝
            P2D_FAIL_INTO_P2P,  // P2D 提案被拒绝 转入P2P
                P2D_P2P_CANCEL,     // P2D转入P2P后被拒绝
                P2D_P2P_WAITING_REPAY, // P2D转入到P2P 等待还钱 
            // 提案被通过    
            P2D_WAITING_REPAY,  // P2D 提案通过 等待还款
                P2D_FINISH,  //正常还款
        P2P_INIT,   // P2P发起提案
            P2P_CANCEL,     //P2P 取消
            P2P_WAITING_REPAY,  //P2P等待还钱
                P2P_FINISH
    }

    struct Proposal {
        uint256 blockNumber;        // 区块号
        address nftAddress;         // NFT地址  
        uint256 tokenId;            // TOKEN ID 
        address borrower;           // 申请借款的人
        uint256 createTime;         // 发起提案时间
        uint256 price;              // 申请借贷价格
        uint256 loanTime;           // 借贷时间
        ProposalStatus status;      // 提案状态
        address lender;             // 借的人（仅针对于p2p)
        bytes32 currRandomNumber;       // 随机数  (仅对于P2D 选择投票人员所使用)
        uint256 borrowTime;         // 拨款的时间  (只有当 提案通过了才成立)
        address[] agreers;
        address[]   rejectors;
    }

    event PassP2pProposal(
        uint256 indexed proposalId,
        address nftAddress,
        uint256 tokenId,
        uint256 blockNumber
    );
    event SetProposal(
        uint256 indexed proposalId,
        address indexed owner,
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 blockNumber,
        bytes32 ramdomNumber
    );
    event RevokeProposal(
        uint256 indexed proposalId,
        address nftAddress,
        uint256 tokenId,
        uint256 blockNumber
    );
    event PassProposal(
        uint256 indexed proposalId,
        address nftAddress,
        uint256 tokenId,
        uint256 blockNumber,
        address[] agreeers
    );
    event FailedProposal(
        uint256 indexed proposalId,
        address nftAddress,
        uint256 tokenId,
        uint256 blockNumber,
        address[] rejectors
    );

     function createP2DProposal( address _nftAddress,
        uint256 _tokenId,
        uint256 _price,
        bytes32 _newRandowNumber,
        uint256 _loanTime) public {
        IERC721 Nft = IERC721(_nftAddress);
        Nft.transferFrom(msg.sender, address(this), _tokenId);
        ramdomNumber = keccak256(abi.encode(ramdomNumber, _newRandowNumber));
        uint proposalsLen = proposals.length;
        address[] memory agreeors;
        address[] memory rejectors;
        Proposal memory proposal=Proposal({
                blockNumber: block.number,
                nftAddress: _nftAddress,
                tokenId: _tokenId,
                borrower: msg.sender,
                createTime:block.timestamp,
                price:_price,
                loanTime:_loanTime,
                status:ProposalStatus.P2D_INIT,
                currRandomNumber:ramdomNumber,
                borrowTime:0,
                lender:address(0x0),
                agreers:agreeors,
                rejectors:rejectors
        });
        proposals.push(proposal);
        proposalTable[_nftAddress][_tokenId] = proposalsLen;
        proposalLinkedList.increate(proposalsLen,proposalsLen-1);
         //TODO event
    }

    function createP2PProposal(address _nftAddress,
        uint256 _tokenId,
        uint256 _price,
        uint256 _loanTime)public {
        IERC721 Nft = IERC721(_nftAddress);
        Nft.transferFrom(msg.sender, address(this), _tokenId);
        uint proposalsLen = proposals.length;
        address[] memory agreeors;
        address[] memory rejectors;
        Proposal memory proposal=Proposal({
                blockNumber: block.number,
                nftAddress: _nftAddress,
                tokenId: _tokenId,
                borrower: msg.sender,
                createTime:block.timestamp,
                price:_price,
                loanTime:_loanTime,
                status:ProposalStatus.P2P_INIT,
                currRandomNumber:ramdomNumber,
                borrowTime:0,
                lender:address(0x0),
                agreers:agreeors,
                rejectors:rejectors
        });
        proposals.push(proposal);
        proposalTable[_nftAddress][_tokenId] = proposalsLen;
        proposalLinkedList.increate(proposalsLen,proposalsLen-1);
         //TODO event
    }

    function revokeP2PProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        ProposalStatus status= proposal.status;
        require(status == ProposalStatus.P2P_INIT);
        proposalLinkedList.remove(_proposalId);
        IERC721(proposal.nftAddress).transferFrom(address(this), proposal.borrower, proposal.tokenId);
        proposal.status=ProposalStatus.P2P_CANCEL;
         //TODO event
    }

    function revokeP2DProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        ProposalStatus status= proposal.status;
        require(status == ProposalStatus.P2D_FAIL_INTO_P2P || (status==ProposalStatus.P2D_INIT && proposal.createTime+2 days>=block.timestamp ));
        proposalLinkedList.remove(_proposalId);
        IERC721(proposal.nftAddress).transferFrom(address(this), proposal.borrower, proposal.tokenId);
        proposal.status=ProposalStatus.P2D_P2P_CANCEL;
         //TODO event
    }

    function vote(
        uint256 _proposalId,
        bool _agreement,
        bytes calldata _sign
    ) external {

        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status==ProposalStatus.P2D_INIT && proposal.createTime+2 days<block.timestamp,"is not PtD");
        address user=msg.sender;
        bytes32 Hash=calculateHash(user,_proposalId,_agreement);
        require(SignatureChecker.isValidSignatureNow(signer,Hash,_sign));
        require(isVoted[_proposalId][user] == false, "already voted");
        isVoted[_proposalId][user] = true;
        _agreement
            ? proposal.agreers.push(user)
            : proposal.rejectors.push(user);
        // 交给Event 去做  //TODO event
        if(proposal.rejectors.length > voteNumber/2){
            proposal.status = ProposalStatus.P2D_FAIL_INTO_P2P;
        }else if (proposal.agreers.length > voteNumber/2) {
            proposalLinkedList.remove(_proposalId);
            token.transferFrom(VicDAO,proposal.borrower,proposal.price);
            proposal.status = ProposalStatus.P2P_WAITING_REPAY;
            // TODO event 
        }
    }

    function payAmount(uint256 amount,uint256 time)public pure returns (uint256){
        return amount*(100+lendingRate(time));
    }

    function lendingRate(uint256 time) public pure returns (uint256){
        return 0;
    }

   function calculateHash(address _address, uint256 _value, bool _flag) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_address,_value,_flag));
    }

    function payByP2D(uint256 _propsalId)public{
        Proposal storage proposal=proposals[_propsalId];
        require(proposal.borrower==msg.sender);
        require(proposal.status==ProposalStatus.P2D_WAITING_REPAY);
        _pay(proposal,VicDAO);
        proposal.status=ProposalStatus.P2D_FINISH;
         //TODO event
    }

    function payByP2P(uint256 _propsalId)public{
        Proposal storage proposal=proposals[_propsalId];
        require(proposal.borrower==msg.sender);
        require(proposal.status==ProposalStatus.P2P_WAITING_REPAY);
        _pay(proposal,proposal.lender);
        proposal.status=ProposalStatus.P2P_FINISH;
        //TODO event
    }

   function _pay(Proposal storage proposal,address toAddress)private{
        uint256 needPayAmount=payAmount(proposal.price,proposal.loanTime);
        token.transferFrom(msg.sender, toAddress,needPayAmount);
        //TODO LinkedList operate
        IERC721(proposal.nftAddress).transferFrom(address(this),msg.sender,proposal.tokenId);
   }
   
    function P2pBuy(
        uint256 _proposalId
    )external {
        Proposal storage proposal=proposals[_proposalId];
        ProposalStatus status=proposal.status;
        require(status == ProposalStatus.P2D_FAIL_INTO_P2P || (status==ProposalStatus.P2D_INIT && proposal.createTime+2 days>=block.timestamp));

        token.transferFrom(msg.sender,proposal.borrower,proposal.price);
        proposal.status = ProposalStatus.P2P_WAITING_REPAY;
        proposal.lender = msg.sender;
        proposal.borrowTime=block.timestamp;
        // delete proposalTable[proposal.nftAddress][proposal.tokenId];
        proposalLinkedList.remove(_proposalId);
        emit PassP2pProposal(_proposalId,proposal.nftAddress,proposal.tokenId,block.number);
        // TODO event
    }

     function setVoteNumber(uint256 _voteNumber)external onlyadministrator{
            voteNumber  = _voteNumber;
    }

    function setAdministrator(address _address)external onlyadministrator returns(address){
        return administrator = _address;
    }
   
}

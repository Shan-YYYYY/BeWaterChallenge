// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Proposals.sol";
import "./BalanceLinkedList.sol";

contract VicDAO {

    uint256 public YEAR_TIMESTAMP = 31536000000;
    uint256 public PLEDGE_MINI_LIMIT = 0;
    uint256 public BURN_PROPORTION = 3;
   
    bytes4 constant ERC721_INTERFACE_ID = 0x80ac58cd;
    // 投票资格下线 常量定义
    // uint256 public  VOTE_QUALIFICATION_LOWER_LIMIT=20000;
    address private administrator;//管理员
    BalanceLinkedList public balanceLinkedList;
    IERC20 public token;
    Proposals public proposalsAddress;
    
    constructor(address _token,address _administrator) {
        token = IERC20(_token);
        administrator = _administrator;
        balanceLinkedList= new BalanceLinkedList(address(this));
        proposalsAddress = new Proposals(_token,address(this),_administrator);
    }
    

    mapping(address => uint256) public vevicBalance;
    mapping(address => uint256) public vevicUpdateTime;
    mapping(address => ReceiptInfo[]) public receiptTable;
    
    struct ReceiptInfo {
        uint256 startTime;
        uint256 unlockTime;
        uint256 vicCount;
        bool proce;
    }
    
    function balanceOf(address user) public view returns (uint256) {
        uint256 balance = vevicBalance[user];
        if (balance == 0) {
            return 0;
        }
        uint256 decrease = (block.timestamp - vevicUpdateTime[user]) *
            BURN_PROPORTION;
        if (balance < decrease) {
            return 0;
        }
        return balance - decrease;
    }

    function pledgeProfit(
        uint256 vic,
        uint256 time
    ) public view returns (uint256) {
        return (vic * (time / YEAR_TIMESTAMP) * 25) / 100;
    }

    function pledge(uint256 vicCount, uint256 time, address front) public {
        require(vicCount > PLEDGE_MINI_LIMIT);
        require(
            time > 0 && time <= 4 * YEAR_TIMESTAMP && time % YEAR_TIMESTAMP == 0
        );
        token.transferFrom(msg.sender, address(this), vicCount);
        uint256 _pledgeProfit = pledgeProfit(vicCount, time);
        increase(msg.sender, _pledgeProfit, front);

        uint256 nowTime = block.timestamp;
        ReceiptInfo memory receipt = ReceiptInfo({
            startTime: nowTime,
            unlockTime: nowTime + time,
            vicCount: vicCount,
            proce: true
        });

        receiptTable[msg.sender].push(receipt);
    }

    // 将增加单独抽出 以便将增加至 member 的操作独立化
    function increase(address user, uint256 count, address front) private {
        uint256 currBalance = balanceOf(user);
        currBalance += count;
        vevicBalance[user] = currBalance;
        vevicUpdateTime[user] = block.timestamp;
        balanceLinkedList.update(user, currBalance, front);
    }

    function unlock(uint256 index) public {
        ReceiptInfo storage receipt = receiptTable[msg.sender][index];
        require(receipt.proce && block.timestamp >= receipt.unlockTime);
        token.transfer(msg.sender, receipt.vicCount);
        receipt.proce = false;
    }

    // function forceUnlock() public {
    //     ReceiptInfo[] storage receipts = receiptTable[msg.sender];
    //     for (uint256 i = 0; i < receipts.length; i++) {
    //         if (receipts[i].proce) {
    //             token.transfer(msg.sender, receipts[i].vicCount);
    //             receipts[i].proce = false;
    //         }
    //     }
    //     vevicBalance[msg.sender] = 0;
    //     balanceLinkedList.remove(msg.sender);
    // }


}
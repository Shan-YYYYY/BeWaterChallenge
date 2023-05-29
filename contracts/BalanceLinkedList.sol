// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./interface/balanceReader.sol";

contract BalanceLinkedList {
    BalanceReader balanceReader;


    constructor(address _balanceReader){
        balanceReader = BalanceReader(_balanceReader); 
    }

    struct Node{
        address current;
        address front;
        address next;
    }
    
 
    address public ZERO_ADDRESS = address(0x0);

    uint256 public length = 0;
    

    modifier onlyBalanceReader{
        require (msg.sender == address(balanceReader));
        _;
    }    

    mapping(address=>Node) public nodeTable;

    //增加节点
    function increate(address user,uint256 account, address front) onlyBalanceReader external {
        require(nodeTable[user].current==ZERO_ADDRESS); 
        _increate(user,account,front);
        length++;
    }

    function _increate(address user,uint256 account, address front)private{
        Node storage frontNode=nodeTable[front];

        uint256 frontBalance = balanceReader.balanceOf(frontNode.front);
        uint256 nextBalance = balanceReader.balanceOf(frontNode.next);

        require(front==ZERO_ADDRESS || nodeTable[front].current!=ZERO_ADDRESS); 
        require((frontNode.front==ZERO_ADDRESS || frontBalance >= account) && nextBalance <= account);

        address preNext=nodeTable[front].next;
        nodeTable[front].next=user;
        nodeTable[user].next=preNext;
        nodeTable[preNext].front=user;
        nodeTable[user].current=user;
    }

    //删除节点
    function remove(address user) onlyBalanceReader external {
        require(user != ZERO_ADDRESS);
        if(nodeTable[user].current != ZERO_ADDRESS){
            _remove(user);
            nodeTable[user].current=ZERO_ADDRESS;
            length--;
        }
    }

    function _remove(address user)private{
        nodeTable[nodeTable[user].front].next=nodeTable[user].next;
        nodeTable[nodeTable[user].next].front=nodeTable[user].front;
    }

    function update(address user,uint256 account, address front) onlyBalanceReader external {
        if(nodeTable[user].current != ZERO_ADDRESS){
            _remove(user);
        }else{
            length++;
        }
        _increate(user, account, front);
    }

    function getFront(address user) view public returns(address){
        require(user != ZERO_ADDRESS);
        require(nodeTable[user].current != ZERO_ADDRESS); 

        return nodeTable[user].front;
    }

    function getNext(address user) view public returns(address){
        require(user != ZERO_ADDRESS);
        require(nodeTable[user].current != ZERO_ADDRESS); 
        require(nodeTable[user].next != ZERO_ADDRESS); 

        return nodeTable[user].next;
    } 


     function getNodes(
        uint256[] calldata list
    ) public  view returns (address[] memory) {
        address[] memory selectedNode = new address[](list.length);
        uint256 index = 0;
        Node memory currentNode = nodeTable[address(0)];
        for (uint256 i = 0; i < list.length; i++) {
            while (index != list[i]) {
                currentNode = nodeTable[currentNode.next];
                index++;
            }
            selectedNode[i] = currentNode.current;
        }
        return selectedNode;
    }

    function getNewNodeFront(uint256 userAccount) view public returns(address front){
        require(userAccount > 0);
        address temp = nodeTable[ZERO_ADDRESS].next;
        while(balanceReader.balanceOf(temp) > userAccount){
            temp = nodeTable[temp].next;
        }
        return temp;
    }

}
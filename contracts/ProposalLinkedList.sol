// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


contract ProposalLinkedList {
    address owner;


    constructor(address _owner){
        owner = _owner;
    }

    struct Node{
        uint256 current;
        uint256 front;
        uint256 next;
    }

 
    uint256 public ZERO = 0;
    
    uint256 public length = 0;

    modifier onlyOwner{
        require (msg.sender == owner);
        _;
    }

    mapping(uint256=>Node) public nodeTable;
    //增加节点
    function increate(uint256 current, uint256 front) onlyOwner external {
        uint256 preNext=nodeTable[front].next;
        nodeTable[front].next=current;
        nodeTable[current].next=preNext;
        nodeTable[preNext].front=current;
        nodeTable[current].current=current;

        length++;
    }

    function remove(uint256 index) onlyOwner external{
        nodeTable[nodeTable[index].front].next=nodeTable[index].next;
        nodeTable[nodeTable[index].next].front=nodeTable[index].front;

        length--;
    }

    function setNodeToFirst(uint256 current) external onlyOwner{
        Node memory _current = nodeTable[current];
        nodeTable[current].next = nodeTable[ZERO].next;
        nodeTable[current].front = ZERO;
        nodeTable[nodeTable[ZERO].next].front = current;
        nodeTable[ZERO].next = current;
        nodeTable[_current.next].front = _current.front;
        nodeTable[_current.front].next = _current.next;
    }




}
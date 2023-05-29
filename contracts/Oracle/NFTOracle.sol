// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Price is Ownable{

    
    struct NFTData {
        uint256 roundId;
        uint256 price;
        uint256 timestamp;
    }  
    struct nftPriceFeed {
        bool registered;
        NFTData[] nftData;
    }
    
     uint256 private constant DECIMAL_PRECISION = 10**18;
    //   最大价格偏差，以18位精度表示，为20%。
    uint256 public maxPriceDeviation; // 20%,18-digit precision.
    
    //   每次更新价格的时间间隔为30分钟。
    uint256 public timeIntervalWithPrice; // 30 minutes
   
    //20000000000000000000
    //   历史价格的取值范围
    uint256 public minRoudId = 2;

    mapping(address => nftPriceFeed)  getNft;
    address[] public nftAdd;
    // mapping(address => uint256) public _index;
   
    event price(address indexed _nft,string name,uint256 updateTime,uint256 _price);

//TWAP的间隔时间
    uint256 public twapInterval;
    //   一个映射，将NFT合约地址映射到对应的TWAP价格。
    mapping(address => uint256)public twapPriceMap;

    function initialize(
       // address _admin,
        uint256 _maxPriceDeviation,
        uint256 _timeIntervalWithPrice,
        uint256 _twapInterval
    )public onlyOwner{
        maxPriceDeviation = _maxPriceDeviation;
        timeIntervalWithPrice = _timeIntervalWithPrice;
        twapInterval = _twapInterval;
    }

//添加多个

    function addNfts(address[] calldata _nftAdds)external onlyOwner{
        for(uint256 i = 0 ; i < _nftAdds.length ; i++){
            _addNft(_nftAdds[i]);
        }
    }

//添加一个
    function addNft(address _nftAddress) external onlyOwner{
        _addNft(_nftAddress);
    }

    function _addNft(address _nftAddress)internal { 
        requireExisted(_nftAddress, false);
        getNft[_nftAddress].registered = true;
        nftAdd.push(_nftAddress);
    }


    function isExisted(address _nftContract) private view returns (bool) {
        return getNft[_nftContract].registered;
  }

    function requireExisted(address _nftAddress,bool _data)private view {
        if(_data){
            require(isExisted(_nftAddress),"NFT not existed");
        }else{
            require(!isExisted(_nftAddress),"NFT is  existed");
        }
    }

    function remove(address _nftAddress) external onlyOwner{
        requireExisted(_nftAddress, true);
        delete getNft[_nftAddress];

        uint256 length = nftAdd.length;
        for(uint256 i = 0; i < length; i++){
            if (nftAdd[i] == _nftAddress) {
                nftAdd[i] = nftAdd[length - 1];
                nftAdd.pop();
            break;
      }
        }
    }
//返回单个NFT的数据数量
    function getPriceFeedLength(address _nftContract) public view returns (uint256 length) {
        return getNft[_nftContract].nftData.length;
  }
    function getPreviousPrice(address _nftContract, uint256 _numOfRoundBack) public view  returns (uint256) {
        require(isExisted(_nftContract), "NFTOracle: key not existed");

        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0 && _numOfRoundBack < len, "NFTOracle: Not enough history");
        return getNft[_nftContract].nftData[len - _numOfRoundBack - 1].price;
    }
    // 获取某个 NFT 资产历史价格记录中的第 n 个价格数据的时间戳，需要传入 _numOfRoundBack 参数表示要获取的历史价格数据在列表中的位置。
    function getPreviousTimestamp(address _nftContract, uint256 _numOfRoundBack) public view  returns (uint256) {
        require(isExisted(_nftContract), "NFTOracle: key not existed");

        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0 && _numOfRoundBack < len, "NFTOracle: Not enough history");
        return getNft[_nftContract].nftData[len - _numOfRoundBack - 1].timestamp;
    }

  function checkValidityOfPrice(
    address _nftContract,
    uint256 _price,
    uint256 _timestamp
  )private view returns(bool){
    uint256 len = getPriceFeedLength(_nftContract);

    if (len > 0) {
      uint256 price = getNft[_nftContract].nftData[len - 1].price;
      if (_price == price) {
        return true;
      }
      uint256 timestamp = getNft[_nftContract].nftData[len - 1].timestamp;
      uint256 percentDeviation;
      if (_price > price) {
        percentDeviation = ((_price - price) * DECIMAL_PRECISION) / price;
      } else {
        percentDeviation = ((price - _price) * DECIMAL_PRECISION) / price;
      }
      uint256 timeDeviation = _timestamp - timestamp;
      if (percentDeviation > maxPriceDeviation) {
        return false;
      } else if (timeDeviation < timeIntervalWithPrice) {
        return false;
      }
    }
    return true;
  }
//获取NFT最新的时间戳
    function getLatestTimestamp(address _nftContract) public view  returns (uint256) {
        require(isExisted(_nftContract), "NFTOracle: key not existed");
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return getNft[_nftContract].nftData[len - 1].timestamp;
  }


    function calculateTwapPrice(address _nftContract) public view returns (uint256) {
    require(isExisted(_nftContract), "NFTOracle: key not existed");
    require(twapInterval != 0, "NFTOracle: interval can't be 0");

    uint256 len = getPriceFeedLength(_nftContract);
    require(len > 0, "NFTOracle: Not enough history");
    uint256 round = len - 1;
    NFTData memory priceRecord = getNft[_nftContract].nftData[round];
    uint256 latestTimestamp = priceRecord.timestamp;
    uint256 baseTimestamp = _blockTimestamp() - twapInterval;
    uint256 totalPrice;

    if (latestTimestamp < baseTimestamp || round == 0) {
      return priceRecord.price;
    }
    bool result = IsminRoudId(_nftContract);
    if(result == true){
        for(uint256 i = 0;i <= round; i++){
            priceRecord.price = getNft[_nftContract].nftData[i].price;
            totalPrice = totalPrice + priceRecord.price;
           }
           return totalPrice / len;
        }else{
            for(uint256 i = len - minRoudId;i <= round; i++){
            priceRecord.price = getNft[_nftContract].nftData[i].price;
            totalPrice = totalPrice + priceRecord.price;
           }
           return totalPrice / minRoudId;
        }
    }

  function IsminRoudId(address _nftContract)internal view returns(bool){
    uint256 len = getPriceFeedLength(_nftContract);
    if(len > minRoudId){
        return false;
    }
    return true;
  }


        // 用于设置某个 NFT 资产的价格数据。只有管理员可以调用该函数，
    function setAssetData(address _nftContract, uint256 _price) external  onlyOwner {
        uint256 _timestamp = _blockTimestamp();
        _setAssetData(_nftContract, _price, _timestamp);
    }


    // 批量设置多个 NFT 资产的价格数据。只有管理员可以调用该函数，需要传入 _nftContracts 和 _prices 两个数组参数，并且两个数组的长度必须相等。
    function setMultipleAssetsData(address[] calldata _nftContracts, uint256[] calldata _prices)
        external 
       onlyOwner
    {
        require(_nftContracts.length == _prices.length, "NFTOracle: data length not match");
        uint256 _timestamp = _blockTimestamp();
        for (uint256 i = 0; i < _nftContracts.length; i++) {
            _setAssetData(_nftContracts[i], _prices[i], _timestamp);
        }
    }


// 内部函数，用于在设置单个 NFT 资产价格数据时进行调用。该函数会检查数据的有效性，并将价格数据添加到对应的价格映射表中
    function _setAssetData(
        address _nftContract,
        uint256 _price,
        uint256 _timestamp
    ) internal {
        requireExisted(_nftContract, true);
        require(_timestamp > getLatestTimestamp(_nftContract), "NFTOracle: incorrect timestamp");
        require(_price > 0, "NFTOracle: price can not be 0");
        bool dataValidity = checkValidityOfPrice(_nftContract, _price, _timestamp);
        require(dataValidity, "NFTOracle: invalid price data");
        uint256 len = getPriceFeedLength(_nftContract);
        NFTData memory data = NFTData({price: _price, timestamp: _timestamp, roundId: len});
        getNft[_nftContract].nftData.push(data);

        uint256 twapPrice = calculateTwapPrice(_nftContract);
        twapPriceMap[_nftContract] = twapPrice;

       
    }
    // 获取某个 NFT 资产的当前价格。该函数会首先检查该资产是否存在，并且是否有任何价格数据。如果已经计算了 TWAP 价格，则返回 TWAP 价格，否则返回最近一次价格数据的价格。
    function getAssetPrice(address _nftContract) external view  returns (uint256) {
        require(isExisted(_nftContract), "NFTOracle: key not existed");
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: no price data");
        uint256 twapPrice = twapPriceMap[_nftContract];
        if (twapPrice == 0) {
        return getNft[_nftContract].nftData[len - 1].price;
        } else {
        return twapPrice;
        }
    }

    function setTwapInterval(uint256 _twapInterval) external  onlyOwner {
        twapInterval = _twapInterval;
  } 
    function _blockTimestamp()public view returns(uint256) {
        return block.timestamp;
    }
//设置TWAP计算的间隔时间
    function settwapInterval(uint256 _twapInterval)external onlyOwner{
        twapInterval = _twapInterval;
    }
}
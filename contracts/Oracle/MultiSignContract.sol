// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract MultiSignContract {
    // 每个round需要的签名数
    uint256 public requiredConfirmations;
    // 签名者
    address[] signers;
    uint256 public currentRound;
    address public admin;
    // 价格预言机合约的地址
    address public priceOracleAddress;
    mapping(address => bool) public isSigner;
    mapping(address => uint) signerToIndex;
    mapping(uint256 => ConfirmInfo) public confirmInfos;
    // 记录每个roundId的每个signer是否已经确认
    mapping(uint256 => mapping(address => bool)) isConfirmed;

    struct ConfirmInfo {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 numConfirmations;
        bool executed;
    }
    event InitiateAnUpdatePrice(uint256 indexed roundId, bytes data);
    event Confirmation(address indexed sender, uint256 indexed roundId);
    event Confirmed(uint256 indexed roundId);
    event updateSuccess(uint256 indexed roundId);
    event updateFailed(uint256 indexed roundId);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier onlySigner(address signer) {
        require(isSigner[signer], "Not signer");
        _;
    }

    modifier confirmInfoExists(uint256 roundId) {
        require(
            confirmInfos[roundId].startTimestamp != 0,
            "confirmInfo does not exist"
        );
        _;
    }

    modifier notExecuted(uint256 roundId) {
        require(
            !confirmInfos[roundId].executed,
            "confirmInfo already executed"
        );
        _;
    }

    modifier confirmed(uint256 roundId) {
        require(isConfirmed[roundId][msg.sender], "Transaction not confirmed");
        _;
    }

    constructor(
        address[] memory _signers,
        uint256 _requiredConfirmations,
        address _admin,
        address _priceOracleAddress
    ) {
        require(_signers.length > 0, "Invalid number of signers");
        require(
            _requiredConfirmations > 0 &&
                _requiredConfirmations <= _signers.length,
            "Invalid number of required confirmations"
        );

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0), "Invalid signer");
            require(!isSigner[signer], "Duplicate signer");
            signerToIndex[signer] = i;
            isSigner[signer] = true;
            signers.push(signer);
        }

        requiredConfirmations = _requiredConfirmations;
        admin = _admin;
        priceOracleAddress = _priceOracleAddress;
    }

    // 初始化一个更新价格的请求
    function initiateAnUpdatePrice(
        bytes memory _data
    ) public onlyAdmin returns (bool) {
        uint256 roundId = ++currentRound;
        require(
            confirmInfos[roundId].startTimestamp == 0,
            "confirmInfo already exists"
        );
        confirmInfos[roundId] = ConfirmInfo({
            startTimestamp: block.timestamp,
            endTimestamp: 0,
            numConfirmations: 0,
            executed: false
        });
        emit InitiateAnUpdatePrice(roundId, _data);
        return true;
    }

    // 签名者确认某次更新价格的请求
    function signerConfirms(
        uint256 _roundId
    )
        public
        onlySigner(msg.sender)
        confirmInfoExists(_roundId)
        notExecuted(_roundId)
    {
        ConfirmInfo storage confirmInfo = confirmInfos[_roundId];
        require(!isConfirmed[_roundId][msg.sender], "Already confirmed");
        isConfirmed[_roundId][msg.sender] = true;
        confirmInfo.numConfirmations++;
        emit Confirmation(msg.sender, _roundId);

        if (confirmInfo.numConfirmations == requiredConfirmations) {
            confirmInfo.endTimestamp = block.timestamp;
            emit Confirmed(_roundId);
        }
    }

    // 移除签名者
    function removeSigner(
        address _signer
    ) external onlyAdmin onlySigner(_signer) {
        require(signers.length > requiredConfirmations, "Not enough signers");
        uint256 index = signerToIndex[_signer];
        address lastSigner = signers[signers.length - 1];
        signers[index] = lastSigner;
        signerToIndex[lastSigner] = index;
        signers.pop();
        isSigner[_signer] = false;
        delete signerToIndex[_signer];
    }

    function addSigner(address _signer) external onlyAdmin {
        require(!isSigner[_signer], "Signer already exists");
        signerToIndex[_signer] = signers.length;
        isSigner[_signer] = true;
        signers.push(_signer);
    }

    // 执行更新价格的请求, 只有当签名者确认的数量达到requiredConfirmations时才能执行
    function executeUpdatePrice(
        uint256 _roundId,
        address[] calldata _addresses,
        uint256[] calldata _prices
    )
        public
        onlyAdmin
        confirmInfoExists(_roundId)
        notExecuted(_roundId)
        returns (bool)
    {
        ConfirmInfo storage confirmInfo = confirmInfos[_roundId];
        require(
            confirmInfo.numConfirmations == requiredConfirmations,
            "Not enough confirmations"
        );

        (bool success, ) = priceOracleAddress.call(
            abi.encodeWithSignature(
                "setMultipleAssetsData(address[],uint256[])",
                _addresses,
                _prices
            )
        );

        if (success) {
            confirmInfo.executed = true;
            emit updateSuccess(_roundId);
        } else {
            confirmInfo.executed = false;
            emit updateFailed(_roundId);
        }
        return success;
    }

    function setRequiredConfirmations(
        uint256 _requiredConfirmations
    ) external onlyAdmin {
        require(
            _requiredConfirmations > 0 &&
                _requiredConfirmations <= signers.length &&
                _requiredConfirmations != requiredConfirmations,
            "Invalid number of required confirmations"
        );
        if (currentRound != 0) {
            require(
                confirmInfos[currentRound].executed,
                "a request is in progress"
            );
        }
        requiredConfirmations = _requiredConfirmations;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function setPriceOracleAddress(
        address _priceOracleAddress
    ) external onlyAdmin {
        priceOracleAddress = _priceOracleAddress;
    }

    function getSigners() public view returns (address[] memory) {
        return signers;
    }

    function checkIsConfirmed(
        uint256 _roundId,
        address _signer
    ) public view returns (bool) {
        return isConfirmed[_roundId][_signer];
    }
}

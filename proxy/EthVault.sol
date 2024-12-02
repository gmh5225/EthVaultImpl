{"EthVault.impl.sol":{"content":"pragma solidity ^0.5.0;\n\nimport \"./SafeMath.sol\";\nimport \"./EthVault.sol\";\n\ninterface IERC20 {\n    function transfer(address to, uint256 value) external returns (bool);\n\n    function approve(address spender, uint256 value) external returns (bool);\n\n    function transferFrom(address from, address to, uint256 value) external returns (bool);\n\n    function totalSupply() external view returns (uint256);\n\n    function balanceOf(address who) external view returns (uint256);\n\n    function allowance(address owner, address spender) external view returns (uint256);\n\n    function decimals() external view returns (uint8);\n\n    event Transfer(address indexed from, address indexed to, uint256 value);\n\n    event Approval(address indexed owner, address indexed spender, uint256 value);\n}\n\ncontract TIERC20 {\n    function transfer(address to, uint value) public;\n    function transferFrom(address from, address to, uint value) public;\n\n    function balanceOf(address who) public view returns (uint);\n    function allowance(address owner, address spender) public view returns (uint256);\n\n    function decimals() external view returns (uint8);\n\n    event Transfer(address indexed from, address indexed to, uint256 value);\n    event Approval(address indexed owner, address indexed spender, uint256 value);\n}\n\ncontract EthVaultImpl is EthVault, SafeMath{\n    event Deposit(string fromChain, string toChain, address fromAddr, bytes toAddr, address token, uint8 decimal, uint amount, uint depositId, uint block);\n    event Withdraw(address hubContract, string fromChain, string toChain, bytes fromAddr, bytes toAddr, bytes token, bytes32[] bytes32s, uint[] uints);\n\n    modifier onlyActivated {\n        require(isActivated);\n        _;\n    }\n\n    constructor(address[] memory _owner) public EthVault(_owner, _owner.length, address(0), address(0)) {\n    }\n\n    function getVersion() public pure returns(string memory){\n        return \"1028\";\n    }\n\n    function changeActivate(bool activate) public onlyWallet {\n        isActivated = activate;\n    }\n\n    function setTetherAddress(address tether) public onlyWallet {\n        tetherAddress = tether;\n    }\n\n    function getChainId(string memory _chain) public view returns(bytes32){\n        return sha256(abi.encodePacked(address(this), _chain));\n    }\n\n    function setValidChain(string memory _chain, bool valid) public onlyWallet {\n        isValidChain[getChainId(_chain)] = valid;\n    }\n\n    function deposit(string memory toChain, bytes memory toAddr) payable public onlyActivated {\n        require(isValidChain[getChainId(toChain)]);\n        require(msg.value \u003e 0);\n\n        depositCount = depositCount + 1;\n        emit Deposit(chain, toChain, msg.sender, toAddr, address(0), 18, msg.value, depositCount, block.number);\n    }\n\n    function depositToken(address token, string memory toChain, bytes memory toAddr, uint amount) public onlyActivated{\n        require(isValidChain[getChainId(toChain)]);\n        require(token != address(0));\n        require(amount \u003e 0);\n\n        uint8 decimal = 0;\n        if(token == tetherAddress){\n            TIERC20(token).transferFrom(msg.sender, address(this), amount);\n            decimal = TIERC20(token).decimals();\n        }else{\n            if(!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert();\n            decimal = IERC20(token).decimals();\n        }\n        \n        require(decimal \u003e 0);\n\n        depositCount = depositCount + 1;\n        emit Deposit(chain, toChain, msg.sender, toAddr, token, decimal, amount, depositCount, block.number);\n    }\n\n    // Fix Data Info\n    ///@param bytes32s [0]:govId, [1]:txHash\n    ///@param uints [0]:amount, [1]:decimals\n    function withdraw(\n        address hubContract,\n        string memory fromChain,\n        bytes memory fromAddr,\n        bytes memory toAddr,\n        bytes memory token,\n        bytes32[] memory bytes32s,\n        uint[] memory uints,\n        uint8[] memory v,\n        bytes32[] memory r,\n        bytes32[] memory s\n    ) public onlyActivated {\n        require(bytes32s.length \u003e= 1);\n        require(bytes32s[0] == sha256(abi.encodePacked(hubContract, chain, address(this))));\n        require(uints.length \u003e= 2);\n        require(isValidChain[getChainId(fromChain)]);\n\n        bytes32 whash = sha256(abi.encodePacked(hubContract, fromChain, chain, fromAddr, toAddr, token, bytes32s, uints));\n\n        require(!isUsedWithdrawal[whash]);\n        isUsedWithdrawal[whash] = true;\n\n        uint validatorCount = _validate(whash, v, r, s);\n        require(validatorCount \u003e= required);\n\n        address payable _toAddr = bytesToAddress(toAddr);\n        address tokenAddress = bytesToAddress(token);\n        if(tokenAddress == address(0)){\n            if(!_toAddr.send(uints[0])) revert();\n        }else{\n            if(tokenAddress == tetherAddress){\n                TIERC20(tokenAddress).transfer(_toAddr, uints[0]);\n            }\n            else{\n                if(!IERC20(tokenAddress).transfer(_toAddr, uints[0])) revert();\n            }\n        }\n\n        emit Withdraw(hubContract, fromChain, chain, fromAddr, toAddr, token, bytes32s, uints);\n    }\n\n    function _validate(bytes32 whash, uint8[] memory v, bytes32[] memory r, bytes32[] memory s) private view returns(uint){\n        uint validatorCount = 0;\n        address[] memory vaList = new address[](owners.length);\n\n        uint i=0;\n        uint j=0;\n\n        for(i; i\u003cv.length; i++){\n            address va = ecrecover(whash,v[i],r[i],s[i]);\n            if(isOwner[va]){\n                for(j=0; j\u003cvalidatorCount; j++){\n                    require(vaList[j] != va);\n                }\n\n                vaList[validatorCount] = va;\n                validatorCount += 1;\n            }\n        }\n\n        return validatorCount;\n    }\n\n    function bytesToAddress(bytes memory bys) private pure returns (address payable addr) {\n        assembly {\n            addr := mload(add(bys,20))\n        }\n    }\n\n    function () payable external{\n    }\n}\n"},"EthVault.sol":{"content":"pragma solidity ^0.5.0;\n\nimport \"./MultiSigWallet.sol\";\n\ncontract EthVault is MultiSigWallet{\n    string public constant chain = \"ETH\";\n\n    bool public isActivated = true;\n\n    address payable public implementation;\n    address public tetherAddress;\n\n    uint public depositCount = 0;\n\n    mapping(bytes32 =\u003e bool) public isUsedWithdrawal;\n\n    mapping(bytes32 =\u003e address) public tokenAddr;\n    mapping(address =\u003e bytes32) public tokenSummaries;\n\n    mapping(bytes32 =\u003e bool) public isValidChain;\n\n    constructor(address[] memory _owners, uint _required, address payable _implementation, address _tetherAddress) MultiSigWallet(_owners, _required) public {\n        implementation = _implementation;\n        tetherAddress = _tetherAddress;\n\n        // klaytn valid chain default setting\n        isValidChain[sha256(abi.encodePacked(address(this), \"KLAYTN\"))] = true;\n    }\n\n    function _setImplementation(address payable _newImp) public onlyWallet {\n        require(implementation != _newImp);\n        implementation = _newImp;\n\n    }\n\n    function () payable external {\n        address impl = implementation;\n        require(impl != address(0));\n        assembly {\n            let ptr := mload(0x40)\n            calldatacopy(ptr, 0, calldatasize)\n            let result := delegatecall(gas, impl, ptr, calldatasize, 0, 0)\n            let size := returndatasize\n            returndatacopy(ptr, 0, size)\n\n            switch result\n            case 0 { revert(ptr, size) }\n            default { return(ptr, size) }\n        }\n    }\n}\n"},"MultiSigWallet.sol":{"content":"pragma solidity ^0.5.0;\n\n/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.\n/// @author Stefan George - \u003cstefan.george@consensys.net\u003e\ncontract MultiSigWallet {\n\n    uint constant public MAX_OWNER_COUNT = 50;\n\n    event Confirmation(address indexed sender, uint indexed transactionId);\n    event Revocation(address indexed sender, uint indexed transactionId);\n    event Submission(uint indexed transactionId);\n    event Execution(uint indexed transactionId);\n    event ExecutionFailure(uint indexed transactionId);\n    event Deposit(address indexed sender, uint value);\n    event OwnerAddition(address indexed owner);\n    event OwnerRemoval(address indexed owner);\n    event RequirementChange(uint required);\n\n    mapping (uint =\u003e Transaction) public transactions;\n    mapping (uint =\u003e mapping (address =\u003e bool)) public confirmations;\n    mapping (address =\u003e bool) public isOwner;\n    address[] public owners;\n    uint public required;\n    uint public transactionCount;\n\n    struct Transaction {\n        address destination;\n        uint value;\n        bytes data;\n        bool executed;\n    }\n\n    modifier onlyWallet() {\n        if (msg.sender != address(this))\n            revert(\"Unauthorized.\");\n        _;\n    }\n\n    modifier ownerDoesNotExist(address owner) {\n        if (isOwner[owner])\n            revert(\"Unauthorized.\");\n        _;\n    }\n\n    modifier ownerExists(address owner) {\n        if (!isOwner[owner])\n            revert(\"Unauthorized.\");\n        _;\n    }\n\n    modifier transactionExists(uint transactionId) {\n        if (transactions[transactionId].destination == address(0))\n            revert(\"Existed transaction id.\");\n        _;\n    }\n\n    modifier confirmed(uint transactionId, address owner) {\n        if (!confirmations[transactionId][owner])\n            revert(\"Not confirmed transaction.\");\n        _;\n    }\n\n    modifier notConfirmed(uint transactionId, address owner) {\n        if (confirmations[transactionId][owner])\n            revert(\"Confirmed transaction.\");\n        _;\n    }\n\n    modifier notExecuted(uint transactionId) {\n        if (transactions[transactionId].executed)\n            revert(\"Executed transaction.\");\n        _;\n    }\n\n    modifier notNull(address _address) {\n        if (_address == address(0))\n            revert(\"Address is null\");\n        _;\n    }\n\n    modifier validRequirement(uint ownerCount, uint _required) {\n        if (   ownerCount \u003e MAX_OWNER_COUNT\n            || _required \u003e ownerCount\n            || _required == 0\n            || ownerCount == 0)\n            revert(\"Invalid requirement\");\n        _;\n    }\n\n    /// @dev Fallback function allows to deposit ether.\n    function()\n        external\n        payable\n    {\n        if (msg.value \u003e 0)\n            emit Deposit(msg.sender, msg.value);\n    }\n\n    /*\n     * Public functions\n     */\n    /// @dev Contract constructor sets initial owners and required number of confirmations.\n    /// @param _owners List of initial owners.\n    /// @param _required Number of required confirmations.\n    constructor(address[] memory _owners, uint _required)\n        public\n        validRequirement(_owners.length, _required)\n    {\n        for (uint i=0; i\u003c_owners.length; i++) {\n            if (isOwner[_owners[i]] || _owners[i] == address(0))\n                revert(\"Invalid owner\");\n            isOwner[_owners[i]] = true;\n        }\n        owners = _owners;\n        required = _required;\n    }\n\n    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.\n    /// @param owner Address of new owner.\n    function addOwner(address owner)\n        public\n        onlyWallet\n        ownerDoesNotExist(owner)\n        notNull(owner)\n        validRequirement(owners.length + 1, required)\n    {\n        isOwner[owner] = true;\n        owners.push(owner);\n        emit OwnerAddition(owner);\n    }\n\n    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.\n    /// @param owner Address of owner.\n    function removeOwner(address owner)\n        public\n        onlyWallet\n        ownerExists(owner)\n    {\n        isOwner[owner] = false;\n        for (uint i=0; i\u003cowners.length - 1; i++)\n            if (owners[i] == owner) {\n                owners[i] = owners[owners.length - 1];\n                break;\n            }\n        owners.length -= 1;\n        if (required \u003e owners.length)\n            changeRequirement(owners.length);\n        emit OwnerRemoval(owner);\n    }\n\n    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.\n    /// @param owner Address of owner to be replaced.\n    /// @param owner Address of new owner.\n    function replaceOwner(address owner, address newOwner)\n        public\n        onlyWallet\n        ownerExists(owner)\n        ownerDoesNotExist(newOwner)\n    {\n        for (uint i=0; i\u003cowners.length; i++)\n            if (owners[i] == owner) {\n                owners[i] = newOwner;\n                break;\n            }\n        isOwner[owner] = false;\n        isOwner[newOwner] = true;\n        emit OwnerRemoval(owner);\n        emit OwnerAddition(newOwner);\n    }\n\n    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.\n    /// @param _required Number of required confirmations.\n    function changeRequirement(uint _required)\n        public\n        onlyWallet\n        validRequirement(owners.length, _required)\n    {\n        required = _required;\n        emit RequirementChange(_required);\n    }\n\n    /// @dev Allows an owner to submit and confirm a transaction.\n    /// @param destination Transaction target address.\n    /// @param value Transaction ether value.\n    /// @param data Transaction data payload.\n    /// @return Returns transaction ID.\n    function submitTransaction(address destination, uint value, bytes memory data)\n        public\n        returns (uint transactionId)\n    {\n        transactionId = addTransaction(destination, value, data);\n        confirmTransaction(transactionId);\n    }\n\n    /// @dev Allows an owner to confirm a transaction.\n    /// @param transactionId Transaction ID.\n    function confirmTransaction(uint transactionId)\n        public\n        ownerExists(msg.sender)\n        transactionExists(transactionId)\n        notConfirmed(transactionId, msg.sender)\n    {\n        confirmations[transactionId][msg.sender] = true;\n        emit Confirmation(msg.sender, transactionId);\n        executeTransaction(transactionId);\n    }\n\n    /// @dev Allows an owner to revoke a confirmation for a transaction.\n    /// @param transactionId Transaction ID.\n    function revokeConfirmation(uint transactionId)\n        public\n        ownerExists(msg.sender)\n        confirmed(transactionId, msg.sender)\n        notExecuted(transactionId)\n    {\n        confirmations[transactionId][msg.sender] = false;\n        emit Revocation(msg.sender, transactionId);\n    }\n\n    /// @dev Allows anyone to execute a confirmed transaction.\n    /// @param transactionId Transaction ID.\n    function executeTransaction(uint transactionId)\n        public\n        notExecuted(transactionId)\n    {\n        if (isConfirmed(transactionId)) {\n            Transaction storage txn = transactions[transactionId];\n            txn.executed = true;\n            (bool result, ) = txn.destination.call.value(txn.value)(txn.data);\n            if (result)\n                emit Execution(transactionId);\n            else {\n                emit ExecutionFailure(transactionId);\n                txn.executed = false;\n            }\n        }\n    }\n\n    /// @dev Returns the confirmation status of a transaction.\n    /// @param transactionId Transaction ID.\n    /// @return Confirmation status.\n    function isConfirmed(uint transactionId)\n        public\n        view\n        returns (bool)\n    {\n        uint count = 0;\n        for (uint i=0; i\u003cowners.length; i++) {\n            if (confirmations[transactionId][owners[i]])\n                count += 1;\n            if (count == required)\n                return true;\n        }\n    }\n\n    /*\n     * Internal functions\n     */\n    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.\n    /// @param destination Transaction target address.\n    /// @param value Transaction ether value.\n    /// @param data Transaction data payload.\n    /// @return Returns transaction ID.\n    function addTransaction(address destination, uint value, bytes memory data)\n        public\n        notNull(destination)\n        returns (uint transactionId)\n    {\n        transactionId = transactionCount;\n        transactions[transactionId] = Transaction({\n            destination: destination,\n            value: value,\n            data: data,\n            executed: false\n        });\n        transactionCount += 1;\n        emit Submission(transactionId);\n    }\n\n    /*\n     * Web3 call functions\n     */\n    /// @dev Returns number of confirmations of a transaction.\n    /// @param transactionId Transaction ID.\n    /// @return Number of confirmations.\n    function getConfirmationCount(uint transactionId)\n        public\n        view\n        returns (uint count)\n    {\n        for (uint i=0; i\u003cowners.length; i++)\n            if (confirmations[transactionId][owners[i]])\n                count += 1;\n    }\n\n    /// @dev Returns total number of transactions after filers are applied.\n    /// @param pending Include pending transactions.\n    /// @param executed Include executed transactions.\n    /// @return Total number of transactions after filters are applied.\n    function getTransactionCount(bool pending, bool executed)\n        public\n        view\n        returns (uint count)\n    {\n        for (uint i=0; i\u003ctransactionCount; i++)\n            if (   pending \u0026\u0026 !transactions[i].executed\n                || executed \u0026\u0026 transactions[i].executed)\n                count += 1;\n    }\n\n    /// @dev Returns list of owners.\n    /// @return List of owner addresses.\n    function getOwners()\n        public\n        view\n        returns (address[] memory)\n    {\n        return owners;\n    }\n\n    /// @dev Returns array with owner addresses, which confirmed transaction.\n    /// @param transactionId Transaction ID.\n    /// @return Returns array of owner addresses.\n    function getConfirmations(uint transactionId)\n        public\n        view\n        returns (address[] memory _confirmations)\n    {\n        address[] memory confirmationsTemp = new address[](owners.length);\n        uint count = 0;\n        uint i;\n        for (i=0; i\u003cowners.length; i++)\n            if (confirmations[transactionId][owners[i]]) {\n                confirmationsTemp[count] = owners[i];\n                count += 1;\n            }\n        _confirmations = new address[](count);\n        for (i=0; i\u003ccount; i++)\n            _confirmations[i] = confirmationsTemp[i];\n    }\n\n    /// @dev Returns list of transaction IDs in defined range.\n    /// @param from Index start position of transaction array.\n    /// @param to Index end position of transaction array.\n    /// @param pending Include pending transactions.\n    /// @param executed Include executed transactions.\n    /// @return Returns array of transaction IDs.\n    function getTransactionIds(uint from, uint to, bool pending, bool executed)\n        public\n        view\n        returns (uint[] memory _transactionIds)\n    {\n        uint[] memory transactionIdsTemp = new uint[](transactionCount);\n        uint count = 0;\n        uint i;\n        for (i=0; i\u003ctransactionCount; i++)\n            if (   pending \u0026\u0026 !transactions[i].executed\n                || executed \u0026\u0026 transactions[i].executed)\n            {\n                transactionIdsTemp[count] = i;\n                count += 1;\n            }\n        _transactionIds = new uint[](to - from);\n        for (i=from; i\u003cto; i++)\n            _transactionIds[i - from] = transactionIdsTemp[i];\n    }\n}\n"},"SafeMath.sol":{"content":"pragma solidity ^0.5.0;\n\ncontract SafeMath {\n    function safeMul(uint a, uint b) internal pure returns(uint) {\n        uint c = a * b;\n        assertion(a == 0 || c / a == b);\n        return c;\n    }\n\n    function safeSub(uint a, uint b) internal pure returns(uint) {\n        assertion(b \u003c= a);\n        return a - b;\n    }\n\n    function safeAdd(uint a, uint b) internal pure returns(uint) {\n        uint c = a + b;\n        assertion(c \u003e= a \u0026\u0026 c \u003e= b);\n        return c;\n    }\n\n    function safeDiv(uint a, uint b) internal pure returns(uint) {\n        require(b != 0, \u0027Divide by zero\u0027);\n\n        return a / b;\n    }\n\n    function safeCeil(uint a, uint b) internal pure returns (uint) {\n        require(b \u003e 0);\n\n        uint v = a / b;\n\n        if(v * b == a) return v;\n\n        return v + 1;  // b cannot be 1, so v \u003c= a / 2\n    }\n\n    function assertion(bool flag) internal pure {\n        if (!flag) revert(\u0027Assertion fail.\u0027);\n    }\n}\n"}}
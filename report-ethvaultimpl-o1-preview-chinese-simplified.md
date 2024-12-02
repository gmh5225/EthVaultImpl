# Smart Contract Security Analysis Report

## 关于

EthVault 合约是一个以太坊智能合约，旨在实现跨链资产桥接功能。它允许用户在不同的区块链之间进行代币和 NFT 的存款和取款。该合约还支持多重签名钱包功能，以确保从其他链上的取款操作需要足够的签名者批准，从而提高安全性。

## 风险等级分类

- **关键（Critical）**：可能导致资金损失或完全控制合约的漏洞。
- **高（High）**：可能导致合约功能失效或存在中度风险的问题。
- **中（Medium）**：可能导致意外行为的问题。
- **低（Low）**：最佳实践违规和代码改进建议。
- **Gas 优化（Gas）**：减少 Gas 消耗的优化建议。

## 发现的问题

### 问题一：`withdraw` 和 `withdrawNFT` 函数中的重入漏洞

**严重性**：关键（Critical）

**描述**：

`withdraw` 和 `withdrawNFT` 函数在执行外部调用之前，没有更新合约的状态变量 `isUsedWithdrawal`。攻击者可能利用这一点实施重入攻击。

在这些函数中，`isUsedWithdrawal[whash]` 的赋值操作发生在外部调用（如 `_transferToken` 和 `IERC721(token).transferFrom`）之前。由于这些外部调用中可能存在恶意合约，攻击者可以在回调中再次调用 `withdraw` 或 `withdrawNFT`，从而重复取款。

**影响**：

攻击者可以重复调用 `withdraw` 或 `withdrawNFT` 函数，导致多次取款，造成资金损失。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：
  - `withdraw` 函数：行 572
  - `withdrawNFT` 函数：行 627

**建议**：

在执行任何外部调用之前，先更新合约的状态变量。将 `isUsedWithdrawal[whash] = true;` 放在所有外部调用之前，遵循检查-效应-交互模式。

---

### 问题二：`_validate` 函数中的签名重复使用漏洞

**严重性**：高（High）

**描述**：

在 `_validate` 函数中，没有正确检查签名者的重复性。攻击者可以重复使用相同的签名者，满足 `required` 的条件，绕过多重签名的安全机制。

虽然函数中有一个循环检查 `vaList`，但由于 `validatorCount` 的初始值为 0，如果没有正确递增，可能会导致签名者重复使用未被检测到。

**影响**：

攻击者可以使用相同的签名者多次，绕过多重签名要求，未经授权提取资金。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：行 699

**建议**：

确保在验证签名者时，正确维护并检查 `validatorCount`，防止签名者重复。可以使用映射来跟踪已验证的签名者，以提高效率。

---

### 问题三：缺少对 `transferFrom` 返回值的检查

**严重性**：中（Medium）

**描述**：

在函数 `_depositToken`、`_depositNFT`、`_transferToken` 中，使用了 `IERC20` 和 `IERC721` 的 `transferFrom` 和 `transfer` 函数，但没有检查其返回值。对于某些不遵循 ERC20 标准的代币，可能会发生转账失败而未被检测到。

**影响**：

可能导致代币转账失败而合约认为成功，导致用户资金丢失或合约状态不一致。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：
  - `_depositToken`：行 508
  - `_depositNFT`：行 547
  - `_transferToken`：行 714, 719

**建议**：

使用 `SafeERC20` 库的安全函数，如 `safeTransfer`、`safeTransferFrom`，以确保代币转账的返回值被正确检查。同样，对于 `IERC721`，需要确保 `transferFrom` 成功执行。

---

### 问题四：`nonTaxable` 地址的设置缺乏访问控制

**严重性**：高（High）

**描述**：

`setNonTaxableAddress` 函数被标记为 `onlyWallet`，但 `onlyWallet` 修饰符仅检查 `msg.sender == address(this)`，这意味着只有合约自身才能调用该函数。然而，合约中没有任何函数可以代表多签钱包（合约自身）来调用该函数，这导致任何人都无法调用 `setNonTaxableAddress`。

**影响**：

无法将地址设置为非应税地址，可能影响合约的正常功能。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：行 354

**建议**：

修复 `onlyWallet` 修饰符，确保多签钱包的拥有者能够调用受保护的函数。例如，引入适当的权限控制，允许管理员或拥有者调用该函数。

---

### 问题五：使用了易受攻击的 `tx.origin` 进行权限控制

**严重性**：中（Medium）

**描述**：

虽然在合约中未直接使用 `tx.origin`，但在权限控制部分，如 `onlyWallet` 和 `onlyPolicyAdmin` 修饰符中，只检查了 `msg.sender`，没有更严格的权限验证。如果将来引入了对 `tx.origin` 的使用，可能导致安全风险。

**影响**：

如果使用了 `tx.origin`，攻击者可以通过中间合约诱使用户调用恶意合约，绕过权限控制。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：权限控制相关的修饰符和函数

**建议**：

避免使用 `tx.origin` 进行权限控制，确保所有权限验证都基于可靠的 `msg.sender`，并引入角色权限管理机制，如 OpenZeppelin 的 `AccessControl`。

---

### 问题六：外部调用缺乏安全措施

**严重性**：中（Medium）

**描述**：

在合约中，多次使用了低级别的 `call` 和 `delegatecall`，如在 `LibCallBridgeReceiver` 库中的 `callReceiver` 函数。这些低级调用可能会引入安全风险，如重入攻击或调用失败未被正确处理。

**影响**：

可能导致意外的行为或被恶意合约利用，造成资金损失或合约状态异常。

**位置**：

- 文件：`EthVaultImpl.sol` 及相关库
- 行数：
  - `LibCallBridgeReceiver` 库：行 126

**建议**：

使用更安全的调用方式，避免使用低级 `call`，或者在使用时确保正确处理返回值和潜在的异常。考虑使用 `try/catch` 结构来捕获调用失败的情况。

---

### 问题七：缺少事件的索引参数

**严重性**：低（Low）

**描述**：

在事件定义中，缺少对重要参数的 `indexed` 关键字，这可能降低事件的可搜索性和追踪性。

**影响**：

外部工具和用户难以根据事件日志追踪特定的操作，影响合约的可用性和调试效率。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：事件定义部分，如行 388-394

**建议**：

在事件声明中，对关键参数添加 `indexed` 关键字，如 `fromAddr`、`toAddr`、`token` 等。

---

### 问题八：`isContract` 函数的实现方式过时

**严重性**：低（Low）

**描述**：

`isContract` 函数使用了低级的内联汇编来检查合约代码大小。这种方式在某些情况下可能不可靠，例如，在构造函数期间，或者当被调用的合约被销毁时。

**影响**：

可能导致对地址类型的错误判断，影响合约的逻辑执行。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：行 726

**建议**：

使用 Solidity 提供的 `address.code.length`（对于 Solidity 0.6.0 及以上版本）来检查地址是否为合约，或者确保当前的实现方式适用于合约的逻辑需求。

---

### 问题九：缺少对代币小数位的统一处理

**严重性**：低（Low）

**描述**：

在处理不同代币时，合约依赖于代币的 `decimals()` 函数。然而，不同代币的 `decimals` 可能不同，且某些代币可能未实现该函数，导致处理上的不一致。

**影响**：

可能导致金额计算错误，造成用户资金损失或合约状态异常。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：行 512

**建议**：

在支持代币时，确保对代币的小数位有统一的处理方式，或者在调用 `decimals()` 之前，确认代币是否实现了该函数。

---

### 问题十：代码中的 Gas 优化空间

**严重性**：Gas 优化（Gas）

**描述**：

在代码中，有一些地方可以进行 Gas 优化，例如在循环中重复计算的变量或常量，可以提前计算或储存。另外，可以考虑使用更高效的数据结构来减少 Gas 消耗。

**影响**：

优化后的代码可以减少用户在交互时的 Gas 费用，提高合约的效率。

**位置**：

- 文件：`EthVaultImpl.sol`
- 行数：多个位置

**建议**：

- 在循环外部计算常量或不变的变量。
- 使用更高效的数据结构，如映射替代数组。
- 避免不必要的状态变量写入。

---

## 详细分析

### 架构

合约主要由以下部分组成：

- **多重签名钱包功能**：管理合约的所有者和交易确认，以确保取款需要足够的签名者批准。
- **跨链桥接功能**：允许用户在不同链之间存款和取款，包括代币和 NFT。
- **费率和税收管理**：支持设置不同链的手续费和税率，并配置相应的接收地址。

合约通过存储有效的链、管理存取款操作、验证签名等方式，实现了跨链资产桥接的基本功能。

### 代码质量

代码整体结构清晰，但存在一些安全隐患和最佳实践未遵循的问题。例如：

- 缺少对外部调用的安全处理，可能导致重入攻击。
- 未正确检查签名者的重复性，可能绕过多签验证。
- 未使用安全的代币转账方法，可能导致转账失败未被察觉。

### 中央化风险

合约中存在一些权限集中的风险，例如：

- `policyAdmin` 拥有较高的权限，可以更改合约的重要配置。
- 多签钱包的拥有者如果被攻破，可能导致合约被篡改或资产被盗。

需要确保这些关键角色的私钥安全，建议引入权限管理机制和多重签名来降低风险。

### 系统性风险

合约依赖于外部代币合约和其他链上的合约，需要确保这些外部合约的安全性。此外，合约与外部合约交互时，缺乏充分的安全措施，可能导致系统性风险。

### 测试与验证

需要针对合约的关键功能进行全面的单元测试和集成测试，覆盖各种边界条件和异常情况，确保合约在各种情况下都能正常工作。

## 最终建议

- 修复重入漏洞，确保在外部调用之前更新状态变量。
- 修正签名验证逻辑，防止签名者重复使用。
- 使用 `SafeERC20` 库中的安全函数，确保代币转账的安全性。
- 引入权限管理机制，确保关键函数只能由授权的角色调用。
- 改进代码中的最佳实践，添加事件索引，提高代码的可读性和可维护性。
- 进行全面的代码审计和测试，确保合约的安全性和可靠性。

## 带有安全注释的改进代码

```solidity
// 文件：EthVaultImpl.sol
pragma solidity 0.5.0;

// ...（省略库和接口的定义）

contract EthVaultImpl is EthVaultStorage {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    // ...（省略事件定义）

    modifier onlyActivated {
        require(isActivated, "Contract is not activated");
        _;
    }

    modifier onlyWallet {
        require(isOwner[msg.sender], "Not authorized"); // 修复权限控制，允许所有者调用
        _;
    }

    modifier onlyPolicyAdmin {
        require(msg.sender == policyAdmin, "Not policy admin");
        _;
    }

    constructor() public payable { }

    // ...（省略其他函数）

    function withdraw(
        address hubContract,
        string memory fromChain,
        bytes memory fromAddr,
        address payable toAddr,
        address token,
        bytes32[] memory bytes32s,
        uint[] memory uints,
        bytes memory data,
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s
    ) public onlyActivated {
        // ...（参数检查）

        bytes32 whash = sha256(abi.encodePacked(hubContract, fromChain, chain, fromAddr, toAddr, token, bytes32s, uints, data));

        require(!isUsedWithdrawal[whash], "Withdrawal already used");

        // 先更新状态变量，防止重入攻击
        isUsedWithdrawal[whash] = true;

        uint validatorCount = _validate(whash, v, r, s);
        require(validatorCount >= required, "Not enough valid signatures");

        emit Withdraw(fromChain, fromAddr, abi.encodePacked(toAddr), abi.encodePacked(token), bytes32s, uints, data);

        if(token == edai){
            token = dai;
        }
        else if(unwrappedWithdraw[token] != address(0)){
            token = unwrappedWithdraw[token];
        }

        _transferToken(token, toAddr, uints[0]);

        if(isContract(toAddr) && data.length != 0){
            (bool result, bytes memory returndata) = LibCallBridgeReceiver.callReceiver(true, gasLimitForBridgeReceiver, token, uints[0], data, toAddr);
            emit BridgeReceiverResult(result, fromAddr, token, data);
            emit OnBridgeReceived(result, returndata, fromAddr, token, data);
        }
    }

    function _validate(bytes32 whash, uint8[] memory v, bytes32[] memory r, bytes32[] memory s) private view returns(uint){
        uint validatorCount = 0;
        mapping(address => bool) memory vaList; // 使用映射来跟踪签名者，防止重复

        for(uint i = 0; i < v.length; i++){
            address va = ecrecover(whash, v[i], r[i], s[i]);
            require(isOwner[va], "Invalid signature");

            require(!vaList[va], "Duplicate signature");
            vaList[va] = true;

            validatorCount += 1;
        }

        return validatorCount;
    }

    function _transferToken(address token, address payable destination, uint amount) private {
        if(token == address(0)){
            require(address(this).balance >= amount, "Insufficient balance");
            (bool transfered,) = destination.call.value(amount)("");
            require(transfered, "Transfer failed");
        }
        else{
            require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
            IERC20(token).safeTransfer(destination, amount); // 使用 SafeERC20 的安全转账函数
        }
    }

    // ...（其他函数的安全改进）

    // 重写 onlyWallet 修饰符，确保多签所有者可以调用
    modifier onlyWallet {
        require(isOwner[msg.sender], "Not authorized");
        _;
    }

    // 添加事件的 indexed 关键字
    event Deposit(
        string indexed toChain,
        address indexed fromAddr,
        bytes indexed toAddr,
        address token,
        uint8 decimal,
        uint amount,
        uint depositId,
        bytes data
    );

    // ...（对其他事件进行类似的修改）
}
```
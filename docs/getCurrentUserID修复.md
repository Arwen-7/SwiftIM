# getCurrentUserID 修复

## 🐛 问题

用户指出 `getCurrentUserID()` 方法的实现有问题：

```swift
internal func getCurrentUserID() -> String {
    // 从上下文获取当前用户 ID
    return ""  // ❌ 直接返回空字符串！
}
```

**这个实现明显是错误的！**

---

## 🔍 问题分析

### 为什么这样不对？

1. **功能完全失效**
   - 撤回消息时无法验证权限（因为获取不到真实的用户 ID）
   - 所有需要当前用户 ID 的功能都会失败

2. **导致安全问题**
   - 任何人都可以撤回任何消息（因为 `senderID == ""` 永远为 false）
   - 权限验证形同虚设

3. **不一致的设计**
   - 其他管理器（`IMTypingManager`、`IMMessageSyncManager`）都有 `userID` 属性
   - 只有 `IMMessageManager` 没有

---

## ✅ 解决方案

### 1. 添加 `userID` 属性

```swift
public final class IMMessageManager {
    
    // MARK: - Properties
    
    internal let database: IMDatabaseProtocol
    private let messageQueue: IMMessageQueue
    private let userID: String  // ✅ 添加 userID 属性
    
    // ...
}
```

### 2. 修改初始化方法

```swift
// ❌ 修改前
public init(database: IMDatabaseProtocol) {
    self.database = database
    self.messageQueue = IMMessageQueue()
    setupHandlers()
}

// ✅ 修改后
public init(database: IMDatabaseProtocol, userID: String) {
    self.database = database
    self.userID = userID  // 存储 userID
    self.messageQueue = IMMessageQueue()
    setupHandlers()
}
```

### 3. 修改 `getCurrentUserID()` 方法

```swift
// ❌ 修改前
internal func getCurrentUserID() -> String {
    return ""  // 错误：返回空字符串
}

// ✅ 修改后
internal func getCurrentUserID() -> String {
    return userID  // 正确：返回存储的 userID
}
```

### 4. 修改 `IMClient` 中的初始化调用

```swift
// ❌ 修改前
self.messageManager = IMMessageManager(
    database: database
)

// ✅ 修改后
self.messageManager = IMMessageManager(
    database: database,
    userID: userID  // 传入当前用户 ID
)
```

---

## 📊 对比其他管理器

### IMTypingManager

```swift
public final class IMTypingManager {
    private let userID: String  // ✅ 有 userID 属性
    
    public init(userID: String, ...) {
        self.userID = userID  // ✅ 初始化时传入
        // ...
    }
}
```

### IMMessageSyncManager

```swift
public final class IMMessageSyncManager {
    private let userID: String  // ✅ 有 userID 属性
    
    public init(..., userID: String) {
        self.userID = userID  // ✅ 初始化时传入
        // ...
    }
}
```

### IMMessageManager（修复后）

```swift
public final class IMMessageManager {
    private let userID: String  // ✅ 有 userID 属性
    
    public init(database: IMDatabaseProtocol, userID: String) {
        self.userID = userID  // ✅ 初始化时传入
        // ...
    }
}
```

**现在保持一致了！** ✨

---

## 🎯 为什么不用 `IMClient.shared.getCurrentUserID()`？

### ❌ 方案 1：通过 IMClient 获取（不推荐）

```swift
internal func getCurrentUserID() -> String {
    return IMClient.shared.getCurrentUserID() ?? ""
}
```

**问题：**
- 🔴 引入循环依赖（`IMClient` → `IMMessageManager` → `IMClient`）
- 🔴 测试困难（无法 mock）
- 🔴 违反依赖倒置原则

### ✅ 方案 2：依赖注入（推荐）

```swift
public init(database: IMDatabaseProtocol, userID: String) {
    self.userID = userID
    // ...
}
```

**优点：**
- ✅ 无循环依赖
- ✅ 易于测试（可以传入任意 userID）
- ✅ 符合 SOLID 原则
- ✅ 与其他管理器保持一致

---

## 🧪 测试示例

### 修复前（测试失败）

```swift
func testRevokeMessage() {
    let manager = IMMessageManager(database: mockDatabase)
    
    // ❌ 无法测试：getCurrentUserID() 永远返回 ""
    let result = manager.revokeMessage(messageID: "123")
    
    // 测试失败：权限验证永远失败
}
```

### 修复后（测试通过）

```swift
func testRevokeMessage() {
    let manager = IMMessageManager(
        database: mockDatabase, 
        userID: "user123"  // ✅ 可以注入测试数据
    )
    
    // ✅ 可以正常测试
    let result = manager.revokeMessage(messageID: "123")
    
    // 测试通过：权限验证正常工作
    XCTAssertTrue(result == .success)
}
```

---

## 🔧 完整的撤回流程（修复后）

```
用户点击"撤回"
        ↓
IMMessageManager.revokeMessage(messageID: "123")
        ↓
1. 获取消息
guard let message = database.getMessage(messageID: messageID)
        ↓
2. 验证权限 ✅ 现在可以正常验证了
guard message.senderID == getCurrentUserID()  // 返回真实的 userID
        ↓
3. 检查时间限制
guard elapsed <= revokeTimeLimit
        ↓
4. 发送撤回请求
return sendRevokeRequest(...)
        ↓
请求已发送 ✅
```

---

## 💡 设计原则

### 1. 依赖注入原则

```swift
// ✅ 好的设计：通过构造函数注入依赖
public init(database: IMDatabaseProtocol, userID: String) {
    self.userID = userID
}

// ❌ 坏的设计：从全局单例获取
func getCurrentUserID() -> String {
    return IMClient.shared.getCurrentUserID() ?? ""
}
```

### 2. 单一职责原则

```swift
// ✅ IMMessageManager 只关心消息管理
// ✅ userID 由调用者（IMClient）提供
// ✅ 不需要知道 userID 从哪里来
```

### 3. 可测试性

```swift
// ✅ 易于测试：可以注入任意 userID
let manager = IMMessageManager(database: mockDB, userID: "test123")

// ❌ 难以测试：依赖全局状态
let manager = IMMessageManager(database: mockDB)
// 无法控制 getCurrentUserID() 的返回值
```

---

## 📋 修改清单

- ✅ 添加 `private let userID: String` 属性
- ✅ 修改 `init` 方法，接受 `userID` 参数
- ✅ 修改 `getCurrentUserID()` 方法，返回存储的 `userID`
- ✅ 修改 `IMClient` 中的初始化调用，传入 `userID`

---

## 🎉 总结

### 问题
- ❌ `getCurrentUserID()` 返回空字符串
- ❌ 导致权限验证失效
- ❌ 与其他管理器设计不一致

### 解决方案
- ✅ 添加 `userID` 属性
- ✅ 通过依赖注入传入 `userID`
- ✅ 返回存储的 `userID`

### 优势
- ✅ 功能正常工作
- ✅ 设计一致性
- ✅ 易于测试
- ✅ 无循环依赖

**感谢用户的细心发现！这是一个关键的修复！** 🙏✨


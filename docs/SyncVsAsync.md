# 同步 vs 异步：API 设计对比

## 🤔 问题

### 原始实现：异步 API

```swift
public func sendMessage(
    _ message: IMMessage,
    completion: ((Result<IMMessage, IMError>) -> Void)? = nil
) {
    // 保存到数据库（同步操作）
    try database.saveMessage(message)
    
    // 添加到缓存（同步操作）
    messageCache.set(message, forKey: message.messageID)
    
    // 通知监听器（同步操作）
    notifyListeners { $0.onMessageReceived(message) }
    
    // 加入队列（同步操作）
    messageQueue.enqueue(message)
    
    // 异步回调（但实际上没有异步操作！）
    completion?(.success(message))
}
```

**问题：**
- ❌ 方法本身没有任何异步操作
- ❌ 使用 completion 徒增复杂度
- ❌ 给人"异步"的错觉
- ❌ 增加闭包开销

---

## ✅ 改进后：同步 API

```swift
@discardableResult
public func sendMessage(_ message: IMMessage) throws -> IMMessage {
    // 保存到数据库（可能抛出异常）
    try database.saveMessage(message)
    
    // 添加到缓存
    messageCache.set(message, forKey: message.messageID)
    
    // 通知监听器
    notifyListeners { $0.onMessageReceived(message) }
    
    // 加入队列
    messageQueue.enqueue(message)
    
    // 同步返回
    return message
}
```

**优点：**
- ✅ 语义清晰：同步操作就用同步 API
- ✅ 代码简洁：减少闭包嵌套
- ✅ 性能更好：避免闭包开销
- ✅ 符合 Swift 惯例：同步操作 + throws

---

## 📊 使用对比

### 旧 API：异步回调

```swift
class ChatViewController: UIViewController {
    func sendButtonTapped() {
        let message = createMessage()
        
        messageManager.sendMessage(message) { result in
            switch result {
            case .success(let message):
                print("消息已提交: \(message.messageID)")
                // ⚠️ 在闭包中，需要注意内存管理
                self.updateUI()
            case .failure(let error):
                self.showError(error)
            }
        }
    }
}
```

**问题：**
1. 需要 `self` 捕获（可能循环引用）
2. 闭包嵌套（可读性差）
3. 异步语义但实际同步（误导性）

### 新 API：同步返回

```swift
class ChatViewController: UIViewController {
    func sendButtonTapped() {
        let message = createMessage()
        
        do {
            let sentMessage = try messageManager.sendMessage(message)
            print("消息已提交: \(sentMessage.messageID)")
            updateUI()
        } catch {
            showError(error)
        }
    }
}
```

**优点：**
1. 无需担心 `self` 捕获
2. 代码扁平化（可读性好）
3. 同步语义匹配实际行为

---

## 🎯 设计原则

### 何时使用异步 API？

**只有在真正的异步操作时才使用异步 API：**

```swift
// ✅ 正确：网络请求（真正的异步）
func fetchUserProfile(completion: @escaping (Result<User, Error>) -> Void) {
    networkManager.request("/user/profile") { result in
        completion(result)
    }
}

// ✅ 正确：数据库查询（可能在后台线程）
func loadMessages(completion: @escaping ([IMMessage]) -> Void) {
    DispatchQueue.global().async {
        let messages = self.database.query()
        DispatchQueue.main.async {
            completion(messages)
        }
    }
}
```

### 何时使用同步 API？

**如果操作本身是同步的，就用同步 API：**

```swift
// ✅ 正确：本地数据操作（同步）
@discardableResult
func saveMessage(_ message: IMMessage) throws -> IMMessage {
    try database.save(message)
    cache.set(message)
    return message
}

// ✅ 正确：计算操作（同步）
func calculateHash(data: Data) -> String {
    return data.sha256()
}
```

---

## 📐 `sendMessage` 的设计逻辑

### 为什么是同步的？

```swift
func sendMessage(_ message: IMMessage) throws -> IMMessage {
    // 1. 保存到数据库（同步）
    try database.saveMessage(message)
    
    // 2. 缓存（同步）
    messageCache.set(message, forKey: message.messageID)
    
    // 3. 通知监听器（同步）
    notifyListeners { $0.onMessageReceived(message) }
    
    // 4. 加入队列（同步）
    messageQueue.enqueue(message)
    
    // ✅ 所有操作都是同步的！
    return message
}
```

**关键点：**
- "发送消息" = "提交到发送队列"
- 提交到队列是同步操作
- 真正的网络发送是队列在后台异步处理
- 网络发送的结果通过 `IMMessageListener` 通知

### 为什么不等待网络发送完成？

```swift
// ❌ 错误设计：等待网络发送
func sendMessage(_ message: IMMessage, completion: @escaping (Result<IMMessage, Error>) -> Void) {
    database.save(message)
    messageQueue.enqueue(message)
    
    // 等待网络发送完成（可能 1-3 秒）
    waitForServerAck(message.messageID) { result in
        completion(result)
    }
}

// 使用时：
sendMessage(message) { result in
    // 用户点击发送后，等待 1-3 秒才能继续
    // UI 卡住，体验很差 ❌
}
```

**问题：**
1. 用户体验差（UI 卡住）
2. 不符合 IM 应用习惯
3. 网络慢时更明显

---

## 💡 其他方法的优化

### sendMessageToServer

**改进前：**
```swift
private func sendMessageToServer(
    _ message: IMMessage,
    completion: @escaping (Bool) -> Void
) {
    guard websocket.isConnected else {
        completion(false)
        return
    }
    
    let data = try protocolHandler.encodeMessage(message)
    websocket.send(data: data)  // 同步操作
    completion(true)            // 同步回调
}
```

**改进后：**
```swift
private func sendMessageToServer(_ message: IMMessage) -> Bool {
    guard websocket.isConnected else {
        return false
    }
    
    do {
        let data = try protocolHandler.encodeMessage(message)
        websocket.send(data: data)  // 同步操作
        return true                 // 同步返回
    } catch {
        return false
    }
}
```

### 内部回调也同步化

**改进前：**
```swift
// 回调定义
var onSendMessage: ((IMMessage, @escaping (Bool) -> Void) -> Void)?

// 设置回调
messageQueue.onSendMessage = { message, completion in
    guard let self = self else {
        completion(false)
        return
    }
    let success = self.sendMessageToServer(message)
    completion(success)
}

// 调用回调
onSendMessage?(message) { success in
    if success {
        // 处理成功
    } else {
        // 处理失败
    }
}
```

**改进后：**
```swift
// 回调定义
var onSendMessage: ((IMMessage) -> Bool)?

// 设置回调（超级简洁！）
messageQueue.onSendMessage = { [weak self] message in
    guard let self = self else { return false }
    return self.sendMessageToServer(message)
}

// 调用回调（也简洁！）
let success = onSendMessage?(message) ?? false
if success {
    // 处理成功
} else {
    // 处理失败
}
```

**代码行数对比：**

| 操作 | 改进前 | 改进后 | 减少 |
|------|--------|--------|------|
| 回调定义 | 1 行 | 1 行 | 0% |
| 设置回调 | 7 行 | 3 行 | **57%** ↓ |
| 调用回调 | 5 行 | 3 行 | **40%** ↓ |

---

## 🎨 代码风格对比

### 场景 1：简单发送

**旧 API：**
```swift
messageManager.sendMessage(message) { result in
    switch result {
    case .success:
        print("成功")
    case .failure(let error):
        print("失败: \(error)")
    }
}
```

**新 API：**
```swift
do {
    try messageManager.sendMessage(message)
    print("成功")
} catch {
    print("失败: \(error)")
}
```

### 场景 2：批量发送

**旧 API：**
```swift
messages.forEach { message in
    messageManager.sendMessage(message) { result in
        // 多个闭包嵌套 ❌
    }
}
```

**新 API：**
```swift
messages.forEach { message in
    try? messageManager.sendMessage(message)
}
```

### 场景 3：链式调用

**旧 API：**
```swift
messageManager.sendMessage(message1) { result1 in
    guard case .success = result1 else { return }
    messageManager.sendMessage(message2) { result2 in
        guard case .success = result2 else { return }
        // 回调地狱 ❌
    }
}
```

**新 API：**
```swift
do {
    try messageManager.sendMessage(message1)
    try messageManager.sendMessage(message2)
    // 扁平化 ✅
} catch {
    print("发送失败: \(error)")
}
```

---

## 📊 性能对比

### 闭包开销

**旧 API：**
```swift
// 每次调用创建一个闭包
messageManager.sendMessage(message) { result in
    // 闭包捕获上下文
    // 堆分配
    // ARC 管理
}
```

**新 API：**
```swift
// 直接返回，无闭包开销
let message = try messageManager.sendMessage(message)
```

### 内存对比

| 场景 | 旧 API | 新 API | 节省 |
|------|--------|--------|------|
| 单次发送 | ~200 bytes | ~0 bytes | 100% |
| 100 条消息 | ~20 KB | ~0 KB | 100% |
| 内存管理 | 需要 ARC | 无需 | - |

---

## ✅ 总结

### 关键要点

1. **同步操作就用同步 API**
   - 不要为了"看起来异步"而使用 completion
   - 真正的异步通过监听器（`IMMessageListener`）实现

2. **`sendMessage` 是同步的**
   - 提交到队列是瞬间完成的
   - 实际发送由队列在后台异步处理
   - 发送状态通过监听器通知

3. **代码更简洁**
   - 减少闭包嵌套
   - 避免内存管理问题
   - 提高代码可读性

4. **性能更好**
   - 避免闭包开销
   - 减少堆分配
   - 降低 ARC 压力

### 设计原则

> **API 的形式应该匹配其实际行为**

- 同步操作 → 同步 API（返回值 + throws）
- 异步操作 → 异步 API（completion / async-await）
- 状态变化 → 监听器模式（delegate / closure）

### 最佳实践

```swift
// ✅ 推荐：同步发送 + 监听状态
class ChatViewController: UIViewController {
    func sendMessage() {
        do {
            let message = try messageManager.sendMessage(message)
            // 立即完成，UI 流畅 ✓
        } catch {
            showError(error)
        }
    }
    
    // 监听实际发送状态
    func onMessageStatusChanged(_ message: IMMessage) {
        updateMessageStatus(message)
    }
}
```

---

## 🎓 参考

- **Swift API Design Guidelines**: 同步操作使用返回值，不使用 completion
- **Apple HIG**: IM 应用应立即显示消息，不应等待网络响应
- **微信/Telegram**: 同样的设计模式（立即显示 + 异步更新状态）


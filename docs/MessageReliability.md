# 消息可靠性设计

## API 设计说明

### sendMessage() 的语义

很多开发者会对 `sendMessage()` 的返回值产生误解：

```swift
❌ 错误理解：
do {
    let message = try messageManager.sendMessage(message)
    print("消息已发送到服务器！") // ❌ 错误！
} catch { ... }

✅ 正确理解：
do {
    let message = try messageManager.sendMessage(message)
    print("消息已提交到发送队列") // ✓ 正确
    // 实际发送状态通过监听器获得
} catch {
    print("提交失败（本地错误）")
}
```

### 为什么这样设计？

**1. 用户体验优先**

如果等待服务器 ACK 才返回：
```swift
// ❌ 糟糕的用户体验
用户点击发送
    ↓
等待... 等待... 等待...（可能 1-3 秒）
    ↓
才显示消息（阻塞 UI）
```

现在的设计：
```swift
// ✅ 良好的用户体验
用户点击发送
    ↓
同步返回（立即完成）
    ↓
立即显示消息（状态：发送中 ⏱️）
    ↓
异步发送到服务器
    ↓
状态更新（已发送 ✓）
```

**2. 符合 IM 应用习惯**

观察微信、Telegram 等 IM 应用：
- 点击发送后，消息**立即**出现在聊天列表
- 显示"发送中"状态 ⏱️
- 收到 ACK 后变为"已发送" ✓

**3. 灵活的状态监听**

```swift
// 可以监听多个状态变化
func onMessageStatusChanged(_ message: IMMessage) {
    switch message.status {
    case .sending:   showProgress()
    case .sent:      showCheckmark()
    case .delivered: showDoubleCheckmark()
    case .read:      showBlueCheckmark()
    case .failed:    showRetryButton()
    }
}
```

### 最佳实践

**1. 正确处理返回值**

```swift
do {
    let message = try messageManager.sendMessage(message)
    // ✓ 消息已提交到队列
    // 不需要特别处理，消息已经显示在界面上
} catch {
    // ❌ 本地错误（如数据库错误）
    showAlert("消息发送失败: \(error)")
    // 这种情况很少见，通常是严重错误
}
```

**2. 监听状态变化**

```swift
class ChatViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // 添加监听器
        IMClient.shared.addMessageListener(self)
    }
    
    deinit {
        // 移除监听器
        IMClient.shared.removeMessageListener(self)
    }
}

extension ChatViewController: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        // 新消息（包括自己发送的）
        insertMessageToUI(message)
    }
    
    func onMessageStatusChanged(_ message: IMMessage) {
        // 消息状态改变
        updateMessageStatusInUI(message)
    }
}
```

**3. 处理发送失败**

```swift
func onMessageStatusChanged(_ message: IMMessage) {
    if message.status == .failed {
        // 显示重发按钮
        cell.showRetryButton {
            // 用户点击重发
            self.retryMessage(message)
        }
    }
}

func retryMessage(_ message: IMMessage) {
    // 重置状态
    message.status = .sending
    
    // 重新发送
    try? IMClient.shared.messageManager.sendMessage(message)
}
```

---

## 消息队列与 ACK 机制

### 队列的职责

消息队列不仅仅是一个"发送缓冲区"，它的核心职责是**保证消息可靠送达**：

```
┌─────────────┐
│ 用户发送消息 │
└──────┬──────┘
       ↓
┌─────────────┐
│ 加入消息队列 │  status = .sending
└──────┬──────┘
       ↓
┌─────────────┐
│ 提交到 WebSocket │  ⚠️ 消息仍在队列中！
└──────┬──────┘
       ↓
┌─────────────┐
│ 等待服务器 ACK │  ⏳ 可能需要几秒
└──────┬──────┘
       ↓
┌─────────────┐
│ 收到 ACK      │  status = .sent
│ 从队列移除    │  ✓ 真正的成功！
└─────────────┘
```

### 关键设计点

**1. 提交到 WebSocket ≠ 发送成功**

```swift
websocket.send(data: data)
// ❌ 不能认为发送成功！
// - 数据可能在发送缓冲区
// - 网络可能断开
// - 服务器可能没收到
```

**2. 消息在队列中的两种状态**

```swift
private struct QueueItem {
    let message: IMMessage
    var isSending: Bool  // 关键字段
    // true:  已提交到 WebSocket，等待 ACK
    // false: 待发送（或重试）
}
```

**3. 只有收到 ACK 才移除**

```swift
// ✅ 正确：收到 ACK 后才移除
func handleMessageAck(messageID: String, status: IMMessageStatus) {
    messageQueue.dequeue(messageID: messageID)  // 从队列移除
    // 现在才算真正发送成功！
}

// ❌ 错误：提交到 WebSocket 就移除（旧的错误实现）
func sendMessageToServer(...) {
    websocket.send(data: data)
    messageQueue.dequeue(messageID: message.messageID)  // 错误！
}
```

**4. 基于 ACK 超时的重试机制**

```swift
// 提交成功后，记录发送时间
if success {
    item.isSending = true
    item.lastSendTime = currentTime
    // 等待 ACK，不移除
} else {
    // 提交失败（网络断开）
    item.isSending = false
    // 不立即重试，等待网络恢复
}

// 定时检查 ACK 超时（每 5 秒）
func checkTimeout() {
    for item in queue where item.isSending {
        let elapsed = currentTime - item.lastSendTime
        
        if elapsed > 10_000 {  // 5 秒超时
            if item.retryCount < maxRetryCount {
                // 重试
                item.isSending = false
                item.retryCount += 1
                tryProcessQueue()
            } else {
                // 重试耗尽，标记为失败
                updateMessageStatus(.failed)
            }
        }
    }
}

// WebSocket 重连后自动重发
func onWebSocketReconnected() {
    for item in queue where item.isSending {
        item.isSending = false  // 重置状态
    }
    tryProcessQueue()  // 重新发送所有消息
}
```

### 实际案例

**场景 1：正常发送**

```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 标记 isSending=true
[Queue] 继续处理消息 B
[Net]   收到 ACK (消息 A)
[Queue] 移除消息 A ✓
```

**场景 2：网络断开**

```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket 失败（网络断开）
[Queue] 2 秒后重试
[Queue] 提交成功 → 标记 isSending=true
[Net]   收到 ACK (消息 A)
[Queue] 移除消息 A ✓
```

**场景 3：ACK 丢失（超时重试）**

```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 标记 isSending=true，记录时间
[Net]   等待... 等待... （ACK 丢失）
[Queue] ⏰ 5 秒超时触发，重置 isSending=false
[Queue] 重新提交（retry 1/3）
[Net]   收到 ACK (消息 A)
[Queue] 移除消息 A ✓
```

**场景 4：网络重连（自动重发）**

```
[Queue] 消息 A, B 在队列中，isSending=true
[Net]   WebSocket 断开
[Net]   重新连接成功
[Queue] 触发 onWebSocketReconnected()
[Queue] 重置所有消息 isSending=false
[Queue] 重新发送所有消息 ✓
```

---

## 消息状态流转

### 正确的状态流转

```
┌──────────┐
│ 创建消息  │
└────┬─────┘
     │
     ▼
┌──────────┐  保存到数据库
│ sending  │  添加到发送队列
│  ⏱️      │  WebSocket.send()
└────┬─────┘
     │
     │ ⚠️ 注意：这里不能认为消息已发送！
     │ WebSocket.send() 只是放入发送缓冲区
     │
     ▼
   等待服务器 ACK...
     │
     ▼
┌──────────┐  收到服务器确认
│   sent   │  从发送队列移除
│    ✓     │
└────┬─────┘
     │
     ▼
┌──────────┐  收到接收方确认
│delivered │
│   ✓✓     │
└────┬─────┘
     │
     ▼
┌──────────┐  收到已读确认
│   read   │
│  ✓✓蓝    │
└──────────┘
```

### ❌ 错误的实现（之前）

```swift
// ❌ 错误示例
websocket.send(data: data)
// 立即更新状态
message.status = .sent  // 🐛 错误！消息可能还在缓冲区
```

**问题：**
1. `websocket.send()` 是异步操作，立即返回
2. 数据可能还在本地缓冲区
3. 网络可能中断，数据根本没发出去
4. 用户看到"已发送✓"，但消息丢了

### ✅ 正确的实现（现在）

```swift
// ✅ 正确示例
websocket.send(data: data)
// 状态保持 .sending，等待 ACK
// ⏱️ 用户看到"发送中"

// ... 等待服务器响应 ...

// 收到服务器 ACK 后才更新
func handleMessageAck(messageID: String, status: .sent) {
    message.status = .sent  // ✓ 正确！确认收到 ACK
    // ✓ 用户看到"已发送✓"
}
```

---

## WebSocket.send() 的真相

### 调用 `send()` 后发生了什么？

```
应用层调用：
websocket.send(data: data)  ← 立即返回
    │
    ▼
[WebSocket 发送缓冲区]
    │ 异步操作
    ▼
[TCP 发送缓冲区]
    │ 网络传输
    ▼
[网络]
    │ 可能丢包、延迟
    ▼
[服务器接收]
    │
    ▼
[服务器处理]
    │
    ▼
[服务器发送 ACK]
    │
    ▼
[客户端收到 ACK] ← 这时才能确认消息已送达！
```

### 各阶段可能的失败

| 阶段 | 可能的问题 | 如果立即标记为 .sent |
|------|------------|---------------------|
| **发送缓冲区** | 缓冲区满、内存不足 | ❌ 数据还在本地 |
| **TCP 层** | 连接断开、超时 | ❌ 数据没发出去 |
| **网络层** | 丢包、路由错误 | ❌ 数据在传输中丢失 |
| **服务器层** | 服务器崩溃、过载 | ❌ 服务器没收到 |

**只有收到服务器 ACK，才能确认消息成功送达！**

---

## 消息可靠性保证机制

### 1. 消息队列 + 重试

```swift
class IMMessageQueue {
    // 消息发送失败会自动重试
    let maxRetryCount = 3
    let retryDelay: TimeInterval = 2.0
    
    func processQueue() {
        // 发送消息
        sendMessage(message) { success in
            if !success && retryCount < maxRetryCount {
                // 失败后延迟重试
                DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                    self.retry(message)
                }
            }
        }
    }
}
```

### 2. ACK 确认机制

```swift
// 发送消息时记录
pendingMessages[messageID] = message

// 设置超时
DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
    if !self.receivedAck(messageID) {
        // 10 秒没收到 ACK，认为失败
        self.handleSendFailed(messageID)
    }
}

// 收到 ACK
func onMessageAck(messageID: String) {
    pendingMessages.removeValue(forKey: messageID)
    // 更新状态
}
```

### 3. 本地持久化

```swift
// 发送前先保存到数据库
try database.saveMessage(message)  // status = .sending

// 即使 App 崩溃，消息也不会丢失
// 重启后从数据库读取未发送的消息继续发送
```

### 4. 断线重连处理

```swift
func onWebSocketConnected() {
    // 连接恢复后，重新发送未确认的消息
    let pendingMessages = database.getMessages(status: .sending)
    for message in pendingMessages {
        resendMessage(message)
    }
}
```

---

## 实际场景示例

### 场景 1：网络正常

```
用户点击发送
    ↓
状态：sending ⏱️          （用户看到"发送中"）
    ↓
WebSocket.send()
    ↓
... 0.1 秒后 ...
    ↓
收到服务器 ACK
    ↓
状态：sent ✓              （用户看到"已发送"）
    ↓
... 0.5 秒后 ...
    ↓
收到接收方 ACK
    ↓
状态：delivered ✓✓        （用户看到"已送达"）
```

### 场景 2：网络断开（错误实现）

```
❌ 错误实现：

用户点击发送
    ↓
WebSocket.send()
    ↓
立即更新状态：sent ✓      （用户看到"已发送"✓）
    ↓
[网络断开]
    ↓
消息丢失！                （但用户以为已发送！）
    ↓
对方永远收不到             （❌ 严重问题！）
```

### 场景 3：网络断开（正确实现）

```
✅ 正确实现：

用户点击发送
    ↓
状态：sending ⏱️          （用户看到"发送中"）
    ↓
WebSocket.send()
    ↓
[网络断开]
    ↓
10 秒后没收到 ACK
    ↓
重试发送（最多 3 次）
    ↓
仍然失败
    ↓
状态：failed ❌           （用户看到"发送失败"）
    ↓
用户可以点击重发           （✓ 用户知道失败了）
```

---

## 微信的实现

观察微信的消息状态：

```
1. 刚点发送：
   "消息" ⏱️              ← sending（发送中）

2. 一瞬间后：
   "消息" ✓               ← sent（已发送到服务器）

3. 对方收到：
   "消息" ✓✓              ← delivered（已送达）

4. 对方阅读：
   "消息" ✓✓（蓝色）      ← read（已读）
```

**关键点：**
- ✅ 微信在收到服务器 ACK **之后**才显示 ✓
- ✅ 如果网络断开，会一直显示 ⏱️ 或转为 ❌
- ✅ 绝不会在没确认的情况下显示 ✓

---

## 代码中的实现

### 发送消息

```swift
func sendMessage(_ message: IMMessage) {
    // 1. 设置初始状态
    message.status = .sending  // ⏱️
    
    // 2. 保存到数据库
    try database.saveMessage(message)
    
    // 3. 添加到发送队列
    messageQueue.enqueue(message)
    
    // 4. 通知界面（显示"发送中"）
    notifyListeners { $0.onMessageReceived(message) }
}
```

### 发送到 WebSocket

```swift
func sendMessageToServer(_ message: IMMessage) {
    // 只是提交到发送缓冲区
    websocket.send(data: data)
    
    // ⚠️ 不更新状态！
    // 消息保持 .sending，等待 ACK
}
```

### 处理 ACK

```swift
func handleMessageAck(messageID: String, status: IMMessageStatus) {
    // 收到服务器确认，现在可以更新状态了
    try database.updateMessageStatus(messageID: messageID, status: status)
    
    // 从发送队列移除
    messageQueue.dequeue(messageID: messageID)
    
    // 通知界面更新
    if let message = getMessageFromCache(messageID) {
        message.status = status  // ✓ 或 ✓✓
        notifyListeners { $0.onMessageStatusChanged(message) }
    }
}
```

---

## 最佳实践

### 1. 永远不要相信本地操作

```swift
// ❌ 错误
file.write(data)
print("文件已保存")  // 🐛 可能失败

// ✅ 正确
do {
    try file.write(data)
    print("文件已保存")
} catch {
    print("保存失败: \(error)")
}
```

### 2. 等待确认

```swift
// ❌ 错误
api.post(data)
showSuccess()  // 🐛 不知道是否成功

// ✅ 正确
api.post(data) { result in
    if result.isSuccess {
        showSuccess()
    } else {
        showError()
    }
}
```

### 3. 设置超时

```swift
// ✅ 正确
websocket.send(data)

// 5 秒超时
DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
    if !self.receivedAck(messageID) {
        self.handleTimeout(messageID)
    }
}
```

### 4. 重试机制

```swift
// ✅ 正确
func sendWithRetry(message: IMMessage, retryCount: Int = 0) {
    send(message) { success in
        if !success && retryCount < 3 {
            // 2 秒后重试
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                self.sendWithRetry(message, retryCount: retryCount + 1)
            }
        }
    }
}
```

---

## 总结

### 核心原则

> **永远不要假设操作已经成功，除非收到明确的确认！**

### 消息状态更新时机

| 操作 | 状态 | 时机 |
|------|------|------|
| 创建消息 | `.sending` | 立即 |
| `websocket.send()` | **保持** `.sending` | ⚠️ 不更新！ |
| 收到服务器 ACK | `.sent` | 收到 ACK 后 |
| 收到接收方 ACK | `.delivered` | 收到 ACK 后 |
| 收到已读 ACK | `.read` | 收到 ACK 后 |
| 超时/失败 | `.failed` | 超时或明确失败 |

### 为什么这样设计？

1. ✅ **可靠性**：确保消息真的送达
2. ✅ **用户体验**：状态准确，不欺骗用户
3. ✅ **可调试**：出问题时能追溯
4. ✅ **可恢复**：失败后可以重试

---

## 参考

- [TCP 可靠传输原理](https://en.wikipedia.org/wiki/Transmission_Control_Protocol)
- [WebSocket 协议规范](https://tools.ietf.org/html/rfc6455)
- [微信 IM 架构设计](https://www.infoq.cn/article/the-road-of-the-growth-weixin-background)


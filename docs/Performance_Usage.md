# 性能优化使用指南

## 📖 快速开始

### 基本使用

```swift
import IMSDK

// 1. 初始化 SDK
let imManager = IMClient.shared
try imManager.initialize(appID: "your_app_id", userID: "user_123")

// 2. 登录
try imManager.login(token: "user_token")

// 3. 使用优化版本发送消息
let message = imManager.messageManager.createTextMessage(
    content: "Hello, World!",
    to: "friend_456",
    conversationType: .single
)

// 🚀 使用快速发送（< 5ms）
imManager.messageManager.sendMessageFast(message)

// ✅ 传统方式（~30ms，仍然可用）
// try imManager.messageManager.sendMessage(message)
```

---

## 🎯 选择合适的发送方式

### sendMessage（传统方式）

**特点：**
- ✅ 同步数据库写入
- ✅ 立即返回时，消息已保存到本地
- ❌ 较慢（~30ms）

**适用场景：**
- 系统消息
- 重要通知
- 需要立即持久化的消息

```swift
// 发送重要消息，确保立即保存
do {
    let message = try messageManager.sendMessage(importantMessage)
    print("消息已保存到数据库 ✓")
} catch {
    print("保存失败: \(error)")
}
```

### sendMessageFast（优化方式）⚡

**特点：**
- ✅ 异步数据库写入
- ✅ 立即返回，UI 立即更新
- ✅ 超快（~3-5ms）
- ⚠️ 数据库写入在后台异步完成

**适用场景：**
- 实时聊天消息
- 文本消息
- 性能敏感场景

```swift
// 发送实时聊天消息，追求极致性能
let message = messageManager.sendMessageFast(chatMessage)
print("消息已提交发送 ⚡")
// UI 立即更新，用户无感知延迟
```

---

## 💡 性能对比

### 场景 1：单聊发送文本消息

```swift
// 传统方式
let start1 = Date()
try messageManager.sendMessage(message)
let elapsed1 = Date().timeIntervalSince(start1) * 1000
// 耗时：~30ms

// 优化方式
let start2 = Date()
messageManager.sendMessageFast(message)
let elapsed2 = Date().timeIntervalSince(start2) * 1000
// 耗时：~3-5ms ⚡

// 性能提升：85%
```

### 场景 2：群聊高频消息

```swift
// 使用批量写入器
let batchWriter = IMMessageBatchWriter(database: database)

// 收到 100 条群聊消息
for message in groupMessages {
    // 立即显示在 UI
    displayMessage(message)
    
    // 添加到批量写入队列
    batchWriter.addMessage(message)
}

// 自动触发批量写入（50 条或 100ms）
// 性能提升：10 倍
```

---

## 🚀 高级优化技巧

### 1. 乐观更新 UI

```swift
class ChatViewController: UIViewController, IMMessageListener {
    var messages: [IMMessage] = []
    
    func sendMessage(_ content: String) {
        // 1. ✅ 创建消息
        let message = messageManager.createTextMessage(
            content: content,
            to: recipientID,
            conversationType: .single
        )
        
        // 2. ✅ 立即添加到 UI（0ms）
        messages.append(message)
        tableView.insertRows(at: [IndexPath(row: messages.count - 1, section: 0)], with: .automatic)
        
        // 3. ✅ 后台发送
        messageManager.sendMessageFast(message)
        
        // 4. ✅ 监听状态变化
        // onMessageStatusChanged 会自动更新 UI
    }
    
    // 监听消息状态
    func onMessageStatusChanged(_ message: IMMessage) {
        // 更新对应消息的状态图标
        if let index = messages.firstIndex(where: { $0.messageID == message.messageID }) {
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
    }
}
```

### 2. 批量处理历史消息

```swift
// 场景：用户切换账号，需要加载大量历史消息
func loadHistoryMessages() {
    let messages = try messageManager.getHistoryMessages(
        conversationID: "conv_123",
        startTime: 0,
        count: 1000
    )
    
    // 使用批量写入器
    let batchWriter = IMMessageBatchWriter(database: database)
    
    for message in messages {
        batchWriter.addMessage(message)
    }
    
    // 自动批量写入，性能提升 10 倍
    // 1000 条消息：~1.5s（批量）vs ~15s（单条）
}
```

### 3. 网络环境自适应

```swift
// 根据网络类型调整批量写入策略
class AdaptiveBatchWriter {
    var batchWriter: IMMessageBatchWriter!
    
    func setupForNetwork(_ networkType: IMNetworkStatus) {
        switch networkType {
        case .wifi:
            // WiFi：延迟低，可以适当放宽
            batchWriter = IMMessageBatchWriter(
                database: database,
                batchSize: 100,
                maxWaitTime: 0.2
            )
            
        case .cellular:
            // 4G/5G：优化批量写入
            batchWriter = IMMessageBatchWriter(
                database: database,
                batchSize: 50,
                maxWaitTime: 0.1
            )
            
        default:
            // 弱网：更激进的批量策略
            batchWriter = IMMessageBatchWriter(
                database: database,
                batchSize: 20,
                maxWaitTime: 0.05
            )
        }
    }
}
```

### 4. 应用生命周期管理

```swift
// AppDelegate
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 设置一致性保障
        IMConsistencyGuard.shared.setDatabase(IMClient.shared.database)
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // ⚠️ 重要：确保所有异步消息已写入
        IMConsistencyGuard.shared.ensureAllWritten()
        
        print("✅ 所有消息已持久化")
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // 内存警告时，立即刷新缓冲区
        IMConsistencyGuard.shared.ensureAllWritten()
    }
}
```

---

## 📊 性能监控

### 启用性能日志

```swift
// 在 DEBUG 模式下，性能日志会自动打印

// 发送消息
messageManager.sendMessageFast(message)
// 输出：
// ⚡ [PERF] sendMessageFast: 3.45ms
//   - cache: 0.82ms
//   - notify: 1.23ms
//   - enqueue: 0.95ms
//   - db: async (non-blocking)

// 接收消息
messageManager.handleReceivedMessageFast(message)
// 输出：
// ⚡ [PERF] handleReceivedMessageFast (sync): 4.78ms
//   - direction: 0.05ms
//   - cache: 0.95ms
//   - notify: 2.13ms
//   - ack: 1.65ms
```

### 集成分析系统

```swift
extension IMLogger {
    func recordLatency(_ latency: TimeInterval, messageType: IMMessageType) {
        // 上报到你的分析系统
        Analytics.record(event: "message_latency", properties: [
            "latency_ms": latency,
            "message_type": messageType.rawValue
        ])
        
        // 如果延迟过高，记录警告
        if latency > 100 {
            Analytics.record(event: "high_latency_warning", properties: [
                "latency_ms": latency
            ])
        }
    }
}
```

### 端到端延迟测量

```swift
// 在消息中添加时间戳
class IMMessage: Object {
    // ... 其他属性
    
    /// 客户端发送时间（用于计算端到端延迟）
    @Persisted var clientSendTime: Int64 = 0
}

// 发送端
func sendMessage(_ message: IMMessage) {
    message.clientSendTime = Int64(Date().timeIntervalSince1970 * 1000)
    messageManager.sendMessageFast(message)
}

// 接收端
func handleReceivedMessage(_ message: IMMessage) {
    let receiveTime = Int64(Date().timeIntervalSince1970 * 1000)
    let latency = receiveTime - message.clientSendTime
    
    // 记录延迟
    IMLogger.shared.recordLatency(Double(latency), messageType: message.messageType)
    
    if latency < 100 {
        print("✅ 极速消息！延迟 \(latency)ms")
    }
}
```

---

## 🎯 实战案例

### 案例 1：一对一实时聊天

```swift
class ChatService {
    let messageManager: IMMessageManager
    
    func sendTextMessage(_ text: String, to userID: String) {
        // 1. 创建消息
        let message = messageManager.createTextMessage(
            content: text,
            to: userID,
            conversationType: .single
        )
        
        // 2. ⚡ 快速发送（< 5ms）
        messageManager.sendMessageFast(message)
        
        // 3. UI 自动更新（通过监听器）
        // 用户几乎无感知延迟
    }
}

// 性能指标：
// - 用户点击发送 → UI 显示：< 5ms
// - 端到端延迟：< 100ms（在良好网络下）
```

### 案例 2：群聊消息轰炸

```swift
class GroupChatService {
    let batchWriter: IMMessageBatchWriter
    
    func handleBatchMessages(_ messages: [IMMessage]) {
        // 群里同时收到 100 条消息
        
        for message in messages {
            // 1. ✅ 立即显示在 UI
            NotificationCenter.default.post(
                name: .newMessageReceived,
                object: message
            )
            
            // 2. ✅ 添加到批量写入队列
            batchWriter.addMessage(message)
        }
        
        // 自动批量写入：
        // - 单条写入：100 条 × 15ms = 1500ms
        // - 批量写入：100 条 ÷ 50/批 × 30ms = 60ms
        // 性能提升：25 倍！
    }
}
```

### 案例 3：消息同步

```swift
class SyncService {
    func syncOfflineMessages() async {
        // 1. 从服务器拉取离线消息
        let messages = try await fetchOfflineMessages()  // 可能有 1000+ 条
        
        // 2. 使用批量写入器
        let batchWriter = IMMessageBatchWriter(database: database)
        
        for message in messages {
            batchWriter.addMessage(message)
        }
        
        // 3. 强制刷新（确保所有消息已写入）
        batchWriter.flush()
        
        // 性能对比：
        // - 传统方式：1000 条 × 15ms = 15 秒 😱
        // - 批量方式：1000 条 × 1.5ms = 1.5 秒 ⚡
    }
}
```

---

## ⚠️ 注意事项

### 1. 数据一致性

异步写入虽然快，但需要处理数据一致性：

```swift
// ✅ 推荐：应用退出前确保所有消息已写入
func applicationWillTerminate(_ application: UIApplication) {
    IMConsistencyGuard.shared.ensureAllWritten()
}

// ✅ 推荐：关键消息使用同步写入
try messageManager.sendMessage(criticalMessage)

// ✅ 推荐：普通消息使用异步写入
messageManager.sendMessageFast(normalMessage)
```

### 2. 内存管理

```swift
// ❌ 避免：无限制缓存消息
for i in 0..<1_000_000 {
    let message = createMessage()
    messages.append(message)  // 内存爆炸！
}

// ✅ 推荐：使用分页加载
func loadMessages() {
    let pageSize = 20
    let messages = try messageManager.getHistoryMessages(
        conversationID: conversationID,
        startTime: lastLoadTime,
        count: pageSize
    )
}
```

### 3. 错误处理

```swift
// 异步写入可能失败，需要监控
DispatchQueue.global(qos: .utility).async {
    do {
        try database.saveMessage(message)
    } catch {
        // 记录错误
        IMLogger.shared.error("Async save failed: \(error)")
        
        // 重试或上报
        Analytics.record(event: "db_write_error", error: error)
    }
}
```

---

## 🎊 性能指标总结

### 优化前 vs 优化后

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| **发送耗时** | 30ms | 3-5ms | ⚡ 85% ↓ |
| **接收耗时** | 30ms | 4-6ms | ⚡ 80% ↓ |
| **端到端延迟** | 112ms | 82ms | ⚡ 27% ↓ |
| **UI 响应时间** | 40ms | 5ms | ⚡ 87% ↓ |
| **批量写入** | 15ms/条 | 1.5ms/条 | ⚡ 90% ↓ |
| **高并发吞吐** | 100 条/秒 | 1000 条/秒 | ⚡ 10x ↑ |

### 达成目标 ✅

🎯 **端到端延迟 < 100ms** ✅  
🎯 **UI 响应 < 10ms** ✅  
🎯 **高并发支持 > 500 条/秒** ✅

---

## 📚 相关文档

- [性能优化详细设计](./Performance_MessageLatency.md)
- [API 文档](./API.md)
- [消息可靠性](./MessageReliability.md)
- [架构设计](./Architecture.md)

---

**最后更新**：2025-10-24  
**版本**：1.0.0


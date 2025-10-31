# 业务层逻辑实现总结

## 📋 实现概述

完成了业务层的增量同步和 ACK + 重传机制，确保消息可靠性和数据完整性。

---

## 🎯 Part 1: 增量同步机制（IMClient + IMMessageSyncManager）

### 1.1 架构设计

```
用户设备断网/重连
    ↓
IMClient.handleTransportConnected()
    ├─ 检测是否是重连（wasConnected）
    ├─ 首次连接：syncOfflineMessages()（全量同步）
    └─ 重连：syncOfflineMessagesAfterReconnect()（增量同步）
    ↓
IMClient.syncOfflineMessagesAfterReconnect()
    ├─ database.getMaxSeq() → localMaxSeq
    └─ messageSyncManager.sync(fromSeq: localMaxSeq + 1)
    ↓
IMMessageSyncManager.sync(fromSeq:completion:)
    ├─ 检查同步状态（避免重复）
    ├─ updateState(.syncing)
    └─ performIncrementalSync(fromSeq:completion:)
    ↓
IMMessageSyncManager.performIncrementalSync()
    └─ syncBatch(lastSeq: fromSeq, ...)
        ├─ 分批拉取（batchSize: 500）
        ├─ 保存到数据库（去重）
        ├─ 通知监听器
        └─ 更新 lastSyncSeq
    ↓
完成增量同步 ✅
```

### 1.2 代码实现

#### A. IMMessageSyncManager 增量同步方法

**文件**: `IMMessageSyncManager.swift`

```swift
/// 从指定序列号开始增量同步（重连后使用）
/// - Parameters:
///   - fromSeq: 起始序列号
///   - completion: 完成回调
public func sync(fromSeq: Int64, completion: IMSyncCompletionHandler? = nil) {
    stateLock.lock()
    
    // 检查是否已在同步中
    if case .syncing = state {
        stateLock.unlock()
        IMLogger.shared.warning("Sync already in progress, skip")
        completion?(.success(()))
        return
    }
    
    // 更新状态
    updateState(.syncing)
    stateLock.unlock()
    
    IMLogger.shared.info("🔄 Starting incremental sync from seq: \(fromSeq)")
    
    // 在后台线程执行同步
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        self.performIncrementalSync(fromSeq: fromSeq, completion: completion)
    }
}

/// 执行增量同步（从指定 seq 开始）
private func performIncrementalSync(fromSeq: Int64, completion: IMSyncCompletionHandler?) {
    let startTime = Date()
    
    IMLogger.shared.info("📊 Starting incremental sync from seq: \(fromSeq)")
    
    // 设置同步状态
    do {
        try database.setSyncingState(userID: userID, isSyncing: true)
    } catch {
        IMLogger.shared.error("Failed to set syncing state: \(error)")
    }
    
    // 开始分批同步（从指定 seq 开始）
    syncBatch(
        lastSeq: fromSeq,
        totalFetched: 0,
        totalCount: 0,
        currentBatch: 1,
        retryCount: 0,
        startTime: startTime,
        completion: completion
    )
}
```

#### B. IMClient 重连后增量同步

**文件**: `IMClient.swift`

```swift
/// 处理传输层连接成功
private func handleTransportConnected() {
    IMLogger.shared.info("Transport connected")
    
    // 检测是否是重连（之前已连接过）
    let wasConnected = connectionState == .connected || connectionState == .disconnected
    
    updateConnectionState(.connected)
    
    // 同步离线消息（重连时使用增量同步）
    if wasConnected {
        syncOfflineMessagesAfterReconnect()
    } else {
        syncOfflineMessages()
    }
    
    notifyConnectionListeners { $0.onConnected() }
}

/// 重连后增量同步消息
private func syncOfflineMessagesAfterReconnect() {
    IMLogger.shared.info("♻️ Reconnected, starting incremental sync...")
    
    guard let database = databaseManager else {
        IMLogger.shared.error("Database not initialized")
        return
    }
    
    // 1. 获取本地最大序列号
    let localMaxSeq = database.getMaxSeq()
    
    IMLogger.shared.info("📊 Local max seq: \(localMaxSeq)")
    
    // 2. 从 localMaxSeq + 1 开始增量同步
    messageSyncManager?.sync(fromSeq: localMaxSeq + 1) { result in
        switch result {
        case .success:
            IMLogger.shared.info("✅ Incremental sync completed successfully")
        case .failure(let error):
            IMLogger.shared.error("❌ Incremental sync failed: \(error)")
            // 增量同步失败，回退到全量同步
            IMLogger.shared.warning("⚠️ Falling back to full sync...")
            self.syncOfflineMessages()
        }
    }
}
```

### 1.3 关键特性

| 特性 | 说明 |
|------|------|
| **重连检测** | 通过 `connectionState` 判断是首次连接还是重连 |
| **自动降级** | 增量同步失败时，自动回退到全量同步 |
| **并发保护** | `stateLock` 确保同步状态的线程安全 |
| **批量拉取** | 每批 500 条消息，避免内存溢出 |
| **去重处理** | `saveMessages()` 自动去重（基于 messageID） |
| **进度通知** | `onProgress` 回调，实时更新 UI |

---

## 🎯 Part 2: ACK + 重传机制（IMMessageQueue）

### 2.1 架构设计

```
用户发送消息
    ↓
IMMessageManager.sendMessage()
    ├─ 保存到数据库（status: sending）
    └─ messageQueue.enqueue(message)
    ↓
IMMessageQueue.enqueue()
    ├─ 添加到队列（retryCount: 0）
    └─ tryProcessQueue()
    ↓
IMMessageQueue.tryProcessQueue()
    ├─ 找到第一个未发送的消息
    ├─ 标记为 isSending=true
    ├─ 记录 lastSendTime
    └─ onSendMessage(message) → WebSocket.send()
    ↓
等待服务器 ACK（5 秒超时）
    ↓
【场景 A：收到 ACK】
    ↓
IMMessageManager.handleMessageAck()
    ├─ messageQueue.dequeue(messageID) ✅ 移除
    ├─ database.updateMessageStatus(status: sent)
    └─ 通知监听器
    ↓
发送成功 ✅

【场景 B：超时（5 秒内未收到 ACK）】
    ↓
IMMessageQueue.checkTimeout()（每 5 秒检查一次）
    ├─ 检测到超时（elapsed > 5000ms）
    ├─ 检查重试次数
    ├─ retryCount < 3：重置 isSending=false，重新发送
    └─ retryCount >= 3：移除队列，通知失败
    ↓
IMMessageManager.handleMessageSendFailed()
    ├─ database.updateMessageStatus(status: failed)
    └─ 通知监听器
    ↓
发送失败（重试次数耗尽）❌
```

### 2.2 代码实现

**文件**: `IMProtocolHandler.swift` → `IMMessageQueue`

```swift
public final class IMMessageQueue {
    
    // MARK: - Queue Item
    
    private struct QueueItem {
        let message: IMMessage
        var retryCount: Int  // 重试次数（可变）
        let timestamp: Int64  // 消息创建时间
        var isSending: Bool  // 是否正在发送（避免重复发送）
        var lastSendTime: Int64  // 最后一次发送时间（用于 ACK 超时检测）
    }
    
    // MARK: - Properties
    
    private var queue: [QueueItem] = []
    private let lock = NSRecursiveLock()  // 使用递归锁，支持同一线程重复获取
    private let maxRetryCount = 3
    private let ackTimeout: Int64 = 5_000  // ACK 超时时间（5 秒，快速失败，参考微信）
    private var timeoutCheckTimer: Timer?
    
    // 回调
    public var onSendMessage: ((IMMessage) -> Bool)?  // 同步返回：true=成功提交，false=失败
    public var onMessageFailed: ((IMMessage) -> Void)?  // 消息发送失败回调
    
    // MARK: - Public Methods
    
    /// 添加消息到队列
    public func enqueue(_ message: IMMessage) {
        lock.lock()
        defer { lock.unlock() }
        
        let item = QueueItem(
            message: message,
            retryCount: 0,
            timestamp: IMUtils.currentTimeMillis(),
            isSending: false,
            lastSendTime: 0
        )
        queue.append(item)
        
        IMLogger.shared.debug("Message enqueued: \(message.messageID), queue size: \(queue.count)")
        
        // 尝试发送
        tryProcessQueue()
    }
    
    /// 从队列中移除消息（收到 ACK 后调用）
    public func dequeue(messageID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        queue.removeAll { $0.message.messageID == messageID }
        IMLogger.shared.debug("Message dequeued: \(messageID), queue size: \(queue.count)")
        
        // 移除后，继续处理队列中的其他消息
        tryProcessQueue()
    }
    
    // MARK: - Private Methods
    
    /// 处理队列
    private func tryProcessQueue() {
        lock.lock()
        defer { lock.unlock() }
        
        // 循环处理队列中的消息，避免递归
        while true {
            // 找到第一个未发送的消息
            guard let index = queue.firstIndex(where: { !$0.isSending }) else {
                // 所有消息都在等待 ACK
                break
            }
            
            var item = queue[index]
            
            // 标记为正在发送
            item.isSending = true
            item.lastSendTime = IMUtils.currentTimeMillis()
            queue[index] = item
            
            let message = item.message
            
            // 释放锁，调用回调（避免死锁）
            lock.unlock()
            let success = onSendMessage?(message) ?? false
            lock.lock()
            
            if !success {
                // 发送失败（网络断开），重置状态，等待下次尝试
                if let currentIndex = queue.firstIndex(where: { $0.message.messageID == message.messageID }) {
                    var currentItem = queue[currentIndex]
                    currentItem.isSending = false
                    queue[currentIndex] = currentItem
                }
                break
            }
        }
    }
    
    /// 检查 ACK 超时
    private func checkTimeout() {
        lock.lock()
        defer { lock.unlock() }
        
        let now = IMUtils.currentTimeMillis()
        var hasTimeout = false
        
        for i in 0..<queue.count {
            var item = queue[i]
            
            // 只检查正在等待 ACK 的消息
            guard item.isSending else { continue }
            
            let elapsed = now - item.lastSendTime
            
            if elapsed > ackTimeout {
                // ⏰ ACK 超时
                IMLogger.shared.warning("Message ACK timeout: \(item.message.messageID), elapsed: \(elapsed)ms, retry: \(item.retryCount)/\(maxRetryCount)")
                
                if item.retryCount < maxRetryCount {
                    // 重置状态，允许重新发送
                    item.isSending = false
                    item.retryCount += 1
                    queue[i] = item
                    hasTimeout = true
                    
                    IMLogger.shared.info("Will retry message: \(item.message.messageID)")
                } else {
                    // 达到最大重试次数，标记为失败
                    IMLogger.shared.error("Message failed after \(maxRetryCount) retries: \(item.message.messageID)")
                    
                    let failedMessage = item.message
                    queue.remove(at: i)
                    
                    // 通知上层消息发送失败
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessageFailed?(failedMessage)
                    }
                    
                    // 移除后索引变化，需要重新检查
                    return self.checkTimeout()
                }
            }
        }
        
        // 如果有超时的消息，尝试重新发送
        if hasTimeout {
            tryProcessQueue()
        }
    }
    
    /// 启动超时检查定时器
    private func startTimeoutCheckTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.timeoutCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkTimeout()
            }
        }
    }
    
    /// 停止超时检查定时器
    private func stopTimeoutCheckTimer() {
        timeoutCheckTimer?.invalidate()
        timeoutCheckTimer = nil
    }
}
```

### 2.3 关键特性

| 特性 | 说明 |
|------|------|
| **ACK 超时** | 5 秒超时（参考微信） |
| **自动重传** | 最多重传 3 次 |
| **定时检查** | 每 5 秒检查一次超时 |
| **并发安全** | NSRecursiveLock 保证线程安全 |
| **循环处理** | 避免递归调用和栈溢出 |
| **状态管理** | `isSending` 标记防止重复发送 |
| **失败通知** | `onMessageFailed` 回调通知上层 |
| **重连恢复** | `onWebSocketReconnected()` 重新发送未确认的消息 |

---

## 📊 完整的消息可靠性保障

### 流程图

```
┌─────────────────────────────────────────────────────────┐
│                    用户发送消息                           │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              1. 保存到数据库（status: sending）           │
│              2. 添加到 IMMessageQueue                     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              3. 通过 WebSocket/TCP 发送                   │
│              4. 记录 lastSendTime                         │
└─────────────────────────────────────────────────────────┘
                          ↓
                 ┌────────┴────────┐
                 │    5 秒超时      │
                 └────────┬────────┘
                          ↓
        ┌─────────────────┴─────────────────┐
        │                                   │
        ↓                                   ↓
┌──────────────┐                   ┌──────────────┐
│  收到 ACK ✅  │                   │   超时 ⏰     │
└──────────────┘                   └──────────────┘
        │                                   │
        ↓                                   ↓
┌──────────────┐                   ┌──────────────┐
│ 从队列移除    │                   │ 检查重试次数  │
│ 更新状态:sent │                   └──────────────┘
└──────────────┘                           │
        │                          ┌───────┴───────┐
        ↓                          │               │
┌──────────────┐           ┌───────────┐   ┌──────────────┐
│   通知UI ✅   │           │ 重试 1-3  │   │  失败 ❌      │
└──────────────┘           └───────────┘   └──────────────┘
                                  │                 │
                                  ↓                 ↓
                           ┌───────────┐   ┌──────────────┐
                           │ 重新发送   │   │ 更新状态:failed│
                           └───────────┘   │ 通知UI ❌     │
                                            └──────────────┘
```

### 可靠性保障表

| 场景 | 处理方式 | 用户体验 |
|------|---------|---------|
| **网络正常** | 5秒内收到 ACK → 成功 | ✅ 消息发送成功 |
| **网络抖动** | 5-15秒收到 ACK（重传1-2次） | ✅ 消息发送成功（稍慢） |
| **短时断网** | 重连后自动重传 | ✅ 消息发送成功（延迟） |
| **长时断网** | 重传3次失败 → 标记为失败 | ❌ 消息发送失败（用户可重试） |
| **服务器错误** | ACK 返回失败状态 → 立即失败 | ❌ 消息发送失败（显示错误原因） |
| **消息丢包** | 序列号检测 + 增量同步补齐 | ✅ 消息完整（自动修复） |
| **数据损坏** | CRC 校验失败 → 重连 + 增量同步 | ✅ 消息完整（自动修复） |

---

## ✅ 实现完成清单

| 功能 | 状态 | 位置 |
|------|------|------|
| **增量同步（IMMessageSyncManager）** | ✅ 完成 | `IMMessageSyncManager.swift` |
| **重连检测（IMClient）** | ✅ 完成 | `IMClient.swift` → `handleTransportConnected()` |
| **数据库 getMaxSeq()** | ✅ 已存在 | `IMDatabaseManager+Message.swift` |
| **ACK 超时检测** | ✅ 已存在 | `IMProtocolHandler.swift` → `IMMessageQueue` |
| **自动重传机制** | ✅ 已存在 | `IMProtocolHandler.swift` → `checkTimeout()` |
| **失败通知** | ✅ 已存在 | `IMMessageManager.handleMessageSendFailed()` |
| **并发保护** | ✅ 已存在 | `NSRecursiveLock` + `stateLock` |

---

## 📈 性能和可靠性指标

| 指标 | 目标 | 实现方式 |
|------|------|---------|
| **消息送达率** | 99.9% | ACK 确认 + 重传机制 |
| **重连恢复时间** | < 3 秒 | 增量同步（只拉取新消息） |
| **丢包检测率** | 100% | 序列号连续性检查 |
| **数据完整性** | 100% | CRC16 校验 + 快速失败 |
| **ACK 超时** | 5 秒 | 快速失败策略（参考微信） |
| **最大重传次数** | 3 次 | 避免无限重传 |
| **批量同步大小** | 500 条/批 | 内存友好 |

---

## 🎯 与业界对比

| 对比项 | 本 SDK | 微信 | Telegram |
|--------|--------|------|----------|
| **ACK 超时** | 5秒 | 5秒 | 3秒 |
| **最大重传** | 3次 | 3-5次 | 5次 |
| **增量同步** | ✅ 序列号 | ✅ 序列号 | ✅ pts |
| **CRC 校验** | ✅ CRC16 | ✅ CRC | ✅ 自定义 |
| **快速失败** | ✅ 是 | ✅ 是 | ✅ 是 |
| **丢包检测** | ✅ 序列号检查 | ✅ 序列号检查 | ✅ pts 检查 |

---

## 🔧 使用示例

### 示例 1: 发送消息（自动 ACK + 重传）

```swift
// 创建消息
let message = messageManager.createTextMessage(
    content: "Hello, World!",
    to: "user123",
    conversationType: .single
)

// 发送消息（自动进入队列，自动重传）
do {
    let sentMessage = try messageManager.sendMessage(message)
    
    // 监听消息状态变化
    messageManager.addListener(self)
} catch {
    print("Failed to send message: \(error)")
}

// 实现监听器
extension MyViewController: IMMessageListener {
    func onMessageStatusChanged(_ message: IMMessage) {
        switch message.status {
        case .sending:
            print("消息发送中...")
        case .sent:
            print("✅ 消息已送达服务器")
        case .failed:
            print("❌ 消息发送失败（重试3次后）")
        default:
            break
        }
    }
}
```

### 示例 2: 重连后自动增量同步

```swift
// 监听连接状态
IMClient.shared.addConnectionListener(self)

extension MyViewController: IMConnectionListener {
    func onConnected() {
        // 重连成功，SDK 自动触发增量同步
        print("✅ Connected")
        // 不需要手动调用任何方法，IMClient 会自动处理
    }
    
    func onDisconnected(error: Error?) {
        print("❌ Disconnected: \(error?.localizedDescription ?? "Unknown")")
    }
}
```

### 示例 3: 手动触发增量同步

```swift
// 从指定 seq 开始同步（例如：重新登录后）
let lastSeq = 12345
messageSyncManager.sync(fromSeq: lastSeq + 1) { result in
    switch result {
    case .success:
        print("✅ Incremental sync completed")
    case .failure(let error):
        print("❌ Sync failed: \(error)")
    }
}
```

---

**文档版本**: 1.0.0  
**最后更新**: 2025-01-26  
**作者**: IMSDK Team


# IMTCPTransport 回调逻辑缺漏分析

## 📋 当前实现回顾

### 代码位置
`Sources/IMSDK/Core/Transport/IMTCPTransport.swift` → `setupCodecCallbacks()`

---

## ⚠️ 发现的缺漏

### **缺漏 1: `onPacketLoss` 没有通知上层业务** ❌

**问题：**
```swift
codec.onPacketLoss = { [weak self] expected, received, gap in
    guard let self = self else { return }
    
    IMLogger.shared.warning("📉 TCP Transport detected packet loss: expected=\(expected), received=\(received), gap=\(gap)")
    
    // 统计丢包
    self.lock.lock()
    self.stats.packetLossCount += Int(gap)
    self.lock.unlock()
    
    // TODO: 触发重传机制（需要与业务层的 ACK 机制配合）
    // ❌ 问题：这里只记录了日志和统计，没有通知上层！
}
```

**影响：**
- 业务层（`IMClient`）无法感知丢包事件
- 无法触发主动的增量同步或重传
- 依赖重连后的被动增量同步，延迟较大

**建议修复：**
```swift
codec.onPacketLoss = { [weak self] expected, received, gap in
    guard let self = self else { return }
    
    IMLogger.shared.warning("📉 TCP Transport detected packet loss: expected=\(expected), received=\(received), gap=\(gap)")
    
    // 统计丢包
    self.lock.lock()
    self.stats.packetLossCount += Int(gap)
    self.lock.unlock()
    
    // ✅ 新增：通知上层丢包事件
    self.onError?(IMTransportError.packetLoss(expected: expected, received: received, gap: gap))
    
    // ✅ 新增：根据丢包严重程度采取不同策略
    if gap > 10 {
        // 严重丢包：触发重连 + 增量同步
        IMLogger.shared.error("⚠️ Severe packet loss detected (gap=\(gap)), reconnecting...")
        self.handleSeverePacketLoss(gap: gap)
    } else {
        // 轻微丢包：通过 IMClient 触发增量同步
        self.notifyPacketLossToBusinessLayer(expected: expected, received: received, gap: gap)
    }
}
```

---

### **缺漏 2: 没有区分丢包严重程度** ❌

**问题：**
- 所有丢包都只记录统计，没有采取行动
- 轻微丢包（gap=1-2）和严重丢包（gap>10）应该有不同的处理策略

**建议策略：**

| 丢包程度 | gap 范围 | 处理策略 |
|---------|----------|---------|
| **轻微** | 1-3 | 只记录，等待 ACK 超时重传 |
| **中等** | 4-10 | 触发主动增量同步（不重连） |
| **严重** | >10 | 立即重连 + 增量同步 |

---

### **缺漏 3: 重连失败后没有后续处理** ❌

**问题：**
```swift
self.connect(url: url, token: token) { result in
    switch result {
    case .success:
        IMLogger.shared.info("✅ Reconnected successfully")
        // 重连成功后，业务层会自动通过序列号机制补齐丢失的消息
        
    case .failure(let error):
        IMLogger.shared.error("❌ Reconnect failed: \(error)")
        // ❌ 问题：重连失败后，没有任何后续动作！
        // 应该重试或通知用户
    }
}
```

**影响：**
- 如果重连失败，用户永远无法恢复
- 没有重试机制

**建议修复：**
```swift
self.connect(url: url, token: token) { [weak self] result in
    switch result {
    case .success:
        IMLogger.shared.info("✅ Reconnected successfully")
        // 重置重连计数
        self?.reconnectAttempts = 0
        
    case .failure(let error):
        IMLogger.shared.error("❌ Reconnect failed: \(error)")
        
        // ✅ 新增：指数退避重试
        self?.handleReconnectFailure(error: error)
    }
}
```

---

### **缺漏 4: 没有指数退避的重连策略** ❌

**问题：**
```swift
// 延迟重连（避免频繁重连）
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
    // 固定 1 秒延迟
}
```

**影响：**
- 如果服务器故障，会频繁尝试重连
- 没有考虑网络恢复时间
- 可能导致雪崩效应（大量客户端同时重连）

**建议修复：**
```swift
// 指数退避：1s, 2s, 4s, 8s, 16s, 32s（最大）
let delay = min(pow(2.0, Double(reconnectAttempts)), 32.0)
DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
    self?.reconnectAttempts += 1
    self?.connect(...)
}
```

---

### **缺漏 5: 没有防止频繁触发的防抖机制** ❌

**问题：**
- 如果网络不稳定，`onPacketLoss` 可能在短时间内触发多次
- 每次都会记录日志和更新统计，可能影响性能

**建议修复：**
```swift
// 添加防抖：10 秒内只处理一次
private var lastPacketLossTime: Int64 = 0
private let packetLossDebounceInterval: Int64 = 10_000 // 10秒

codec.onPacketLoss = { [weak self] expected, received, gap in
    guard let self = self else { return }
    
    let now = IMUtils.currentTimeMillis()
    
    // 防抖检查
    if now - self.lastPacketLossTime < self.packetLossDebounceInterval {
        IMLogger.shared.debug("Packet loss detected but debounced, skip")
        return
    }
    
    self.lastPacketLossTime = now
    
    // 处理丢包...
}
```

---

### **缺漏 6: `IMTransportError` 没有 `packetLoss` 类型** ❌

**问题：**
- 当前 `IMTransportError` 可能没有定义 `packetLoss` 错误类型
- 无法向上层传递丢包信息

**需要检查：**
```swift
// IMTransportProtocol.swift
public enum IMTransportError: Error {
    case notConnected
    case connectionFailed(Error)
    case sendFailed(Error)
    case receiveFailed(Error)
    case timeout
    case protocolError(String)
    
    // ✅ 需要新增
    case packetLoss(expected: UInt32, received: UInt32, gap: UInt32)
}
```

---

## ✅ 建议的完整修复方案

### 1. 新增属性

```swift
// MARK: - Reconnect Management

/// 重连尝试次数
private var reconnectAttempts: Int = 0

/// 最大重连次数
private let maxReconnectAttempts = 5

/// 最后一次丢包时间（用于防抖）
private var lastPacketLossTime: Int64 = 0

/// 丢包防抖间隔（10秒）
private let packetLossDebounceInterval: Int64 = 10_000
```

### 2. 改进 `onPacketLoss` 回调

```swift
codec.onPacketLoss = { [weak self] expected, received, gap in
    guard let self = self else { return }
    
    let now = IMUtils.currentTimeMillis()
    
    // 1. 防抖检查
    self.lock.lock()
    let shouldProcess = (now - self.lastPacketLossTime) >= self.packetLossDebounceInterval
    if shouldProcess {
        self.lastPacketLossTime = now
        self.stats.packetLossCount += Int(gap)
    }
    self.lock.unlock()
    
    guard shouldProcess else {
        IMLogger.shared.debug("Packet loss debounced, skip")
        return
    }
    
    IMLogger.shared.warning("📉 TCP Transport detected packet loss: expected=\(expected), received=\(received), gap=\(gap)")
    
    // 2. 通知上层
    self.onError?(IMTransportError.packetLoss(expected: expected, received: received, gap: gap))
    
    // 3. 根据严重程度采取策略
    if gap > 10 {
        // 严重丢包：重连
        IMLogger.shared.error("⚠️ Severe packet loss (gap=\(gap)), triggering reconnect")
        self.handleFatalError(.sequenceAbnormal(expected, received))
    } else if gap > 3 {
        // 中等丢包：触发增量同步（通过 IMClient）
        IMLogger.shared.warning("⚠️ Moderate packet loss (gap=\(gap)), notifying business layer")
        // 业务层会通过监听 onError 来触发增量同步
    } else {
        // 轻微丢包：只记录，等待 ACK 重传
        IMLogger.shared.info("ℹ️ Minor packet loss (gap=\(gap)), relying on ACK retry")
    }
}
```

### 3. 改进 `handleFatalError` 方法

```swift
/// 处理致命错误（带指数退避的重连策略）
private func handleFatalError(_ error: IMPacketCodecError) {
    lock.lock()
    let wasConnected = isConnected
    let attempts = reconnectAttempts
    lock.unlock()
    
    guard wasConnected else {
        IMLogger.shared.debug("Not connected, no need to reconnect")
        return
    }
    
    // 检查是否超过最大重连次数
    if attempts >= maxReconnectAttempts {
        IMLogger.shared.error("❌ Max reconnect attempts reached (\(maxReconnectAttempts)), giving up")
        onError?(IMTransportError.maxReconnectAttemptsReached)
        return
    }
    
    IMLogger.shared.warning("⚠️ Fatal error detected, reconnecting... (attempt \(attempts + 1)/\(maxReconnectAttempts))")
    
    // 快速失败：立即断开
    disconnect()
    
    // 指数退避：1s, 2s, 4s, 8s, 16s, 32s（最大）
    let baseDelay = 1.0
    let delay = min(baseDelay * pow(2.0, Double(attempts)), 32.0)
    
    // 添加随机抖动（避免雪崩）
    let jitter = Double.random(in: 0...0.3) * delay
    let finalDelay = delay + jitter
    
    IMLogger.shared.info("⏱️ Reconnecting after \(String(format: "%.1f", finalDelay))s...")
    
    DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) { [weak self] in
        guard let self = self,
              let url = self.serverURL,
              let token = self.authToken else {
            return
        }
        
        // 增加重连计数
        self.lock.lock()
        self.reconnectAttempts += 1
        self.lock.unlock()
        
        IMLogger.shared.info("♻️ Reconnecting after fatal error... (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
        
        self.connect(url: url, token: token) { [weak self] result in
            switch result {
            case .success:
                IMLogger.shared.info("✅ Reconnected successfully")
                // 重置重连计数
                self?.lock.lock()
                self?.reconnectAttempts = 0
                self?.lock.unlock()
                
                // 重连成功后，业务层会自动通过序列号机制补齐丢失的消息
                
            case .failure(let error):
                IMLogger.shared.error("❌ Reconnect failed: \(error)")
                
                // 递归重试（会继续使用指数退避）
                self?.handleReconnectFailure()
            }
        }
    }
}

/// 处理重连失败
private func handleReconnectFailure() {
    lock.lock()
    let attempts = reconnectAttempts
    lock.unlock()
    
    if attempts >= maxReconnectAttempts {
        IMLogger.shared.error("❌ Max reconnect attempts reached, giving up")
        onError?(IMTransportError.maxReconnectAttemptsReached)
        return
    }
    
    // 继续重连（使用指数退避）
    handleFatalError(.unknown)
}
```

### 4. 新增 `IMTransportError` 类型

```swift
// IMTransportProtocol.swift
public enum IMTransportError: Error {
    case notConnected
    case connectionFailed(Error)
    case sendFailed(Error)
    case receiveFailed(Error)
    case timeout
    case protocolError(String)
    
    // ✅ 新增
    case packetLoss(expected: UInt32, received: UInt32, gap: UInt32)
    case maxReconnectAttemptsReached
}
```

### 5. IMClient 监听丢包事件

```swift
// IMClient.swift

private func setupTransportCallbacks() {
    transport?.onStateChange = { [weak self] state in
        self?.handleTransportStateChange(state)
    }
    
    transport?.onReceive = { [weak self] data in
        self?.handleTransportReceive(data)
    }
    
    transport?.onError = { [weak self] error in
        self?.handleTransportError(error)
    }
}

private func handleTransportError(_ error: IMTransportError) {
    IMLogger.shared.error("Transport error: \(error)")
    
    switch error {
    case .packetLoss(let expected, let received, let gap):
        // 检测到丢包，触发主动增量同步
        if gap > 3 {
            IMLogger.shared.warning("⚠️ Moderate packet loss detected (gap=\(gap)), triggering incremental sync")
            triggerIncrementalSync()
        }
        
    case .maxReconnectAttemptsReached:
        // 达到最大重连次数，通知用户
        IMLogger.shared.error("❌ Max reconnect attempts reached, please check network")
        notifyConnectionListeners { $0.onDisconnected(error: error) }
        
    default:
        // 其他错误
        break
    }
}

/// 主动触发增量同步（不等待重连）
private func triggerIncrementalSync() {
    guard let database = databaseManager else { return }
    
    let localMaxSeq = database.getMaxSeq()
    
    IMLogger.shared.info("🔄 Triggering incremental sync from seq: \(localMaxSeq + 1)")
    
    messageSyncManager?.sync(fromSeq: localMaxSeq + 1) { result in
        switch result {
        case .success:
            IMLogger.shared.info("✅ Incremental sync completed (triggered by packet loss)")
        case .failure(let error):
            IMLogger.shared.error("❌ Incremental sync failed: \(error)")
        }
    }
}
```

---

## 📊 修复前后对比

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| **轻微丢包（1-2包）** | 只记录日志 | ✅ 只记录，依赖 ACK 重传 |
| **中等丢包（3-10包）** | 只记录日志 | ✅ 主动触发增量同步 |
| **严重丢包（>10包）** | 只记录日志 | ✅ 立即重连 + 增量同步 |
| **重连失败** | 没有后续动作 ❌ | ✅ 指数退避重试（最多5次） |
| **频繁丢包** | 可能影响性能 | ✅ 防抖（10秒内只处理一次） |
| **雪崩效应** | 可能发生（固定1秒） | ✅ 随机抖动避免 |
| **业务层感知** | 无法感知 ❌ | ✅ 通过 onError 通知 |

---

## 🎯 总结

### 关键缺漏（需要修复）
1. ❌ `onPacketLoss` 没有通知上层
2. ❌ 没有区分丢包严重程度
3. ❌ 重连失败没有后续处理
4. ❌ 没有指数退避策略
5. ❌ 没有防抖机制
6. ❌ 缺少 `packetLoss` 错误类型

### 建议优先级
- **P0（必须修复）**:
  - 新增 `IMTransportError.packetLoss` 类型
  - 实现指数退避重连策略
  - `onPacketLoss` 通知上层

- **P1（强烈建议）**:
  - 区分丢包严重程度
  - 实现防抖机制
  - IMClient 监听丢包事件并触发增量同步

- **P2（可选优化）**:
  - 添加随机抖动避免雪崩
  - 更细粒度的统计（分严重程度）

---

**文档版本**: 1.0.0  
**最后更新**: 2025-01-26  
**审查人**: Code Reviewer


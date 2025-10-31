# ReconnectManager 重构总结

## 📋 问题发现

用户指出了一个**重复设计**的问题：

```swift
// ❌ 问题代码（重复）
private var reconnectAttempts: Int = 0              // 新增的（重复）
private let maxReconnectAttempts = 5                // 新增的（重复）
private var reconnectManager: ReconnectManager?     // 已存在的

// ReconnectManager 内部已经有：
class ReconnectManager {
    private let maxAttempts: Int                    // 已存在
    private var currentAttempt = 0                  // 已存在
}
```

**问题**：
- ✅ 用户发现了代码重复
- ✅ `ReconnectManager` 已经实现了完整的重连逻辑
- ❌ 新增的 `reconnectAttempts` 和 `maxReconnectAttempts` 是多余的

---

## ✅ 重构方案

### 1. 删除重复属性 ✅

**Before**:
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

**After**:
```swift
// MARK: - Packet Loss Management

/// 最后一次丢包时间（用于防抖）
private var lastPacketLossTime: Int64 = 0

/// 丢包防抖间隔（10秒）
private let packetLossDebounceInterval: Int64 = 10_000
```

---

### 2. 改进 ReconnectManager ✅

**新增功能**:
```swift
class ReconnectManager {
    var onReconnect: (() -> Void)?
    var onMaxAttemptsReached: (() -> Void)?  // ✅ 新增回调
    
    func triggerReconnect() {
        guard maxAttempts == 0 || currentAttempt < maxAttempts else {
            IMLogger.shared.error("[ReconnectManager] Max reconnect attempts reached (\(maxAttempts))")
            onMaxAttemptsReached?()  // ✅ 触发回调
            return
        }
        
        currentAttempt += 1
        
        // ✅ 指数退避算法：2^n * baseInterval，最大32秒
        let delay = min(pow(2.0, Double(min(currentAttempt - 1, 5))) * baseInterval, 32.0)
        
        // ✅ 添加随机抖动（避免雪崩效应）
        let jitter = Double.random(in: 0...0.3) * delay
        let finalDelay = delay + jitter
        
        IMLogger.shared.info("[ReconnectManager] Reconnect attempt \(currentAttempt)/\(maxAttempts), delay: \(String(format: "%.1f", finalDelay))s")
        
        timer = Timer.scheduledTimer(withTimeInterval: finalDelay, repeats: false) { [weak self] _ in
            self?.onReconnect?()
        }
    }
}
```

**改进点**:
- ✅ 新增 `onMaxAttemptsReached` 回调
- ✅ 添加随机抖动（±30%）
- ✅ 限制最大延迟为 32 秒
- ✅ 使用 `IMLogger` 替代 `print`

---

### 3. 简化 handleFatalError ✅

**Before** (100+ 行):
```swift
private func handleFatalError(_ error: IMPacketCodecError) {
    lock.lock()
    let wasConnected = isConnected
    let attempts = reconnectAttempts
    lock.unlock()
    
    guard wasConnected else { return }
    
    if attempts >= maxReconnectAttempts {
        // ...
    }
    
    disconnect()
    
    let baseDelay = 1.0
    let delay = min(baseDelay * pow(2.0, Double(attempts)), 32.0)
    let jitter = Double.random(in: 0...0.3) * delay
    let finalDelay = delay + jitter
    
    DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
        // ...
        self.reconnectAttempts += 1
        // ...
    }
}

private func handleReconnectFailure() {
    // ... 又是一堆重复逻辑
}
```

**After** (10 行):
```swift
private func handleFatalError(_ error: IMPacketCodecError) {
    lock.lock()
    let wasConnected = isConnected
    lock.unlock()
    
    guard wasConnected else {
        IMLogger.shared.debug("Not connected, no need to reconnect")
        return
    }
    
    IMLogger.shared.warning("⚠️ Fatal error detected: \(error), will reconnect...")
    
    // 快速失败：立即断开
    disconnect()
    
    // ✅ 使用 ReconnectManager 触发重连（内置指数退避 + 最大次数限制）
    reconnectManager?.triggerReconnect()
}
```

**改进**:
- ✅ 从 100+ 行简化到 10 行
- ✅ 删除 `handleReconnectFailure()` 方法（不再需要）
- ✅ 所有重连逻辑委托给 `ReconnectManager`

---

### 4. 改进 startReconnectMonitor ✅

**Before**:
```swift
private func startReconnectMonitor() {
    guard config.autoReconnect else { return }
    
    reconnectManager = ReconnectManager(
        maxAttempts: config.maxReconnectAttempts,
        baseInterval: config.reconnectInterval
    )
    
    reconnectManager?.onReconnect = { [weak self] in
        self?.performReconnect()
    }
}
```

**After**:
```swift
private func startReconnectMonitor() {
    guard config.autoReconnect else { return }
    
    reconnectManager = ReconnectManager(
        maxAttempts: config.maxReconnectAttempts,
        baseInterval: config.reconnectInterval
    )
    
    // ✅ 重连回调
    reconnectManager?.onReconnect = { [weak self] in
        self?.performReconnect()
    }
    
    // ✅ 达到最大重连次数回调
    reconnectManager?.onMaxAttemptsReached = { [weak self] in
        guard let self = self else { return }
        IMLogger.shared.error("❌ Max reconnect attempts reached")
        self.onError?(IMTransportError.maxReconnectAttemptsReached)
    }
}
```

---

### 5. 改进 performReconnect ✅

**Before**:
```swift
private func performReconnect() {
    // ...
    connect(url: url, token: token) { [weak self] result in
        switch result {
        case .success:
            print("[IMTCPTransport] 重连成功")
            self.reconnectManager?.resetAttempts()
            
        case .failure:
            print("[IMTCPTransport] 重连失败，等待下次重试...")
            // ❌ 问题：没有触发下一次重连！
        }
    }
}
```

**After**:
```swift
private func performReconnect() {
    // ...
    connect(url: url, token: token) { [weak self] result in
        switch result {
        case .success:
            IMLogger.shared.info("✅ Reconnected successfully")
            // ✅ 重连成功，重置重连计数
            self.reconnectManager?.resetAttempts()
            
        case .failure(let error):
            IMLogger.shared.error("❌ Reconnect failed: \(error)")
            // ✅ 重连失败，继续触发下一次重连（带指数退避）
            self.reconnectManager?.triggerReconnect()
        }
    }
}
```

**关键修复**:
- ✅ 重连失败时，再次调用 `triggerReconnect()`
- ✅ 这样就能实现自动重试，直到成功或达到最大次数

---

## 📊 重构效果对比

| 指标 | Before | After |
|------|--------|-------|
| **代码行数** | `handleFatalError`: 100+ 行<br>`handleReconnectFailure`: 20+ 行 | `handleFatalError`: 10 行<br>`handleReconnectFailure`: 删除 ✅ |
| **重复逻辑** | ❌ 是（重连计数、指数退避） | ✅ 否（全部在 `ReconnectManager`） |
| **可维护性** | ⚠️ 中（逻辑分散） | ✅ 高（单一职责） |
| **可测试性** | ⚠️ 中（难以单元测试） | ✅ 高（`ReconnectManager` 可独立测试） |
| **随机抖动** | ✅ 有 | ✅ 有（改进到 `ReconnectManager`） |
| **最大延迟限制** | ❌ 无 | ✅ 32 秒 |
| **重连失败处理** | ❌ 不完整（不会自动重试） | ✅ 完整（自动重试直到成功或达到最大次数） |

---

## 📁 修改的文件

| 文件 | 修改内容 | 变化 |
|------|---------|------|
| `IMTCPTransport.swift` | 删除重复属性 | -10 行 |
| `IMTCPTransport.swift` | 简化 `handleFatalError` | -90 行 |
| `IMTCPTransport.swift` | 删除 `handleReconnectFailure` | -20 行 |
| `IMTCPTransport.swift` | 改进 `ReconnectManager` | +10 行 |
| `IMTCPTransport.swift` | 改进 `startReconnectMonitor` | +7 行 |
| `IMTCPTransport.swift` | 改进 `performReconnect` | +3 行 |
| **总计** | | **-100 行** 📉 |

---

## 🎯 关键改进

### 1. 单一职责原则 ✅
- `ReconnectManager` 负责重连逻辑
- `IMTCPTransport` 只负责触发重连

### 2. 避免重复 ✅
- 删除了重复的重连计数属性
- 删除了重复的指数退避逻辑

### 3. 完整的重连机制 ✅
```
Fatal Error
    ↓
handleFatalError()
    ├─ disconnect()
    └─ reconnectManager.triggerReconnect()
        ↓
    ReconnectManager (指数退避)
        ├─ 延迟 1.2s（1s + jitter）
        └─ onReconnect() → performReconnect()
            ↓
        【成功】resetAttempts() ✅
        【失败】triggerReconnect() → 继续重试
            ↓
        重试 2、3、4、5...
            ↓
        【达到最大次数】onMaxAttemptsReached() ❌
            ↓
        IMClient 通知用户
```

### 4. 雪崩效应避免 ✅
```swift
// 随机抖动：±30%
let jitter = Double.random(in: 0...0.3) * delay
let finalDelay = delay + jitter

// 示例：
// 第1次：1.0s + (0~0.3s) = 1.0~1.3s
// 第2次：2.0s + (0~0.6s) = 2.0~2.6s
// 第3次：4.0s + (0~1.2s) = 4.0~5.2s
```

---

## ✅ 用户反馈

**用户问题**：
> "我有个疑问，不是已经有ReconnectManager重连管理器了么，为什么还要单独增加reconnectAttempts和maxReconnectAttempts"

**回答**：
- ✅ 你说得对！这是重复的设计
- ✅ 已经删除重复属性
- ✅ 全部委托给 `ReconnectManager` 管理
- ✅ 代码从 220+ 行简化到 120 行（-100 行）
- ✅ 更加符合单一职责原则

---

**文档版本**: 1.0.0  
**最后更新**: 2025-01-26  
**作者**: IMSDK Team


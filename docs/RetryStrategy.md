# 消息重试策略

## 🤔 核心问题

### 什么时候应该重试？

**错误的理解：**
- ❌ 提交到 WebSocket 失败就重试
- ❌ 立即重试，延迟 2 秒

**正确的理解：**
- ✅ 没收到服务器 ACK 才重试
- ✅ 网络断开时等待恢复，不盲目重试

---

## ❌ 旧的设计：盲目重试

### 逻辑

```swift
func sendMessage() {
    websocket.send(data) { success in
        if success {
            // 移除消息 ❌ 错误！
            queue.removeFirst()
        } else {
            // 立即重试 ❌ 错误！
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                sendMessage()  // 2 秒后重试
            }
        }
    }
}
```

### 问题

**场景：网络断开**

```
[Time 0s]  发送消息 A
[Time 0s]  WebSocket 断开，返回 false
[Time 2s]  重试 1/3 → 失败（网络还是断开）
[Time 4s]  重试 2/3 → 失败（网络还是断开）
[Time 6s]  重试 3/3 → 失败（网络还是断开）
[Time 6s]  消息标记为失败 ❌
[Time 10s] 网络恢复
[Time 10s] 消息已经失败，无法发送 ❌
```

**问题分析：**
1. ❌ 浪费了 3 次重试机会
2. ❌ 网络断开时重试没有意义
3. ❌ 网络恢复后消息已经失败了

---

## ✅ 新的设计：智能重试

### 核心思想

> **重试的真正含义：提交成功但未收到 ACK**

```
提交失败（网络断开）
    ↓
不重试，等待网络恢复 ✓

提交成功但 5 秒未收到 ACK
    ↓
重试发送 ✓
```

### 逻辑

```swift
// 1. 提交消息
func tryProcessQueue() {
    websocket.send(data) { success in
        if success {
            // ✅ 提交成功
            item.isSending = true
            item.lastSendTime = currentTime
            // 不移除，等待 ACK
        } else {
            // ❌ 提交失败（网络问题）
            item.isSending = false
            // 不重试，等待网络恢复或下次调用
        }
    }
}

// 2. 定时检查 ACK 超时（每 5 秒）
func checkTimeout() {
    for item in queue where item.isSending {
        let elapsed = currentTime - item.lastSendTime
        
        if elapsed > 10_000 {  // 5 秒超时
            if item.retryCount < 3 {
                // ⏰ ACK 超时，重试
                item.isSending = false
                item.retryCount += 1
                tryProcessQueue()
            } else {
                // 重试耗尽，标记为失败
                onMessageFailed?(item.message)
            }
        }
    }
}

// 3. WebSocket 重连后重发
func onWebSocketReconnected() {
    for item in queue {
        if item.isSending {
            item.isSending = false  // 重置状态
        }
    }
    tryProcessQueue()  // 重新发送所有消息
}
```

---

## 📊 场景对比

### 场景 1：网络断开

**旧设计：**
```
[0s]  发送 A → 失败（网络断开）
[2s]  重试 1/3 → 失败 ❌
[4s]  重试 2/3 → 失败 ❌
[6s]  重试 3/3 → 失败 ❌
[6s]  消息失败 ❌
[10s] 网络恢复（消息已失败）❌
```

**新设计：**
```
[0s]  发送 A → 失败（网络断开）
[0s]  重置 isSending=false ✓
[0s]  不重试，等待网络恢复 ✓
[10s] 网络恢复，触发 onWebSocketReconnected() ✓
[10s] 重新发送 A ✓
[10s] 收到 ACK，成功 ✓
```

**结果：**
- ❌ 旧设计：消息失败
- ✅ 新设计：消息成功

---

### 场景 2：ACK 丢失

**旧设计：**
```
[0s]  发送 A → 成功提交到 WebSocket
[0s]  从队列移除 ❌
[30s] ACK 丢失
[30s] 消息已不在队列，无法重试 ❌
```

**新设计：**
```
[0s]  发送 A → 成功提交到 WebSocket
[0s]  标记 isSending=true，保留在队列 ✓
[30s] ACK 超时触发
[30s] 重置 isSending=false，retry=1
[30s] 重新发送 A ✓
[31s] 收到 ACK，成功 ✓
```

**结果：**
- ❌ 旧设计：消息丢失
- ✅ 新设计：消息成功

---

### 场景 3：网络抖动

**旧设计：**
```
[0s]  发送 A → 失败
[2s]  重试 1/3 → 失败
[4s]  重试 2/3 → 失败
[5s]  网络恢复
[6s]  重试 3/3 → 成功 ✓
[6s]  但已经浪费了 2 次重试 ⚠️
```

**新设计：**
```
[0s]  发送 A → 失败
[0s]  重置 isSending=false
[5s]  网络恢复，触发 onWebSocketReconnected()
[5s]  重新发送 A → 成功 ✓
[5s]  收到 ACK ✓
[5s]  完全没有浪费重试次数 ✓
```

**结果：**
- ⚠️ 旧设计：成功但浪费重试次数
- ✅ 新设计：成功且保留重试次数

---

## 🎯 重试次数的正确用途

### 旧设计：重试次数 = 网络尝试次数 ❌

```
消息 A：
- 尝试 1：网络断开 → 失败
- 尝试 2：网络断开 → 失败
- 尝试 3：网络断开 → 失败
- 结果：消息失败 ❌

结论：重试次数用于对抗网络断开（无意义）
```

### 新设计：重试次数 = ACK 超时次数 ✅

```
消息 A：
- 尝试 1：成功发送，但 ACK 超时（10 秒）
- 尝试 2：成功发送，但 ACK 超时（10 秒）
- 尝试 3：成功发送，但 ACK 超时（10 秒）
- 结果：消息失败 ✓（合理，服务器可能真的有问题）

结论：重试次数用于对抗 ACK 丢失或服务器繁忙（有意义）
```

---

## 📐 参数配置

### ACK 超时时间

```swift
private let ackTimeout: Int64 = 5_000  // 5 秒
```

**为什么是 10 秒？**
- ✅ 网络延迟通常 < 1 秒
- ✅ 服务器处理通常 < 1 秒
- ✅ 10 秒足够覆盖大部分网络问题
- ✅ 快速失败，用户体验更好
- ✅ 参考微信、Telegram 等 IM 应用的设计

### 超时检查间隔

```swift
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { ... }
```

**为什么是 5 秒？**
- ✅ 不需要太频繁（节省 CPU）
- ✅ 5 秒的误差可以接受
- ✅ 刚好匹配 ACK 超时时间

### 最大重试次数

```swift
private let maxRetryCount = 3
```

**为什么是 3 次？**
- ✅ 3 次 = 15 秒（5s × 3）
- ✅ 足够覆盖临时网络问题
- ✅ 快速失败，避免长时间等待

---

## 🔧 实现细节

### 1. QueueItem 数据结构

```swift
private struct QueueItem {
    let message: IMMessage
    var retryCount: Int              // 重试次数
    let timestamp: Int64              // 创建时间
    var isSending: Bool              // 是否正在等待 ACK
    var lastSendTime: Int64          // 最后发送时间
}
```

### 2. 三个关键方法

#### tryProcessQueue()
- 找到 `isSending=false` 的消息
- 提交到 WebSocket
- 成功：标记 `isSending=true`，记录时间
- 失败：保持 `isSending=false`，不重试

#### checkTimeout()
- 遍历 `isSending=true` 的消息
- 检查是否超时（30 秒）
- 超时：重置 `isSending=false`，增加重试次数
- 重试耗尽：标记为失败

#### onWebSocketReconnected()
- 重置所有 `isSending=true` 的消息
- 重新发送所有消息

### 3. 定时器管理

```swift
public init() {
    startTimeoutCheckTimer()
}

deinit {
    stopTimeoutCheckTimer()
}

private func startTimeoutCheckTimer() {
    DispatchQueue.main.async { [weak self] in
        self?.timeoutCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) { [weak self] _ in
            self?.checkTimeout()
        }
    }
}
```

---

## ✅ 优势总结

| 维度 | 旧设计 | 新设计 |
|------|--------|--------|
| **重试时机** | 提交失败立即重试 | ACK 超时才重试 |
| **网络断开** | 浪费重试次数 | 等待网络恢复 |
| **网络恢复** | 消息可能已失败 | 自动重发 |
| **重试意义** | 对抗网络断开（无效） | 对抗 ACK 丢失（有效） |
| **成功率** | 低 | 高 |
| **用户体验** | 差（消息容易失败） | 好（消息可靠送达） |

---

## 🧪 测试场景

### 1. 正常发送

```swift
// Given: 网络正常
// When: 发送消息
// Then: 提交成功 → 收到 ACK → 移除
```

### 2. ACK 超时

```swift
// Given: 消息已发送
// When: 5 秒未收到 ACK
// Then: 重试发送 → 收到 ACK → 移除
```

### 3. 网络断开

```swift
// Given: 消息在队列中
// When: 网络断开
// Then: 提交失败 → 不重试 → 等待恢复 → 重新发送 → 成功
```

### 4. 重试耗尽

```swift
// Given: 消息已重试 3 次
// When: 第 3 次仍超时
// Then: 标记为失败 → 通知界面
```

### 5. 并发发送

```swift
// Given: 队列中有 A, B, C
// When: A 在等待 ACK
// Then: 同时发送 B → B 也等待 ACK → 收到 A 的 ACK → 发送 C
```

---

## 📚 参考

- **微信**：类似的重试策略（观察行为）
- **Telegram**：快速重试 + 无限等待
- **WhatsApp**：基于 ACK 的可靠性保证

---

## 🎓 关键要点

1. **重试的本质**：不是对抗网络断开，而是对抗 ACK 丢失
2. **网络断开**：不应浪费重试次数，应等待恢复
3. **ACK 超时**：真正需要重试的场景
4. **重连重发**：保证所有未确认的消息都能送达

> **设计哲学：智能重试，而非盲目重试**


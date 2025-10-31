# 消息队列流程对比

## ❌ 修复前：错误的实现

### 流程图

```
用户发送消息
    ↓
加入队列 [A]
    ↓
提交到 WebSocket
    ↓
❌ 立即从队列移除 [A]  ← 错误！
    ↓
继续处理下一条 [B]
    ↓
（稍后）收到 ACK [A]
    ↓
⚠️ 但 [A] 已经不在队列了！
```

### 问题分析

```swift
// 消息队列的回调
onSendMessage?(message) { success in
    if success {
        // ❌ 错误：提交到 WebSocket 就认为成功
        queue.removeFirst()
        
        // 问题：
        // 1. WebSocket.send() 只是提交到发送缓冲区
        // 2. 数据可能还没发送到服务器
        // 3. 如果网络断开，消息丢失
        // 4. 重试机制无效
    }
}
```

### 风险场景

**场景 1：网络瞬断**
```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 从队列移除 ❌
[Net]   网络断开！
[Net]   消息 A 丢失 ❌
[Net]   恢复连接
[Net]   服务器永远收不到消息 A
```

**场景 2：服务器繁忙**
```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 从队列移除 ❌
[Net]   服务器繁忙，丢弃了消息
[Net]   没有返回 ACK
[Queue] 消息已不在队列，无法重试 ❌
```

---

## ✅ 修复后：正确的实现

### 流程图

```
用户发送消息
    ↓
加入队列 [A] (isSending=false)
    ↓
提交到 WebSocket
    ↓
✓ 标记 isSending=true，但保留在队列 [A]
    ↓
继续处理下一条 [B]
    ↓
（稍后）收到 ACK [A]
    ↓
✓ 现在才从队列移除 [A]
```

### 正确实现

```swift
// 消息队列的回调
onSendMessage?(message) { success in
    if success {
        // ✅ 正确：提交成功，但不移除
        item.isSending = true
        // 消息保持在队列中，等待 ACK
        
        // 继续处理下一条
        tryProcessQueue()
    } else {
        // 提交失败，重试
        if item.retryCount < maxRetryCount {
            item.isSending = false
            item.retryCount += 1
            // 延迟重试
        }
    }
}

// 收到 ACK 时
func handleMessageAck(messageID: String) {
    // ✅ 只有这里才移除
    messageQueue.dequeue(messageID: messageID)
}
```

### 可靠性保证

**场景 1：网络瞬断（自动恢复）**
```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 标记 isSending=true ✓
[Queue] A 仍在队列中 ✓
[Net]   网络断开！
[Net]   恢复连接
[Queue] A 仍在队列，可以重发 ✓
[Net]   收到 ACK [A]
[Queue] 移除 A ✓
```

**场景 2：服务器繁忙（自动重试）**
```
[Queue] 消息 A 加入队列
[Queue] 提交到 WebSocket → 标记 isSending=true ✓
[Net]   服务器丢弃了消息
[Net]   超时（或重连后）
[Queue] 重置 isSending=false
[Queue] 重新提交 (retry 1/3)
[Net]   收到 ACK [A]
[Queue] 移除 A ✓
```

**场景 3：并发发送（避免重复）**
```
[Queue] 消息 A (isSending=true) - 等待 ACK
[Queue] 消息 B (isSending=false) - 可以发送
[Queue] 消息 C (isSending=false) - 排队等待
[Queue] 处理 B → 标记 isSending=true
[Net]   收到 ACK [A]
[Queue] 移除 A，处理 C ✓
```

---

## 对比总结

| 维度 | 修复前 ❌ | 修复后 ✅ |
|------|----------|----------|
| **队列移除时机** | 提交到 WebSocket 后 | 收到服务器 ACK 后 |
| **消息可靠性** | 低（网络问题导致丢失） | 高（自动重试） |
| **重试机制** | 无效（消息已移除） | 有效（消息保留在队列） |
| **断线重连** | 未发送的消息丢失 | 自动重发 |
| **重复发送** | 可能（无保护） | 避免（isSending 标记） |
| **状态一致性** | 差（队列和 ACK 不同步） | 好（ACK 驱动移除） |

---

## 关键要点

### 1. 消息队列的核心职责

> **保证消息可靠送达，而不仅仅是发送缓冲区**

### 2. 提交到 WebSocket ≠ 发送成功

```swift
websocket.send(data: data)
// 这只是把数据放入发送缓冲区
// 不代表：
// - 数据已发送
// - 服务器已收到
// - 消息已送达
```

### 3. 只有 ACK 是真理

```swift
// 只有收到服务器 ACK，才能确认消息送达
func handleMessageAck(messageID: String) {
    messageQueue.dequeue(messageID: messageID)
    // 这是唯一应该移除消息的地方
}
```

### 4. isSending 标记的作用

```swift
// 防止消息重复发送
guard let index = queue.firstIndex(where: { !$0.isSending }) else {
    // 所有消息都在等待 ACK，不要重复发送
    return
}
```

---

## ✅ 已实现的优化

### 1. ACK 超时机制

```swift
// 定时检查（每 5 秒）
private func checkTimeout() {
    for item in queue where item.isSending {
        let elapsed = currentTime - item.lastSendTime
        
        if elapsed > 10_000 {  // 5 秒超时
            if item.retryCount < maxRetryCount {
                // 重置状态，允许重试
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
```

### 2. 断线重连后自动重发

```swift
// WebSocket 重连后调用
public func onWebSocketReconnected() {
    // 重置所有消息状态
    for i in 0..<queue.count {
        var item = queue[i]
        if item.isSending {
            item.isSending = false
            queue[i] = item
        }
    }
    
    // 重新发送
    tryProcessQueue()
}
```

### 3. 网络断开时不盲目重试

```swift
if success {
    // 提交成功，等待 ACK
    item.isSending = true
    item.lastSendTime = currentTime
} else {
    // 提交失败，重置状态
    // 不立即重试，等待：
    // - WebSocket 重连
    // - 或下次调用 tryProcessQueue
    item.isSending = false
}
```

### 3. 消息去重

```swift
// 服务器端根据 messageID 去重
// 避免网络抖动导致的重复消息
```

### 4. 优先级队列

```swift
// 支持高优先级消息（如撤回）优先发送
```

---

## 测试用例

### 1. 正常发送

```swift
// Given: 队列为空
// When: 发送消息 A
// Then: A 加入队列 → 提交 WebSocket → 收到 ACK → 移除 A
```

### 2. 网络断开

```swift
// Given: 消息 A 在队列中
// When: 提交到 WebSocket 失败（网络断开）
// Then: 延迟 2 秒重试 → 成功 → 收到 ACK → 移除 A
```

### 3. 并发发送

```swift
// Given: 消息 A, B, C 在队列中
// When: 发送 A（等待 ACK）→ 发送 B（等待 ACK）
// Then: 收到 ACK(A) → 移除 A → 发送 C
```

### 4. 重试耗尽

```swift
// Given: 消息 A 在队列中
// When: 提交失败 3 次
// Then: 移除 A，标记为 .failed
```


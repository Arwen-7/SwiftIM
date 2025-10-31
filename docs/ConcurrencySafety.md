# 并发安全设计

## 🚨 发现的问题

### 死锁场景

**原始代码：**
```swift
private let lock = NSLock()  // 非递归锁

private func tryProcessQueue() {
    lock.lock()
    defer { lock.unlock() }
    
    // 处理消息...
    if success {
        // ❌ 递归调用
        tryProcessQueue()  
        // 尝试再次获取锁 → 死锁！
    }
}
```

**死锁流程：**
```
Thread 1:
  tryProcessQueue()
    lock.lock() ✓ (获取锁)
      发送消息 A 成功
      tryProcessQueue() (递归)
        lock.lock() ❌ (同一线程重复获取 NSLock)
          → 死锁！线程永久阻塞
```

---

## 🔍 多处并发调用

`tryProcessQueue()` 被多个地方调用：

### 1. enqueue() - 添加消息时
```swift
public func enqueue(_ message: IMMessage) {
    lock.lock()
    queue.append(item)
    lock.unlock()
    
    tryProcessQueue()  // 调用 1
}
```

### 2. dequeue() - 移除消息后
```swift
public func dequeue(messageID: String) {
    lock.lock()
    queue.removeAll { $0.message.messageID == messageID }
    lock.unlock()
    
    tryProcessQueue()  // 调用 2
}
```

### 3. tryProcessQueue() 内部 - 递归
```swift
private func tryProcessQueue() {
    lock.lock()
    // ...
    if success {
        tryProcessQueue()  // 调用 3 (递归)
    }
    lock.unlock()
}
```

### 4. checkTimeout() - 超时检查
```swift
private func checkTimeout() {
    lock.lock()
    // ...
    if hasTimeout {
        lock.unlock()
        tryProcessQueue()  // 调用 4
    }
}
```

### 5. onWebSocketReconnected() - 重连后
```swift
public func onWebSocketReconnected() {
    lock.lock()
    // 重置状态
    lock.unlock()
    
    tryProcessQueue()  // 调用 5
}
```

---

## ✅ 解决方案

### 方案：NSRecursiveLock + 循环（采用）

**改进后：**
```swift
private let lock = NSRecursiveLock()  // ✓ 递归锁

private func tryProcessQueue() {
    lock.lock()
    defer { lock.unlock() }
    
    // 循环代替递归（避免栈溢出）
    while true {
        guard let index = queue.firstIndex(where: { !$0.isSending }) else {
            break  // 没有待发送的消息
        }
        
        let success = sendMessage(queue[index])
        
        if success {
            continue  // 继续下一条
        } else {
            break     // 失败则停止
        }
    }
}
```

### 关键改进

#### 1. NSRecursiveLock
```swift
// NSLock：同一线程重复获取会死锁
private let lock = NSLock()  // ❌

// NSRecursiveLock：同一线程可以重复获取
private let lock = NSRecursiveLock()  // ✅
```

#### 2. 循环代替递归
```swift
// 改进前：递归（可能栈溢出）
if success {
    tryProcessQueue()  // 递归调用
}

// 改进后：循环（性能更好）
while true {
    // ...
    if success {
        continue  // 继续循环
    } else {
        break
    }
}
```

---

## 📊 改进效果

### 并发安全性

| 场景 | 改进前 | 改进后 |
|------|--------|--------|
| **同线程递归** | ❌ 死锁 | ✅ 安全 |
| **多处并发调用** | ⚠️ 风险 | ✅ 安全 |
| **重复处理** | ⚠️ 可能 | ✅ 避免 |

### 性能

| 指标 | 改进前 | 改进后 |
|------|--------|--------|
| **栈深度** | 递归（可能溢出） | 循环（固定） |
| **内存占用** | 高（递归帧） | 低（单帧） |
| **执行效率** | 低 | 高 |

---

## 🧪 测试场景

### 场景 1：快速添加多条消息

```swift
for i in 1...100 {
    messageQueue.enqueue(message)
    // 每次都调用 tryProcessQueue()
    // 但 isProcessing 标记确保不会重复处理
}

// 改进前：可能死锁
// 改进后：正常处理 ✓
```

### 场景 2：发送过程中收到 ACK

```swift
Thread 1: tryProcessQueue()
  -> 正在发送消息 A
  
Thread 2: 收到 ACK(A)
  -> dequeue(A)
  -> tryProcessQueue()
  
// 改进前：可能死锁或重复处理
// 改进后：Thread 2 发现 isProcessing=true，直接返回 ✓
```

### 场景 3：超时检查与新消息并发

```swift
Thread 1: checkTimeout()
  -> 发现超时
  -> tryProcessQueue()
  
Thread 2: enqueue(newMessage)
  -> tryProcessQueue()
  
// 改进前：可能重复处理
// 改进后：其中一个被 isProcessing 标记阻止 ✓
```

### 场景 4：连续发送 100 条消息

```swift
for i in 1...100 {
    messageQueue.enqueue(message)
}

// tryProcessQueue() 通过循环处理所有消息
// 不需要递归 100 层

// 改进前：递归 100 次，可能栈溢出
// 改进后：单次循环，性能更好 ✓
```

---

## 🎯 为什么使用递归锁？

### NSLock vs NSRecursiveLock

```swift
// NSLock
let lock = NSLock()
lock.lock()    // ✓
lock.lock()    // ❌ 死锁！

// NSRecursiveLock
let lock = NSRecursiveLock()
lock.lock()    // ✓
lock.lock()    // ✓ 可以重复获取
lock.unlock()  // 释放一次
lock.unlock()  // 释放第二次
```

### 计数机制

```swift
NSRecursiveLock 内部维护计数：
  - lock() → count++
  - unlock() → count--
  - 只有 count == 0 时真正释放锁
  
Thread 1:
  lock.lock()     // count = 1
  lock.lock()     // count = 2 (允许)
  lock.unlock()   // count = 1
  lock.unlock()   // count = 0 (释放)
```

### 性能开销

| 锁类型 | 性能 | 递归支持 |
|--------|------|---------|
| NSLock | 快 | ❌ |
| NSRecursiveLock | 略慢 | ✅ |

**结论：** 牺牲微小性能换取安全性是值得的！

---

## 💡 最佳实践

### 1. 明确锁的作用域

```swift
func someMethod() {
    lock.lock()
    defer { lock.unlock() }  // ✓ 确保释放
    
    // 临界区
}
```

### 2. 避免在锁内进行耗时操作

```swift
// ❌ 不好
func badExample() {
    lock.lock()
    defer { lock.unlock() }
    
    // 网络请求（耗时）
    let data = fetchFromNetwork()
    processData(data)
}

// ✅ 好
func goodExample() {
    // 先获取数据（无锁）
    let data = fetchFromNetwork()
    
    // 只在必要时加锁
    lock.lock()
    processData(data)
    lock.unlock()
}
```

### 3. 使用标记避免重复

```swift
private var isProcessing = false

func process() {
    lock.lock()
    defer { lock.unlock() }
    
    guard !isProcessing else { return }  // ✓ 提前返回
    
    isProcessing = true
    defer { isProcessing = false }
    
    // 实际处理
}
```

### 4. 循环优于递归

```swift
// ❌ 递归（可能栈溢出）
func processRecursive() {
    if hasMore {
        processRecursive()
    }
}

// ✅ 循环（性能更好）
func processLoop() {
    while hasMore {
        // 处理
    }
}
```

---

## 🎓 关键要点

### 1. 递归 + 非递归锁 = 死锁

```
❌ NSLock + 递归调用 = 死锁
✅ NSRecursiveLock + 递归调用 = 安全
```

### 2. 使用标记避免并发

```
isProcessing 标记：
  - 同一时间只有一个线程在处理
  - 其他调用直接返回
  - 避免重复处理
```

### 3. 循环代替递归

```
循环 vs 递归：
  - 循环：固定栈深度，性能好
  - 递归：栈深度增长，可能溢出
```

### 4. 锁的选择

```
使用场景：
  - 简单互斥 → NSLock
  - 需要递归 → NSRecursiveLock
  - 读写分离 → pthread_rwlock
  - 高性能 → os_unfair_lock
```

---

## 📚 参考资料

- **Apple Documentation**: [NSRecursiveLock](https://developer.apple.com/documentation/foundation/nsrecursivelock)
- **Threading Programming Guide**: [Synchronization](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafety/ThreadSafety.html)
- **Concurrent Programming**: [Lock Types](https://en.wikipedia.org/wiki/Lock_(computer_science))


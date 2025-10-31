# 消息去重机制 - 技术设计

## 📋 概览

### 功能描述
实现消息去重机制，避免网络重传、离线同步等场景下产生的重复消息，保证消息的唯一性和数据一致性。

### 核心目标
1. **防止重复消息**：同一 messageID 的消息在数据库中只保存一份
2. **智能更新**：当消息有变化时自动更新，无变化时跳过
3. **性能优化**：使用主键索引实现高效去重
4. **统计透明**：提供详细的去重统计信息

---

## 🎯 技术方案

### 1. 主键索引

#### 1.1 数据库主键

```swift
public class IMMessage: Object {
    @Persisted(primaryKey: true) public var messageID: String = ""
    // ... 其他字段
}
```

**优势**：
- ✅ Realm 自动创建哈希索引，查询 O(1) 复杂度
- ✅ 主键唯一性由数据库引擎保证
- ✅ 支持 `realm.object(ofType:forPrimaryKey:)` 快速查询

#### 1.2 messageID 生成规则

```
客户端生成：clientMsgID = UUID()
服务端生成：messageID = serverMsgID

规则：
- 发送消息时使用 clientMsgID
- 收到 ACK 后使用服务端返回的 messageID
- 接收消息直接使用服务端的 messageID
```

### 2. 去重策略

#### 2.1 单条消息保存

```swift
public func saveMessage(_ message: IMMessage) throws -> IMMessageSaveResult {
    // 1. 查询是否已存在（O(1) 主键查询）
    if let existing = realm.object(ofType: IMMessage.self, forPrimaryKey: message.messageID) {
        // 2. 判断是否需要更新
        if shouldUpdateMessage(existing: existing, new: message) {
            // 3a. 更新关键字段
            existing.status = message.status
            existing.serverTime = message.serverTime
            // ...
            return .updated
        } else {
            // 3b. 无需更新，跳过
            return .skipped
        }
    } else {
        // 4. 不存在，插入新消息
        realm.add(message)
        return .inserted
    }
}
```

**流程图**：
```
                   ┌─────────────┐
                   │ 保存消息     │
                   └──────┬──────┘
                          │
                          ▼
              ┌───────────────────────┐
              │ 查询主键是否存在？     │
              └───────┬───────────────┘
                      │
          ┌───────────┼───────────┐
          │ 是                    │ 否
          ▼                       ▼
    ┌──────────┐          ┌──────────┐
    │ 已存在   │          │ 插入新   │
    └────┬─────┘          │ 消息     │
         │                └──────────┘
         ▼                      ▲
    ┌──────────────┐            │
    │ 内容有变化？ │            │
    └───┬──────────┘            │
        │                       │
    ┌───┼───┐                   │
    │ 是   否 │                  │
    ▼       ▼                   │
┌────────┐ ┌────────┐           │
│ 更新   │ │ 跳过   │           │
│        │ │        │           │
└────────┘ └────────┘           │
    │           │               │
    └───────────┴───────────────┘
                │
                ▼
        ┌───────────────┐
        │ 返回操作结果  │
        └───────────────┘
```

#### 2.2 批量消息保存

```swift
public func saveMessages(_ messages: [IMMessage]) throws -> IMMessageBatchSaveStats {
    var stats = IMMessageBatchSaveStats()
    
    for message in messages {
        if let existing = realm.object(ofType: IMMessage.self, forPrimaryKey: message.messageID) {
            if shouldUpdateMessage(existing: existing, new: message) {
                // 更新
                stats.updatedCount += 1
            } else {
                // 跳过
                stats.skippedCount += 1
            }
        } else {
            // 插入
            realm.add(message)
            stats.insertedCount += 1
        }
    }
    
    return stats
}
```

### 3. 更新判断逻辑

#### 3.1 需要更新的字段

```swift
private func shouldUpdateMessage(existing: IMMessage, new: IMMessage) -> Bool {
    // 状态变化
    if existing.status != new.status {
        return true
    }
    
    // 服务端时间变化（且新值有效）
    if existing.serverTime != new.serverTime && new.serverTime > 0 {
        return true
    }
    
    // 序列号变化（且新值有效）
    if existing.seq != new.seq && new.seq > 0 {
        return true
    }
    
    // 内容变化
    if existing.content != new.content {
        return true
    }
    
    // 已读状态变化
    if existing.isRead != new.isRead {
        return true
    }
    
    // 删除状态变化
    if existing.isDeleted != new.isDeleted {
        return true
    }
    
    // 撤回状态变化
    if existing.isRevoked != new.isRevoked {
        return true
    }
    
    return false
}
```

#### 3.2 更新策略表

| 字段 | 更新条件 | 说明 |
|------|---------|------|
| `status` | 任何变化 | 消息状态流转 |
| `serverTime` | 新值 > 0 且不同 | 服务端时间戳 |
| `seq` | 新值 > 0 且不同 | 消息序列号 |
| `content` | 任何变化 | 消息内容（撤回/编辑） |
| `isRead` | 任何变化 | 已读状态 |
| `isDeleted` | 任何变化 | 删除状态 |
| `isRevoked` | 任何变化 | 撤回状态 |

**不更新的字段**：
- `clientMsgID`：客户端 ID 不变
- `conversationID`：会话 ID 不变
- `senderID`：发送人不变
- `sendTime`：发送时间不变

---

## 📊 统计信息

### 1. 单条保存结果

```swift
public enum IMMessageSaveResult {
    case inserted   // 插入新消息
    case updated    // 更新已有消息
    case skipped    // 跳过（已存在且无需更新）
}
```

### 2. 批量保存统计

```swift
public struct IMMessageBatchSaveStats {
    public var insertedCount: Int = 0  // 插入数量
    public var updatedCount: Int = 0   // 更新数量
    public var skippedCount: Int = 0   // 跳过数量
    
    public var totalCount: Int {
        return insertedCount + updatedCount + skippedCount
    }
    
    public var deduplicationRate: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(skippedCount) / Double(totalCount)
    }
}
```

**示例输出**：
```
BatchSaveStats(inserted: 5, updated: 3, skipped: 2, total: 10, dedup: 20.0%)
```

---

## 🔍 应用场景

### 场景 1：离线消息同步

```
本地已有消息：
  - msg_001: "Hello" (sent)
  - msg_002: "Hi" (sending)
  - msg_003: "Test" (sent)

服务器返回：
  - msg_001: "Hello" (sent)      ← 重复，跳过
  - msg_002: "Hi" (delivered)    ← 状态变化，更新
  - msg_003: "Test" (sent)       ← 重复，跳过
  - msg_004: "New" (sent)        ← 新消息，插入
  - msg_005: "Another" (sent)    ← 新消息，插入

结果：
  - inserted: 2
  - updated: 1
  - skipped: 2
  - total: 5
  - deduplicationRate: 40%
```

### 场景 2：网络重传

```
第 1 次发送：
  - msg_123: "Hello" (sending)
  → 保存：inserted

网络超时，重传第 2 次：
  - msg_123: "Hello" (sending)
  → 保存：skipped（内容相同）

网络超时，重传第 3 次：
  - msg_123: "Hello" (sending)
  → 保存：skipped（内容相同）

收到 ACK：
  - msg_123: "Hello" (sent)
  → 保存：updated（状态变化）
```

### 场景 3：消息状态流转

```
发送消息：
  msg_456: status=sending → inserted

发送成功：
  msg_456: status=sent → updated

对方收到：
  msg_456: status=delivered → updated

对方已读：
  msg_456: status=read → updated
```

### 场景 4：消息撤回

```
正常消息：
  msg_789: "Secret" (sent)

撤回操作：
  msg_789: "已撤回" (sent, isRevoked=true)
  → 保存：updated（内容和撤回状态变化）
```

---

## ⚡️ 性能优化

### 1. 主键索引性能

| 操作 | 复杂度 | 说明 |
|------|-------|------|
| 主键查询 | O(1) | 哈希索引 |
| 插入 | O(1) | 直接插入 |
| 更新 | O(1) | 主键定位 |
| 去重判断 | O(1) | 主键查询 |

### 2. 批量操作优化

```swift
// ❌ 错误：每次都开启新事务
for message in messages {
    try realm.write {
        realm.add(message)
    }
}

// ✅ 正确：一次事务处理所有消息
try realm.write {
    for message in messages {
        realm.add(message)
    }
}
```

**性能对比**：
```
单条保存（1000 条消息）：~2000ms
批量保存（1000 条消息）：~50ms
性能提升：40倍
```

### 3. 字段更新优化

```swift
// ❌ 错误：更新所有字段
realm.create(IMMessage.self, value: message, update: .all)

// ✅ 正确：只更新需要的字段
if shouldUpdateMessage(existing, new) {
    existing.status = new.status
    existing.serverTime = new.serverTime
    // 只更新变化的字段
}
```

---

## 🧪 测试策略

### 1. 基础功能测试（6 个）

| 测试 | 场景 | 预期结果 |
|------|------|---------|
| testFirstTimeInsert | 首次插入 | inserted |
| testDuplicateInsertSameContent | 重复插入相同内容 | skipped |
| testUpdateMessageContent | 更新内容 | updated |
| testUpdateMessageStatus | 更新状态 | updated |
| testUpdateMessageSeq | 更新 seq | updated |
| testUpdateServerTime | 更新 serverTime | updated |

### 2. 批量操作测试（4 个）

| 测试 | 场景 | 预期结果 |
|------|------|---------|
| testBatchInsertAllNew | 全新消息 | 100% 插入 |
| testBatchInsertAllDuplicates | 全部重复 | 100% 跳过 |
| testBatchMixedOperations | 混合操作 | 正确统计 |
| testBatchSaveEmptyArray | 空数组 | 空统计 |

### 3. 真实场景测试（4 个）

| 测试 | 场景 | 验证点 |
|------|------|--------|
| testOfflineMessageSyncDeduplication | 离线同步 | 去重率正确 |
| testNetworkRetransmissionDeduplication | 网络重传 | 防重复 |
| testMessageStatusTransition | 状态流转 | 每次更新 |
| testConcurrentSaveSameMessage | 并发保存 | 只有一条 |

### 4. 边界测试（3 个）

| 测试 | 场景 | 预期行为 |
|------|------|---------|
| testEmptyMessageID | 空字符串 ID | 正常保存 |
| testLargeDuplicatePerformance | 大量重复 | 性能测试 |
| testConcurrentSaveSameMessage | 并发保存 | 线程安全 |

### 5. 统计测试（3 个）

| 测试 | 场景 | 验证点 |
|------|------|--------|
| testBatchSaveStatsCalculation | 统计计算 | 数量正确 |
| testDeduplicationRateCalculation | 去重率 | 百分比正确 |
| testUpdateMultipleFields | 多字段更新 | 全部更新 |

**总计：20 个测试**

---

## 📈 性能指标

### 1. 单条保存

| 指标 | 数值 | 场景 |
|------|------|------|
| 插入新消息 | < 1ms | 首次保存 |
| 跳过重复 | < 1ms | 完全相同 |
| 更新消息 | < 2ms | 字段变化 |

### 2. 批量保存

| 指标 | 数值 | 场景 |
|------|------|------|
| 100 条全新 | < 10ms | 首次同步 |
| 100 条重复 | < 5ms | 重复同步 |
| 1000 条混合 | < 50ms | 离线同步 |

### 3. 内存占用

| 场景 | 内存占用 |
|------|---------|
| 1000 条消息 | < 2MB |
| 10000 条消息 | < 15MB |
| 100000 条消息 | < 120MB |

---

## 🔒 并发安全

### 1. Realm 线程模型

```swift
// ❌ 错误：跨线程访问
let message = getMessage(messageID: "123")  // 线程 A
DispatchQueue.global().async {
    message.status = .sent  // 线程 B - 崩溃！
}

// ✅ 正确：每个线程独立 Realm 实例
DispatchQueue.global().async {
    let realm = try! Realm()
    let message = realm.object(ofType: IMMessage.self, forPrimaryKey: "123")
    try! realm.write {
        message?.status = .sent
    }
}
```

### 2. 主键唯一性保证

```
多个线程同时插入相同 messageID：
  Thread 1: saveMessage(msg_001)
  Thread 2: saveMessage(msg_001)
  Thread 3: saveMessage(msg_001)

Realm 保证：
  ✅ 只有一个线程成功插入
  ✅ 其他线程会检测到已存在
  ✅ 数据库中只有一条记录
```

### 3. 写入事务串行化

```
Realm 写入事务是串行的：
  Write 1: [开始] → [执行] → [提交]
                                      Write 2: [开始] → [执行] → [提交]
                                                                          Write 3: [开始] ...

优势：
  ✅ 自动避免写冲突
  ✅ 保证数据一致性
  ✅ 无需额外锁机制
```

---

## 🎯 最佳实践

### 1. messageID 管理

```swift
// ✅ 推荐：使用服务端 messageID 作为主键
message.messageID = serverMsgID

// ⚠️ 谨慎：客户端生成 messageID
message.messageID = UUID().uuidString
// 需要在收到 ACK 后更新为服务端 ID
```

### 2. 批量保存

```swift
// ✅ 推荐：批量保存离线消息
let stats = try database.saveMessages(offlineMessages)
logger.info("Sync completed: \(stats)")

// ❌ 避免：循环单条保存
for message in offlineMessages {
    try database.saveMessage(message)  // 性能差 40 倍
}
```

### 3. 统计监控

```swift
// ✅ 推荐：监控去重率
let stats = try database.saveMessages(messages)
if stats.deduplicationRate > 0.8 {
    logger.warning("High deduplication rate: \(stats.deduplicationRate)")
    // 可能是重复拉取，检查同步逻辑
}
```

### 4. 错误处理

```swift
// ✅ 推荐：捕获并记录错误
do {
    let result = try database.saveMessage(message)
    logger.debug("Save result: \(result)")
} catch {
    logger.error("Failed to save message: \(error)")
    // 重试或上报
}
```

---

## 🔄 与其他功能的关系

### 1. 消息增量同步

```
增量同步拉取消息 → 批量保存 → 自动去重
                              ↓
                      统计去重率（通常 20-40%）
```

### 2. 消息状态管理

```
收到 ACK → 更新消息状态 → 去重检查
                         ↓
                   如果状态相同，跳过
```

### 3. 离线消息

```
应用启动 → 拉取离线消息 → 批量保存
                          ↓
                  本地已有的消息被跳过
                  新消息被插入
```

---

## 📊 监控指标

### 1. 去重率

```
正常范围：20-40%
高去重率（>80%）：可能重复拉取
低去重率（<10%）：可能是新用户或清空了数据
```

### 2. 操作分布

```
理想分布：
  - 插入：60-80%
  - 更新：10-20%
  - 跳过：10-30%

异常分布：
  - 插入：<20%  → 可能重复同步
  - 跳过：>80%  → 可能重复拉取
  - 更新：>50%  → 可能频繁更新状态
```

### 3. 性能监控

```
批量保存 1000 条消息：
  - 正常：< 100ms
  - 警告：100-500ms
  - 异常：> 500ms
```

---

## 🎊 总结

### 实现要点

1. ✅ **主键唯一性**：使用 `@Persisted(primaryKey: true)` 保证唯一
2. ✅ **智能更新**：只更新变化的字段，相同内容跳过
3. ✅ **批量优化**：一次事务处理多条消息
4. ✅ **统计透明**：提供详细的操作统计
5. ✅ **线程安全**：Realm 自动保证并发安全

### 性能收益

- 🚀 **主键查询**：O(1) 复杂度
- 🚀 **批量操作**：性能提升 40 倍
- 🚀 **去重率**：通常 20-40%，节省存储和处理

### 用户价值

- ✅ **无重复消息**：用户体验更好
- ✅ **节省流量**：重复消息不重复处理
- ✅ **数据一致**：同一消息多次收到，状态正确

---

**设计完成时间**：2025-10-24  
**预计工作量**：1-2 天  
**优先级**：🔥 高


# 消息增量同步技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [协议设计](#协议设计)
5. [实现细节](#实现细节)
6. [流程图](#流程图)
7. [性能优化](#性能优化)
8. [测试用例](#测试用例)

---

## 概述

### 什么是消息增量同步？

**消息增量同步**是指客户端只拉取**上次同步之后**的新消息，而不是每次都拉取全部消息。

### 为什么需要增量同步？

**场景 1：用户离线后重新上线**
```
用户 A 离线 24 小时
期间收到 10,000 条消息
```

**全量同步（不好）**：
```
- 拉取所有 10,000 条消息
- 流量：~10MB
- 耗时：~10 秒
- 用户体验：❌ 慢
```

**增量同步（好）**：
```
- 只拉取新的 10,000 条消息
- 流量：~10MB（首次）
- 之后离线 1 小时，只拉取 100 条新消息
- 流量：~100KB
- 耗时：~0.5 秒
- 用户体验：✅ 快
```

### 核心优势

| 对比项 | 全量同步 | 增量同步 |
|--------|---------|---------|
| **流量消耗** | 每次都拉取全部 | 只拉取新消息，节省 **90%+** |
| **同步速度** | 慢（10秒+） | 快（0.5秒） |
| **服务器压力** | 大 | 小 |
| **用户体验** | ❌ 慢 | ✅ 快 |

---

## 核心概念

### 1. seq（序列号）

**定义**：
- 每条消息都有一个全局唯一的、递增的序列号 `seq`
- 服务器按顺序分配 seq：1, 2, 3, 4, ...
- seq 是消息的**逻辑时间戳**

**特点**：
```
✅ 全局唯一
✅ 严格递增
✅ 连续（无间隙）
✅ 服务器分配
```

**示例**：
```swift
Message 1: seq = 1000, content = "Hello"
Message 2: seq = 1001, content = "World"
Message 3: seq = 1002, content = "!"
```

### 2. lastSyncSeq（上次同步的最大 seq）

**定义**：
- 客户端本地记录的**已同步消息的最大 seq**
- 下次同步时，只拉取 `seq > lastSyncSeq` 的消息

**存储位置**：
- 方案 1：存储在 Realm（推荐）
- 方案 2：存储在 UserDefaults
- 方案 3：存储在内存（不推荐，重启丢失）

**示例**：
```swift
// 用户 A 的最后同步状态
User A:
  - lastSyncSeq = 1000
  - 下次拉取：seq > 1000 的消息

// 用户 B 的最后同步状态  
User B:
  - lastSyncSeq = 2500
  - 下次拉取：seq > 2500 的消息
```

### 3. 分批拉取

**为什么要分批？**
```
场景：用户离线 7 天，有 100,000 条新消息

一次性拉取 100,000 条：
  - 流量：~100MB
  - 内存：~200MB
  - 耗时：~60 秒
  - 风险：❌ 内存溢出、超时、卡顿

分批拉取（每次 500 条）：
  - 流量：每批 ~500KB
  - 内存：每批 ~1MB
  - 耗时：每批 ~0.5 秒
  - 风险：✅ 可控
```

**分批策略**：
```swift
// 每次拉取数量
let batchSize = 500

// 分批拉取
Batch 1: seq 1001-1500  (500条)
Batch 2: seq 1501-2000  (500条)
Batch 3: seq 2001-2500  (500条)
...
直到 hasMore = false
```

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                    │
│                     (IMClient)                         │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Business Layer                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         IMMessageSyncManager (新增)               │  │
│  │  - 管理增量同步逻辑                               │  │
│  │  - 记录 lastSyncSeq                               │  │
│  │  - 分批拉取                                       │  │
│  │  - 去重和保存                                     │  │
│  └──────────────────────────────────────────────────┘  │
│                          │                              │
│                          ▼                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │          IMMessageManager                         │  │
│  │  - 消息存储                                       │  │
│  │  - 消息回调                                       │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                     Core Layer                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │          IMNetworkManager (HTTP API)              │  │
│  │  - syncMessages(lastSeq, count)                   │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │          IMDatabaseManager                        │  │
│  │  - saveMessages(batch)                            │  │
│  │  - getMaxSeq()                                    │  │
│  │  - saveLastSyncSeq(seq)                           │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 模块职责

#### 1. IMMessageSyncManager（新增模块）
```swift
/// 消息增量同步管理器
/// 
/// 职责：
/// - 管理增量同步逻辑
/// - 记录和更新 lastSyncSeq
/// - 分批拉取消息
/// - 去重和保存
/// - 进度回调
public class IMMessageSyncManager {
    // 核心方法
    public func startSync(completion: @escaping (Result<Void, Error>) -> Void)
    public func stopSync()
    public func resetSync()  // 清空本地数据，重新全量同步
}
```

#### 2. IMNetworkManager（扩展 HTTP API）
```swift
extension IMHTTPManager {
    /// 增量同步消息
    /// - Parameters:
    ///   - lastSeq: 上次同步的最大 seq
    ///   - count: 本次拉取数量
    ///   - completion: 完成回调
    public func syncMessages(
        lastSeq: Int64,
        count: Int,
        completion: @escaping (Result<SyncResponse, Error>) -> Void
    )
}
```

#### 3. IMDatabaseManager（扩展数据库方法）
```swift
extension IMDatabaseManager {
    /// 批量保存消息（去重）
    public func saveMessages(_ messages: [IMMessage]) throws
    
    /// 获取本地最大 seq
    public func getMaxSeq() -> Int64
    
    /// 保存最后同步的 seq
    public func saveLastSyncSeq(_ seq: Int64) throws
    
    /// 获取最后同步的 seq
    public func getLastSyncSeq() -> Int64
}
```

---

## 协议设计

### 1. 同步请求（Protobuf）

```protobuf
// Protos/im_protocol.proto

// 增量同步请求
message SyncRequest {
  int64 lastSeq = 1;       // 上次同步的最大 seq（0 表示首次同步）
  int32 count = 2;         // 本次拉取数量（建议 100-500）
  int64 timestamp = 3;     // 客户端时间戳（用于计算延迟）
}
```

### 2. 同步响应（Protobuf）

```protobuf
// 增量同步响应
message SyncResponse {
  repeated Message messages = 1;  // 消息列表
  int64 maxSeq = 2;                // 服务器当前最大 seq
  bool hasMore = 3;                // 是否还有更多消息
  int64 totalCount = 4;            // 总共有多少条新消息（用于显示进度）
}

// Message 定义
message Message {
  string messageID = 1;      // 客户端消息 ID
  string serverMsgID = 2;    // 服务器消息 ID
  int64 seq = 3;             // 序列号（关键）
  string conversationID = 4;
  string senderID = 5;
  int32 messageType = 6;
  string content = 7;
  int64 createTime = 8;
  int64 serverTime = 9;
}
```

### 3. HTTP API 设计

```
POST /api/v1/messages/sync

Request:
{
  "lastSeq": 1000,
  "count": 500,
  "timestamp": 1698048000000
}

Response:
{
  "code": 0,
  "message": "success",
  "data": {
    "messages": [
      {
        "messageID": "msg_001",
        "seq": 1001,
        "conversationID": "conv_123",
        "senderID": "user_456",
        "messageType": 1,
        "content": "Hello",
        "createTime": 1698048001000,
        "serverTime": 1698048001500
      },
      // ... more messages
    ],
    "maxSeq": 1500,
    "hasMore": true,
    "totalCount": 10000
  }
}
```

---

## 实现细节

### 1. 数据模型扩展

```swift
// IMModels.swift

/// 同步配置（存储在 Realm）
public class IMSyncConfig: Object {
    @Persisted(primaryKey: true) var userID: String = ""
    @Persisted var lastSyncSeq: Int64 = 0        // 最后同步的 seq
    @Persisted var lastSyncTime: Int64 = 0       // 最后同步时间
    @Persisted var isSyncing: Bool = false       // 是否正在同步
}

/// 同步响应
public struct IMSyncResponse {
    let messages: [IMMessage]
    let maxSeq: Int64
    let hasMore: Bool
    let totalCount: Int64
}
```

### 2. 同步状态机

```
状态转换：
                        startSync()
   idle ────────────────────────────► syncing
    ▲                                    │
    │                                    │
    │                                    ▼
    │                              分批拉取
    │                                    │
    │                                    │
    │         hasMore = false            ▼
    └───────────────────────────── completed
                                         │
                                         │ error
                                         ▼
                                       failed
                                         │
                                         │ retry
                                         └──► syncing
```

### 3. 同步流程（详细）

```swift
func startSync() {
    // Step 1: 获取本地 lastSyncSeq
    let lastSeq = database.getLastSyncSeq()
    
    // Step 2: 标记为正在同步
    state = .syncing
    
    // Step 3: 开始分批拉取
    syncBatch(lastSeq: lastSeq, totalFetched: 0)
}

func syncBatch(lastSeq: Int64, totalFetched: Int) {
    // Step 4: 请求服务器
    networkManager.syncMessages(lastSeq: lastSeq, count: batchSize) { result in
        switch result {
        case .success(let response):
            // Step 5: 保存消息到数据库（去重）
            try? database.saveMessages(response.messages)
            
            // Step 6: 更新 lastSyncSeq
            if let maxSeq = response.messages.map({ $0.seq }).max() {
                try? database.saveLastSyncSeq(maxSeq)
            }
            
            // Step 7: 通知进度
            let progress = Double(totalFetched + response.messages.count) / Double(response.totalCount)
            onProgress?(progress)
            
            // Step 8: 检查是否还有更多
            if response.hasMore {
                // 继续拉取下一批
                syncBatch(lastSeq: response.maxSeq, totalFetched: totalFetched + response.messages.count)
            } else {
                // 同步完成
                state = .completed
                onComplete?()
            }
            
        case .failure(let error):
            // Step 9: 错误处理
            handleError(error)
        }
    }
}
```

### 4. 去重策略

**问题**：
```
场景：同一条消息可能通过多个渠道到达：
1. WebSocket 实时推送
2. 增量同步拉取
3. 手动刷新

如何避免重复？
```

**方案 1：数据库主键约束（推荐）**
```swift
// IMMessage 使用 messageID 作为主键
@Persisted(primaryKey: true) var messageID: String = ""

// 保存时使用 update: .modified
realm.add(message, update: .modified)

// 效果：
// - 如果 messageID 已存在，更新
// - 如果 messageID 不存在，插入
```

**方案 2：插入前检查**
```swift
func saveMessages(_ messages: [IMMessage]) throws {
    let realm = try getRealm()
    
    try realm.write {
        for message in messages {
            // 检查是否已存在
            if let existing = realm.object(ofType: IMMessage.self, forPrimaryKey: message.messageID) {
                // 已存在，只更新部分字段（如状态）
                existing.status = message.status
                existing.serverTime = message.serverTime
            } else {
                // 不存在，插入
                realm.add(message)
            }
        }
    }
}
```

### 5. 并发控制

**问题**：
```
场景 1：用户快速点击"刷新"按钮 5 次
场景 2：同时有 WebSocket 重连触发同步

如何避免并发同步？
```

**方案：使用锁 + 状态标记**
```swift
private let syncLock = NSLock()
private var isSyncing = false

func startSync() {
    syncLock.lock()
    defer { syncLock.unlock() }
    
    // 如果已经在同步，直接返回
    guard !isSyncing else {
        IMLogger.shared.warning("Sync already in progress, skip")
        return
    }
    
    isSyncing = true
    
    // 开始同步...
    
    // 同步完成后
    defer { isSyncing = false }
}
```

### 6. 性能优化

#### 优化 1：批量插入（Realm 优化）
```swift
// ❌ 慢：每条消息一个事务
for message in messages {
    try realm.write {
        realm.add(message)
    }
}

// ✅ 快：所有消息一个事务
try realm.write {
    realm.add(messages)
}

// 性能提升：100x
```

#### 优化 2：后台线程同步
```swift
// 同步在后台线程执行，不阻塞主线程
DispatchQueue.global(qos: .userInitiated).async {
    self.startSync()
}
```

#### 优化 3：增量通知
```swift
// ❌ 每批同步完成后，通知 UI 刷新全部会话
notifyListeners { $0.onConversationListChanged() }

// ✅ 只通知受影响的会话
let affectedConvIDs = Set(messages.map { $0.conversationID })
for convID in affectedConvIDs {
    notifyListeners { $0.onConversationUpdated(convID) }
}
```

---

## 流程图

### 完整同步流程

```
用户上线
   │
   ▼
获取 lastSyncSeq
   │
   ▼
请求服务器
(lastSeq, count=500)
   │
   ▼
服务器返回
messages, maxSeq, hasMore
   │
   ▼
保存消息（去重）
   │
   ▼
更新 lastSyncSeq = maxSeq
   │
   ▼
通知进度
   │
   ▼
hasMore?
   │
   ├─ Yes ─► 继续拉取下一批
   │         (lastSeq=maxSeq, count=500)
   │
   └─ No ──► 同步完成 ✅
```

### 错误处理流程

```
同步出错
   │
   ▼
判断错误类型
   │
   ├─ 网络错误 ─────► 等待 3 秒 ─► 重试
   │                  (最多 3 次)
   │
   ├─ 认证失败 ─────► 提示用户 ─► 停止同步
   │
   ├─ 服务器错误 ───► 等待 10 秒 ─► 重试
   │
   └─ 其他错误 ─────► 记录日志 ─► 停止同步
```

---

## 性能优化

### 1. 智能批量大小

```swift
// 根据网络状况动态调整批量大小
func getBatchSize() -> Int {
    switch networkMonitor.currentStatus {
    case .wifi:
        return 500  // WiFi：大批量
    case .cellular:
        return 200  // 移动网络：中批量
    case .disconnected:
        return 0
    case .unknown:
        return 100  // 未知：小批量
    }
}
```

### 2. 压缩传输

```swift
// HTTP 请求头
headers = [
    "Accept-Encoding": "gzip, deflate",  // 支持压缩
    "Content-Encoding": "gzip"           // 请求体压缩
]

// 效果：流量减少 70%
```

### 3. 缓存优化

```swift
// 同步过程中，不立即写入缓存
// 等所有批次完成后，一次性写入缓存

var tempMessages: [IMMessage] = []

// 分批拉取时
tempMessages.append(contentsOf: response.messages)

// 全部完成后
for message in tempMessages {
    messageCache.set(message, forKey: message.messageID)
}
```

### 4. 数据库索引

```swift
// 为 seq 建立索引，加速查询
@Persisted(indexed: true) var seq: Int64 = 0

// 查询最大 seq（使用索引）
let maxSeq = realm.objects(IMMessage.self)
    .sorted(byKeyPath: "seq", ascending: false)
    .first?.seq ?? 0

// 性能提升：100x
```

---

## 测试用例

### 1. 功能测试

```swift
// 测试 1：首次同步
func testFirstSync() {
    // Given: lastSyncSeq = 0
    // When: 调用 startSync()
    // Then: 拉取所有消息
}

// 测试 2：增量同步
func testIncrementalSync() {
    // Given: lastSyncSeq = 1000，服务器有 seq 1001-1500 的消息
    // When: 调用 startSync()
    // Then: 只拉取 1001-1500 的消息
}

// 测试 3：分批拉取
func testBatchSync() {
    // Given: 有 10,000 条新消息
    // When: 调用 startSync()，batchSize = 500
    // Then: 分 20 批拉取，每批 500 条
}

// 测试 4：去重
func testDeduplication() {
    // Given: 本地已有 seq = 1001 的消息
    // When: 同步时再次收到 seq = 1001 的消息
    // Then: 不重复插入，只更新状态
}
```

### 2. 性能测试

```swift
// 测试 1：大量消息同步
func testLargeSync() {
    // Given: 100,000 条新消息
    // When: 调用 startSync()
    // Then: 
    //   - 完成时间 < 30 秒
    //   - 内存占用 < 50MB
    //   - CPU 占用 < 30%
}

// 测试 2：并发同步
func testConcurrentSync() {
    // Given: 同时调用 startSync() 5 次
    // When: 执行
    // Then: 只有一个同步任务在执行
}
```

### 3. 边界测试

```swift
// 测试 1：无新消息
func testNoNewMessages() {
    // Given: lastSyncSeq = 服务器最大 seq
    // When: 调用 startSync()
    // Then: hasMore = false，直接完成
}

// 测试 2：网络中断
func testNetworkInterruption() {
    // Given: 同步进行到一半
    // When: 网络断开
    // Then: 暂停同步，保存已拉取的消息，等待重连
}

// 测试 3：极大 seq
func testLargeSeq() {
    // Given: seq = Int64.max - 100
    // When: 继续同步
    // Then: 不溢出，正常工作
}
```

---

## 与现有模块的集成

### 1. IMClient 集成

```swift
// IMClient.swift

public func connect() {
    // 连接成功后，自动触发增量同步
    networkManager.connect()
    
    networkManager.onConnected = { [weak self] in
        self?.messageSyncManager.startSync { result in
            switch result {
            case .success:
                IMLogger.shared.info("Sync completed")
            case .failure(let error):
                IMLogger.shared.error("Sync failed: \(error)")
            }
        }
    }
}
```

### 2. WebSocket 重连集成

```swift
// IMNetworkManager.swift

private func handleReconnected() {
    // 重连成功后，触发增量同步
    onConnected?()
    
    // 触发消息队列重试
    protocolHandler.onWebSocketReconnected()
}
```

### 3. 手动刷新

```swift
// IMMessageManager.swift

/// 手动刷新消息
public func refreshMessages(completion: @escaping (Result<Void, Error>) -> Void) {
    messageSyncManager.startSync(completion: completion)
}
```

---

## 监控和日志

### 同步日志

```swift
// 开始同步
IMLogger.shared.info("🔄 Sync started, lastSeq: \(lastSeq)")

// 批次完成
IMLogger.shared.debug("📦 Batch \(batchIndex) completed, fetched: \(count), progress: \(progress)%")

// 同步完成
IMLogger.shared.info("✅ Sync completed, total: \(totalCount), duration: \(duration)s")

// 同步失败
IMLogger.shared.error("❌ Sync failed: \(error)")
```

### 性能指标

```swift
// 记录同步性能
struct SyncMetrics {
    let duration: TimeInterval      // 总耗时
    let totalMessages: Int          // 总消息数
    let totalBatches: Int           // 总批次数
    let avgBatchTime: TimeInterval  // 平均每批耗时
    let throughput: Double          // 吞吐量（条/秒）
}

// 上报到性能监控
IMLogger.performanceMonitor.recordSyncMetrics(metrics)
```

---

## 总结

### 关键要点

1. ✅ **基于 seq 的增量同步**：只拉取新消息，节省流量 90%+
2. ✅ **分批拉取**：避免内存溢出和超时
3. ✅ **去重机制**：数据库主键约束，避免重复消息
4. ✅ **并发控制**：锁 + 状态标记，避免并发同步
5. ✅ **性能优化**：批量插入、后台线程、智能批量大小
6. ✅ **错误处理**：重试机制、错误分类

### 预期效果

| 指标 | 改进前 | 改进后 | 提升 |
|------|--------|--------|------|
| 同步耗时 | 10-30秒 | 0.5-2秒 | **10x** |
| 流量消耗 | 10MB | 1MB | **90%** |
| 内存占用 | 200MB | 20MB | **90%** |
| 用户体验 | ❌ 慢 | ✅ 快 | ⭐️⭐️⭐️⭐️⭐️ |

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


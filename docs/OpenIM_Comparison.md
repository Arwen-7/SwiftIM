# OpenIM SDK vs 当前 SDK 对比分析

## 概述

本文档对比分析了 [OpenIM SDK](https://github.com/openimsdk/openim-sdk-core) 和我们当前的 IM iOS SDK，找出可以学习和改进的地方。

> 参考资料：
> - [OpenIM SDK GitHub](https://github.com/openimsdk/openim-sdk-core)
> - [OpenIM 官方文档](https://docs.openim.io)

---

## ✅ 我们已有的功能

| 功能分类 | 具体功能 | 实现状态 |
|---------|---------|---------|
| **网络管理** | WebSocket 长连接 | ✅ |
| | Ping/Pong 心跳 | ✅ |
| | 断线重连 | ✅ |
| | HTTP API 请求 | ✅ |
| **消息管理** | 消息发送/接收 | ✅ |
| | 消息编码/解码 | ✅ (Protobuf) |
| | 消息本地存储 | ✅ (Realm) |
| | 消息可靠性（ACK/重试） | ✅ |
| | 消息状态管理 | ✅ |
| | 消息撤回 | ✅ (基础) |
| | 消息已读回执 | ✅ (基础) |
| **会话管理** | 会话列表 | ✅ |
| | 未读数统计 | ✅ |
| **安全** | 端到端加密 | ✅ (基础) |
| | 本地数据加密 | ✅ |
| **数据模型** | 用户、消息、会话、群组、好友 | ✅ |
| **工具** | 日志系统 | ✅ |
| | 缓存管理 | ✅ |

---

## 🔍 OpenIM SDK 特有的功能和设计

### 1️⃣ **跨平台支持** ⭐️⭐️⭐️

**OpenIM 实现：**
- 使用 **Go 语言**编写核心 SDK
- 通过 **gomobile** 生成 iOS/Android SDK
- 通过 **WebAssembly (WASM)** 支持 Web 端
- 一套代码，多端复用

**我们当前：**
- ✅ 纯 Swift 实现，仅支持 iOS
- ❌ 不支持跨平台

**改进建议：**
```
优先级：低（我们专注 iOS）

如果未来需要支持多平台：
1. 考虑使用 Kotlin Multiplatform (KMP)
2. 或者使用 Flutter/React Native 的插件机制
3. 保持当前 Swift 实现，单独为其他平台开发
```

---

### 2️⃣ **消息增量同步机制** ⭐️⭐️⭐️

**OpenIM 实现：**
```go
// 增量同步：基于 seq（序列号）
type SyncRequest {
    lastSeq int64  // 上次同步的最大 seq
    count   int32  // 本次拉取数量
}

// 服务器返回
type SyncResponse {
    messages []Message  // 新消息列表
    maxSeq   int64      // 当前服务器最大 seq
    hasMore  bool       // 是否还有更多
}
```

**工作流程：**
```
1. 客户端记录本地最大 seq
2. 重连后，请求服务器 seq > lastSeq 的消息
3. 分批拉取（每次 100-500 条）
4. 直到 hasMore = false
```

**我们当前：**
- ✅ 有 `seq` 字段定义
- ❌ 没有实现完整的增量同步逻辑
- ❌ 没有分批拉取机制

**改进建议：**
```swift
// 需要新增功能

/// 消息同步管理器
public class IMMessageSyncManager {
    private var lastSyncSeq: Int64 = 0  // 本地最大 seq
    
    /// 增量同步消息
    public func syncMessages(completion: @escaping (Result<Void, Error>) -> Void) {
        let request = SyncRequest(
            lastSeq: lastSyncSeq,
            count: 100  // 每次拉取 100 条
        )
        
        networkManager.syncMessages(request) { [weak self] result in
            switch result {
            case .success(let response):
                // 1. 保存消息到数据库
                self?.saveMessages(response.messages)
                
                // 2. 更新 lastSyncSeq
                self?.lastSyncSeq = response.maxSeq
                
                // 3. 如果还有更多，继续拉取
                if response.hasMore {
                    self?.syncMessages(completion: completion)
                } else {
                    completion(.success(()))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
```

**优先级：高** 🔥

---

### 3️⃣ **消息去重机制** ⭐️⭐️⭐️

**OpenIM 实现：**
```go
// 使用 clientMsgID 去重
func (m *MessageManager) insertMessage(msg *Message) error {
    // 检查是否已存在
    if exists := m.db.IsMessageExists(msg.ClientMsgID); exists {
        return nil  // 已存在，跳过
    }
    
    // 插入数据库
    return m.db.InsertMessage(msg)
}
```

**去重策略：**
1. **客户端生成唯一 ID**：`clientMsgID = UUID()`
2. **服务器返回服务器 ID**：`serverMsgID`
3. **数据库唯一索引**：`CREATE UNIQUE INDEX ON messages(clientMsgID)`
4. **插入前检查**：避免重复插入

**我们当前：**
- ✅ 有 `messageID` 字段（客户端生成）
- ❌ 没有明确的去重逻辑
- ❌ 数据库没有唯一索引

**改进建议：**
```swift
// IMDatabaseManager.swift

public func saveMessage(_ message: IMMessage) throws {
    let realm = try getRealm()
    
    try realm.write {
        // 先检查是否已存在
        if let existing = realm.object(ofType: IMMessage.self, forPrimaryKey: message.messageID) {
            // 消息已存在，更新部分字段
            existing.status = message.status
            existing.serverTime = message.serverTime
            IMLogger.shared.verbose("Message already exists, updated: \(message.messageID)")
        } else {
            // 插入新消息
            realm.add(message, update: .modified)
            IMLogger.shared.verbose("Inserted new message: \(message.messageID)")
        }
    }
}
```

**优先级：高** 🔥

---

### 4️⃣ **消息分页加载（历史消息）** ⭐️⭐️⭐️

**OpenIM 实现：**
```go
// 分页参数
type GetHistoryMessagesReq {
    conversationID string
    startTime      int64   // 起始时间（从这个时间往前查）
    count          int32   // 拉取数量
}

func (m *MessageManager) GetHistoryMessages(req GetHistoryMessagesReq) ([]Message, error) {
    return m.db.GetMessages(
        conversationID: req.conversationID,
        startTime: req.startTime,
        count: req.count,
        order: DESC  // 倒序（最新的在前）
    )
}
```

**使用场景：**
```
用户向上滑动聊天界面时：
1. 加载 20 条历史消息
2. 继续向上滑动，再加载 20 条
3. 直到没有更多消息
```

**我们当前：**
- ✅ 有 `getMessages` 方法
- ❌ 没有明确的分页参数（offset/limit）
- ❌ 没有基于时间的查询

**改进建议：**
```swift
// IMMessageManager.swift

/// 分页获取历史消息
/// - Parameters:
///   - conversationID: 会话 ID
///   - startTime: 起始时间（往前查，0 表示从最新开始）
///   - count: 拉取数量
public func getHistoryMessages(
    conversationID: String,
    startTime: Int64 = 0,
    count: Int = 20
) throws -> [IMMessage] {
    let startTimestamp = startTime > 0 ? startTime : Int64.max
    
    return try database.getMessages(
        conversationID: conversationID,
        beforeTime: startTimestamp,
        limit: count
    )
}

// IMDatabaseManager.swift

public func getMessages(
    conversationID: String,
    beforeTime: Int64,
    limit: Int
) throws -> [IMMessage] {
    let realm = try getRealm()
    
    let results = realm.objects(IMMessage.self)
        .filter("conversationID == %@ AND createTime < %@", conversationID, beforeTime)
        .sorted(byKeyPath: "createTime", ascending: false)
        .prefix(limit)
    
    return Array(results)
}
```

**优先级：高** 🔥

---

### 5️⃣ **输入状态（Typing Indicator）** ⭐️⭐️

**OpenIM 实现：**
```go
// 协议定义
type TypingStatus {
    conversationID string
    userID         string
    isTyping       bool
}

// 客户端发送
func (m *MessageManager) SendTypingStatus(conversationID string) {
    // 发送 typing 状态（不存储，不可靠）
    m.ws.Send(TypingStatus{
        conversationID: conversationID,
        userID:         m.userID,
        isTyping:       true,
    })
}

// 收到 typing 状态
func (m *MessageManager) OnTypingStatusReceived(status TypingStatus) {
    // 通知 UI：对方正在输入...
    m.listener.OnUserTyping(status.conversationID, status.userID)
    
    // 10 秒后自动取消
    time.AfterFunc(10*time.Second, func() {
        m.listener.OnUserStopTyping(status.conversationID, status.userID)
    })
}
```

**特点：**
- 不可靠消息（不等待 ACK）
- 不存储到数据库
- 有过期时间（10 秒）
- 防抖动（1-2 秒内只发送一次）

**我们当前：**
- ❌ 没有实现

**改进建议：**
```swift
// IMProtocolHandler.swift

/// 输入状态
public struct TypingStatus: Codable {
    let conversationID: String
    let userID: String
    let isTyping: Bool
    let timestamp: Int64
}

// 回调
public var onTypingStatus: ((TypingStatus) -> Void)?

// IMMessageManager.swift

/// 发送输入状态
public func sendTypingStatus(conversationID: String) {
    // 防抖动：1 秒内只发送一次
    guard shouldSendTypingStatus(conversationID) else { return }
    
    let status = TypingStatus(
        conversationID: conversationID,
        userID: currentUserID,
        isTyping: true,
        timestamp: IMUtils.currentTimeMillis()
    )
    
    // 发送（不等待 ACK）
    websocket?.send(data: encodeTypingStatus(status))
    
    updateLastTypingTime(conversationID)
}
```

**优先级：中**

---

### 6️⃣ **消息搜索** ⭐️⭐️⭐️

**OpenIM 实现：**
```go
// 搜索参数
type SearchMessagesReq {
    keyword        string   // 搜索关键词
    conversationID string   // 会话 ID（可选）
    messageType    []int32  // 消息类型（可选）
    startTime      int64    // 时间范围（可选）
    endTime        int64
    count          int32    // 返回数量
}

// 数据库查询
func (db *Database) SearchMessages(req SearchMessagesReq) ([]Message, error) {
    query := "SELECT * FROM messages WHERE "
    query += "content LIKE ? "  // 全文搜索
    
    if req.conversationID != "" {
        query += "AND conversationID = ? "
    }
    
    if len(req.messageType) > 0 {
        query += "AND messageType IN (?) "
    }
    
    if req.startTime > 0 {
        query += "AND createTime >= ? AND createTime <= ? "
    }
    
    query += "ORDER BY createTime DESC LIMIT ?"
    
    return db.Query(query, params...)
}
```

**特点：**
1. **全局搜索**：搜索所有会话
2. **会话内搜索**：只搜索当前会话
3. **高级筛选**：按类型、时间范围筛选
4. **全文索引**：数据库建立全文索引（FTS）

**我们当前：**
- ❌ 没有实现

**改进建议：**
```swift
// IMMessageManager.swift

/// 搜索消息
public func searchMessages(
    keyword: String,
    conversationID: String? = nil,
    messageTypes: [IMMessageType]? = nil,
    startTime: Int64 = 0,
    endTime: Int64 = Int64.max,
    limit: Int = 50
) throws -> [IMMessage] {
    return try database.searchMessages(
        keyword: keyword,
        conversationID: conversationID,
        messageTypes: messageTypes,
        startTime: startTime,
        endTime: endTime,
        limit: limit
    )
}

// IMDatabaseManager.swift

public func searchMessages(
    keyword: String,
    conversationID: String?,
    messageTypes: [IMMessageType]?,
    startTime: Int64,
    endTime: Int64,
    limit: Int
) throws -> [IMMessage] {
    let realm = try getRealm()
    var results = realm.objects(IMMessage.self)
    
    // 关键词搜索（内容包含）
    results = results.filter("content CONTAINS[cd] %@", keyword)
    
    // 会话 ID 筛选
    if let convID = conversationID {
        results = results.filter("conversationID == %@", convID)
    }
    
    // 消息类型筛选
    if let types = messageTypes, !types.isEmpty {
        let typeValues = types.map { $0.rawValue }
        results = results.filter("messageType IN %@", typeValues)
    }
    
    // 时间范围筛选
    results = results.filter("createTime >= %@ AND createTime <= %@", startTime, endTime)
    
    // 排序和限制数量
    results = results.sorted(byKeyPath: "createTime", ascending: false)
    
    return Array(results.prefix(limit))
}
```

**优先级：高** 🔥

---

### 7️⃣ **网络状态监听** ⭐️⭐️

**OpenIM 实现：**
```go
// 网络状态监听
type NetworkStatus int

const (
    NetworkUnknown     NetworkStatus = 0
    NetworkWifi        NetworkStatus = 1
    NetworkMobile      NetworkStatus = 2
    NetworkDisconnected NetworkStatus = 3
)

// 监听网络变化
func (m *NetworkManager) StartMonitoring() {
    // iOS: 使用 Reachability
    // Android: 使用 ConnectivityManager
    
    m.reachability.OnNetworkChanged(func(status NetworkStatus) {
        switch status {
        case NetworkWifi, NetworkMobile:
            // 网络恢复，重连 WebSocket
            m.reconnect()
            
        case NetworkDisconnected:
            // 网络断开，关闭连接
            m.disconnect()
        }
        
        // 通知监听器
        m.listener.OnNetworkStatusChanged(status)
    })
}
```

**我们当前：**
- ❌ 没有实现

**改进建议：**
```swift
// 新增文件：IMNetworkMonitor.swift

import Network

/// 网络状态
public enum IMNetworkStatus {
    case unknown
    case wifi
    case cellular
    case disconnected
}

/// 网络监听器
public protocol IMNetworkMonitorDelegate: AnyObject {
    func networkStatusChanged(_ status: IMNetworkStatus)
}

/// 网络状态监控
public class IMNetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.im.network.monitor")
    
    public weak var delegate: IMNetworkMonitorDelegate?
    
    private(set) var currentStatus: IMNetworkStatus = .unknown
    
    public func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = self?.getNetworkStatus(from: path) ?? .unknown
            
            if status != self?.currentStatus {
                self?.currentStatus = status
                
                DispatchQueue.main.async {
                    self?.delegate?.networkStatusChanged(status)
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    public func stopMonitoring() {
        monitor.cancel()
    }
    
    private func getNetworkStatus(from path: NWPath) -> IMNetworkStatus {
        guard path.status == .satisfied else {
            return .disconnected
        }
        
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else {
            return .unknown
        }
    }
}

// IMClient.swift 中集成

private let networkMonitor = IMNetworkMonitor()

public func initialize(config: IMConfig) throws {
    // ... existing code ...
    
    // 启动网络监听
    networkMonitor.delegate = self
    networkMonitor.startMonitoring()
}

extension IMClient: IMNetworkMonitorDelegate {
    public func networkStatusChanged(_ status: IMNetworkStatus) {
        IMLogger.shared.info("Network status changed: \(status)")
        
        switch status {
        case .wifi, .cellular:
            // 网络恢复，自动重连
            if connectionState == .disconnected {
                connect()
            }
            
        case .disconnected:
            // 网络断开
            connectionState = .disconnected
        
        case .unknown:
            break
        }
        
        notifyListeners { $0.onConnectionStateChanged(connectionState) }
    }
}
```

**优先级：中**

---

### 8️⃣ **富媒体消息（图片、音视频、文件）** ⭐️⭐️⭐️

**OpenIM 实现：**
```go
// 图片消息
type ImageMessage {
    sourcePath     string  // 本地原图路径
    sourceURL      string  // 服务器原图 URL
    thumbnailPath  string  // 本地缩略图路径
    thumbnailURL   string  // 服务器缩略图 URL
    width          int32
    height         int32
    size           int64
}

// 发送图片流程
func (m *MessageManager) SendImageMessage(imagePath string) {
    // 1. 生成缩略图
    thumbnail := generateThumbnail(imagePath)
    
    // 2. 上传原图和缩略图到 OSS
    sourceURL := m.uploadFile(imagePath)
    thumbnailURL := m.uploadFile(thumbnail)
    
    // 3. 构造消息
    msg := ImageMessage{
        sourcePath:    imagePath,
        sourceURL:     sourceURL,
        thumbnailPath: thumbnail,
        thumbnailURL:  thumbnailURL,
        width:         getImageWidth(imagePath),
        height:        getImageHeight(imagePath),
        size:          getFileSize(imagePath),
    }
    
    // 4. 发送消息
    m.SendMessage(msg)
}

// 接收图片流程
func (m *MessageManager) OnImageMessageReceived(msg ImageMessage) {
    // 1. 显示缩略图（从 thumbnailURL 下载）
    m.downloadFile(msg.thumbnailURL, msg.thumbnailPath)
    
    // 2. 用户点击后，下载原图
    m.downloadFile(msg.sourceURL, msg.sourcePath)
}
```

**文件上传管理：**
```go
type UploadManager {
    // 上传队列
    queue []UploadTask
    
    // 上传进度回调
    onProgress func(taskID string, progress float64)
    
    // 上传完成回调
    onComplete func(taskID string, url string)
}

// 支持断点续传
func (u *UploadManager) Upload(filePath string) string {
    // 1. 分片上传（大文件）
    chunks := splitFile(filePath, chunkSize: 1MB)
    
    // 2. 并发上传分片
    for _, chunk := range chunks {
        go u.uploadChunk(chunk)
    }
    
    // 3. 合并分片
    u.mergeChunks(chunks)
    
    return fileURL
}
```

**我们当前：**
- ✅ 有消息类型定义（image, audio, video, file）
- ❌ 没有文件上传/下载管理
- ❌ 没有上传进度回调
- ❌ 没有断点续传

**改进建议：**
```swift
// 需要新增模块：IMFileManager.swift

/// 文件上传任务
public class IMUploadTask {
    public let taskID: String
    public let filePath: String
    public private(set) var progress: Double = 0.0
    public private(set) var state: State = .pending
    
    public enum State {
        case pending
        case uploading
        case completed
        case failed
    }
    
    var onProgress: ((Double) -> Void)?
    var onComplete: ((String) -> Void)?  // 返回 URL
    var onError: ((Error) -> Void)?
}

/// 文件管理器
public class IMFileManager {
    private let httpManager: IMHTTPManager
    private var uploadQueue: [IMUploadTask] = []
    private let uploadLock = NSLock()
    
    /// 上传图片
    public func uploadImage(
        _ image: UIImage,
        onProgress: ((Double) -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        // 1. 压缩图片
        let compressedData = compressImage(image, maxSize: 1MB)
        
        // 2. 生成缩略图
        let thumbnail = generateThumbnail(image, size: CGSize(width: 200, height: 200))
        
        // 3. 上传原图和缩略图
        let group = DispatchGroup()
        
        var sourceURL: String?
        var thumbnailURL: String?
        
        group.enter()
        uploadFile(compressedData, fileType: .image) { url in
            sourceURL = url
            group.leave()
        }
        
        group.enter()
        uploadFile(thumbnail, fileType: .thumbnail) { url in
            thumbnailURL = url
            group.leave()
        }
        
        group.notify(queue: .main) {
            onComplete(sourceURL ?? "")
        }
    }
    
    /// 上传文件（支持断点续传）
    private func uploadFile(
        _ data: Data,
        fileType: FileType,
        onProgress: ((Double) -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        // 使用 URLSession uploadTask
        // 支持后台上传
        // 支持断点续传
    }
}
```

**优先级：高** 🔥

---

### 9️⃣ **本地数据库优化（索引、查询优化）** ⭐️⭐️

**OpenIM 实现（SQLite）：**
```sql
-- 创建索引
CREATE INDEX idx_conversation_id ON messages(conversationID);
CREATE INDEX idx_create_time ON messages(createTime);
CREATE INDEX idx_status ON messages(status);
CREATE INDEX idx_seq ON messages(seq);

-- 联合索引（用于分页查询）
CREATE INDEX idx_conv_time ON messages(conversationID, createTime DESC);

-- 全文搜索索引
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    conversationID UNINDEXED,
    messageType UNINDEXED,
    createTime UNINDEXED
);
```

**查询优化：**
```go
// 使用索引的查询（快）
SELECT * FROM messages 
WHERE conversationID = ? AND createTime < ?
ORDER BY createTime DESC
LIMIT 20;

// 没有索引的查询（慢）
SELECT * FROM messages 
WHERE content LIKE '%keyword%';  // 全表扫描
```

**我们当前（Realm）：**
- ✅ Realm 自动为主键建立索引
- ❌ 没有为常用查询字段建立索引
- ❌ 没有查询性能监控

**改进建议：**
```swift
// IMModels.swift

public class IMMessage: Object {
    @Persisted(primaryKey: true) var messageID: String = ""
    @Persisted(indexed: true) var conversationID: String = ""  // ← 添加索引
    @Persisted(indexed: true) var createTime: Int64 = 0         // ← 添加索引
    @Persisted(indexed: true) var seq: Int64 = 0                // ← 添加索引
    @Persisted var messageType: IMMessageType = .text
    @Persisted var status: IMMessageStatus = .sending
    @Persisted var content: String = ""
    // ... other fields ...
}

public class IMConversation: Object {
    @Persisted(primaryKey: true) var conversationID: String = ""
    @Persisted(indexed: true) var lastMessageTime: Int64 = 0   // ← 添加索引
    @Persisted(indexed: true) var isPinned: Bool = false        // ← 添加索引
    // ... other fields ...
}
```

**查询优化建议：**
```swift
// 优化前（慢）
let messages = realm.objects(IMMessage.self)
    .filter("content CONTAINS[cd] %@", keyword)  // 全表扫描

// 优化后（快）
let messages = realm.objects(IMMessage.self)
    .filter("conversationID == %@", conversationID)  // 使用索引
    .filter("createTime < %@", startTime)            // 使用索引
    .sorted(byKeyPath: "createTime", ascending: false)
    .prefix(20)
```

**优先级：中**

---

### 🔟 **性能监控和日志系统** ⭐️⭐️

**OpenIM 实现：**
```go
// 性能监控
type PerformanceMonitor {
    // API 调用耗时
    apiLatency map[string]time.Duration
    
    // 数据库查询耗时
    dbQueryTime map[string]time.Duration
    
    // 内存使用
    memoryUsage int64
    
    // 网络流量
    networkTraffic int64
}

// 使用示例
func (m *MessageManager) SendMessage(msg Message) {
    startTime := time.Now()
    defer func() {
        duration := time.Since(startTime)
        m.monitor.RecordAPILatency("SendMessage", duration)
    }()
    
    // 发送消息逻辑
}

// 日志系统
type Logger {
    level     LogLevel
    output    io.Writer
    enableFile bool  // 是否写入文件
    maxSize   int64  // 日志文件最大大小
}

// 日志级别
const (
    LogVerbose  // 详细日志
    LogDebug    // 调试日志
    LogInfo     // 信息日志
    LogWarning  // 警告日志
    LogError    // 错误日志
)
```

**我们当前：**
- ✅ 有基础日志系统（`IMLogger`）
- ❌ 没有性能监控
- ❌ 没有日志文件管理（轮转、清理）
- ❌ 没有日志上报功能

**改进建议：**
```swift
// 增强 IMLogger.swift

public class IMLogger {
    // ... existing code ...
    
    /// 性能监控
    public class PerformanceMonitor {
        private var metrics: [String: [TimeInterval]] = [:]
        private let lock = NSLock()
        
        /// 记录 API 调用耗时
        public func recordAPILatency(_ apiName: String, duration: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            
            if metrics[apiName] == nil {
                metrics[apiName] = []
            }
            metrics[apiName]?.append(duration)
            
            // 只保留最近 100 次记录
            if let count = metrics[apiName]?.count, count > 100 {
                metrics[apiName]?.removeFirst()
            }
        }
        
        /// 获取平均耗时
        public func getAverageLatency(_ apiName: String) -> TimeInterval? {
            lock.lock()
            defer { lock.unlock() }
            
            guard let durations = metrics[apiName], !durations.isEmpty else {
                return nil
            }
            
            return durations.reduce(0, +) / TimeInterval(durations.count)
        }
    }
    
    public static let performanceMonitor = PerformanceMonitor()
    
    /// 日志文件管理
    private func rotateLogFile() {
        guard let logFileURL = getLogFileURL() else { return }
        
        let fileManager = FileManager.default
        
        // 检查文件大小
        if let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
           let fileSize = attributes[.size] as? Int64,
           fileSize > maxLogFileSize {
            
            // 重命名旧日志文件
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            let newURL = logFileURL.deletingLastPathComponent()
                .appendingPathComponent("im_sdk_\(timestamp).log")
            
            try? fileManager.moveItem(at: logFileURL, to: newURL)
            
            // 清理过期日志（保留最近 7 天）
            cleanupOldLogs()
        }
    }
}

// 使用示例
func sendMessage(_ message: IMMessage) throws -> IMMessage {
    let startTime = Date()
    defer {
        let duration = Date().timeIntervalSince(startTime)
        IMLogger.performanceMonitor.recordAPILatency("sendMessage", duration: duration)
    }
    
    // 发送消息逻辑
}
```

**优先级：中**

---

## 📊 优先级总结

| 优先级 | 功能 | 工作量 | 影响 |
|-------|------|--------|------|
| **🔥 高** | 消息增量同步 | 中 | 提升离线消息同步效率 |
| **🔥 高** | 消息去重机制 | 低 | 避免重复消息 |
| **🔥 高** | 消息分页加载 | 中 | 优化历史消息加载 |
| **🔥 高** | 消息搜索 | 高 | 核心功能 |
| **🔥 高** | 富媒体消息 | 高 | 核心功能 |
| **中** | 输入状态 | 低 | 提升交互体验 |
| **中** | 网络状态监听 | 低 | 提升稳定性 |
| **中** | 数据库优化 | 中 | 提升性能 |
| **中** | 性能监控 | 中 | 辅助调试 |
| **低** | 跨平台支持 | 高 | 非必需（iOS 专用） |

---

## 🎯 实施建议

### 第一阶段（必须实现）
1. ✅ **消息去重机制**
2. ✅ **消息分页加载**
3. ✅ **消息增量同步**

### 第二阶段（核心功能）
4. ✅ **消息搜索**
5. ✅ **富媒体消息**

### 第三阶段（优化提升）
6. ✅ **网络状态监听**
7. ✅ **数据库索引优化**

### 第四阶段（增强体验）
8. ✅ **输入状态**
9. ✅ **性能监控**

---

## 参考资料

1. [OpenIM SDK GitHub](https://github.com/openimsdk/openim-sdk-core)
2. [OpenIM 官方文档](https://docs.openim.io)
3. [OpenIM 架构设计](https://docs.openim.io/guides/introduction/architecture)
4. [OpenIM SDK 介绍](https://docs.openim.io/sdks/introduction)

---

**更新时间：** 2025-10-24  
**作者：** IM SDK Team


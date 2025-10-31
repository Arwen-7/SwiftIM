# 消息分页加载技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [实现细节](#实现细节)
5. [性能优化](#性能优化)
6. [使用示例](#使用示例)

---

## 概述

### 什么是消息分页加载？

**消息分页加载**是指在聊天界面中，用户向上滑动时，**逐步加载**历史消息，而不是一次性加载所有消息。

### 为什么需要分页加载？

**场景：用户打开一个有 10,000 条历史消息的会话**

**不分页（不好）**：
```
- 一次性加载 10,000 条消息
- 内存占用：~200MB
- UI 渲染：卡顿 5-10 秒
- 用户体验：❌ 卡顿、闪退
```

**分页加载（好）**：
```
- 首次加载 20 条最新消息
- 内存占用：~400KB
- UI 渲染：流畅
- 用户向上滑动 → 加载更多 20 条
- 用户体验：✅ 流畅、快速
```

---

## 核心概念

### 1. 分页参数

```swift
struct PaginationParams {
    let conversationID: String    // 会话 ID
    let startTime: Int64           // 起始时间（往前查）
    let count: Int                 // 每页数量
}
```

**工作原理**：
```
时间轴（从新到旧）：
  
  最新消息 ───► 100ms
             ├─── 90ms
             ├─── 80ms
             ├─── 70ms  ← startTime (第一页从这里开始)
  第一页     ├─── 60ms
  (20条)     ├─── 50ms
             ├─── 40ms
             └─── 30ms
  
  第二页     ├─── 20ms  ← startTime (第二页从这里开始)
  (20条)     ├─── 10ms
             └─── 0ms
  
  最早消息 ◄───
```

### 2. 时间倒序查询

**SQL 查询**：
```sql
SELECT * FROM messages 
WHERE conversationID = ? 
  AND createTime < ?          -- 小于 startTime（往前查）
ORDER BY createTime DESC      -- 倒序（最新的在前）
LIMIT ?                       -- 限制数量
```

**Realm 查询**：
```swift
realm.objects(IMMessage.self)
    .filter("conversationID == %@ AND createTime < %@", conversationID, startTime)
    .sorted(byKeyPath: "createTime", ascending: false)
    .prefix(count)
```

### 3. 分页状态

```swift
enum PaginationState {
    case idle          // 空闲
    case loading       // 加载中
    case completed     // 全部加载完毕
    case error(Error)  // 加载失败
}
```

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────┐
│            UIViewController                 │
│  ┌───────────────────────────────────────┐ │
│  │    UITableView / UICollectionView     │ │
│  │  - scrollViewDidScroll                │ │
│  │  - 检测到接近顶部 → 触发加载          │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMMessageManager                    │
│  ┌───────────────────────────────────────┐ │
│  │  getHistoryMessages(                  │ │
│  │    conversationID,                    │ │
│  │    startTime,                         │ │
│  │    count                              │ │
│  │  ) -> [IMMessage]                     │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMDatabaseManager                   │
│  ┌───────────────────────────────────────┐ │
│  │  getMessages(                         │ │
│  │    conversationID,                    │ │
│  │    beforeTime,                        │ │
│  │    limit                              │ │
│  │  ) -> [IMMessage]                     │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 数据流

```
用户向上滑动
   │
   ▼
检测到接近顶部
   │
   ▼
调用 getHistoryMessages()
   │
   ├─ 1. 获取当前最早消息的时间
   │     (如果是首次加载，使用 Int64.max)
   │
   ├─ 2. 查询数据库
   │     WHERE createTime < startTime
   │     ORDER BY createTime DESC
   │     LIMIT 20
   │
   ├─ 3. 返回结果
   │
   └─ 4. 如果结果数 < 20
        └─ 表示已加载完毕
```

---

## 实现细节

### 1. 数据库查询方法

```swift
// IMDatabaseManager.swift

extension IMDatabaseManager {
    
    /// 分页获取消息
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - beforeTime: 起始时间（往前查，0 表示从最新开始）
    ///   - limit: 每页数量
    /// - Returns: 消息列表（按时间倒序）
    public func getMessages(
        conversationID: String,
        beforeTime: Int64 = Int64.max,
        limit: Int = 20
    ) throws -> [IMMessage] {
        let realm = try getRealm()
        
        let results = realm.objects(IMMessage.self)
            .filter("conversationID == %@ AND createTime < %@", conversationID, beforeTime)
            .sorted(byKeyPath: "createTime", ascending: false)
            .prefix(limit)
        
        return Array(results)
    }
    
    /// 获取会话的消息总数
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 消息总数
    public func getMessageCount(conversationID: String) -> Int {
        do {
            let realm = try getRealm()
            return realm.objects(IMMessage.self)
                .filter("conversationID == %@", conversationID)
                .count
        } catch {
            return 0
        }
    }
}
```

### 2. 业务层方法

```swift
// IMMessageManager.swift

extension IMMessageManager {
    
    /// 分页获取历史消息
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - startTime: 起始时间（往前查，0 表示从最新开始）
    ///   - count: 拉取数量（默认 20）
    /// - Returns: 消息列表（按时间倒序）
    public func getHistoryMessages(
        conversationID: String,
        startTime: Int64 = 0,
        count: Int = 20
    ) throws -> [IMMessage] {
        let beforeTime = startTime > 0 ? startTime : Int64.max
        
        let messages = try database.getMessages(
            conversationID: conversationID,
            beforeTime: beforeTime,
            limit: count
        )
        
        IMLogger.shared.debug("Loaded \(messages.count) history messages for conversation: \(conversationID)")
        
        return messages
    }
    
    /// 获取会话的消息总数
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 消息总数
    public func getMessageCount(conversationID: String) -> Int {
        return database.getMessageCount(conversationID: conversationID)
    }
    
    /// 检查是否还有更多历史消息
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - currentCount: 当前已加载数量
    /// - Returns: 是否还有更多
    public func hasMoreMessages(conversationID: String, currentCount: Int) -> Bool {
        let totalCount = getMessageCount(conversationID: conversationID)
        return currentCount < totalCount
    }
}
```

### 3. UI 层集成（示例）

```swift
// ChatViewController.swift

class ChatViewController: UIViewController {
    
    // MARK: - Properties
    
    private let conversationID: String
    private var messages: [IMMessage] = []
    private var isLoadingMore = false
    private var hasMoreMessages = true
    
    private let pageSize = 20
    
    // MARK: - Load Messages
    
    func loadInitialMessages() {
        do {
            // 加载最新的 20 条消息
            messages = try IMClient.shared.messageManager.getHistoryMessages(
                conversationID: conversationID,
                startTime: 0,
                count: pageSize
            )
            
            // 检查是否还有更多
            hasMoreMessages = IMClient.shared.messageManager.hasMoreMessages(
                conversationID: conversationID,
                currentCount: messages.count
            )
            
            tableView.reloadData()
        } catch {
            print("Failed to load messages: \(error)")
        }
    }
    
    func loadMoreMessages() {
        guard !isLoadingMore && hasMoreMessages else { return }
        
        isLoadingMore = true
        
        // 获取当前最早消息的时间
        guard let oldestMessage = messages.last else {
            isLoadingMore = false
            return
        }
        
        do {
            // 加载更早的 20 条消息
            let olderMessages = try IMClient.shared.messageManager.getHistoryMessages(
                conversationID: conversationID,
                startTime: oldestMessage.createTime,
                count: pageSize
            )
            
            // 如果加载到的消息少于 pageSize，说明没有更多了
            if olderMessages.count < pageSize {
                hasMoreMessages = false
            }
            
            // 插入到数组末尾（因为是倒序）
            messages.append(contentsOf: olderMessages)
            
            tableView.reloadData()
        } catch {
            print("Failed to load more messages: \(error)")
        }
        
        isLoadingMore = false
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 检测是否接近顶部（距离顶部 < 200pt）
        let offsetY = scrollView.contentOffset.y
        
        if offsetY < 200 && !isLoadingMore && hasMoreMessages {
            loadMoreMessages()
        }
    }
}
```

---

## 性能优化

### 1. 数据库索引

```swift
// IMModels.swift

public class IMMessage: Object {
    @Persisted(primaryKey: true) var messageID: String = ""
    @Persisted(indexed: true) var conversationID: String = ""  // ← 索引
    @Persisted(indexed: true) var createTime: Int64 = 0         // ← 索引
    @Persisted(indexed: true) var seq: Int64 = 0                // ← 索引
    // ...
}
```

**效果**：
```
无索引：查询 10,000 条消息中的 20 条 → 100ms
有索引：查询 10,000 条消息中的 20 条 → 5ms

性能提升：20x
```

### 2. 缓存策略

```swift
// 缓存最近加载的消息
private let messageCache = IMMemoryCache<[IMMessage]>(countLimit: 50)

func getHistoryMessages(...) -> [IMMessage] {
    // 生成缓存 key
    let cacheKey = "\(conversationID)_\(startTime)_\(count)"
    
    // 先查缓存
    if let cached = messageCache.get(forKey: cacheKey) {
        return cached
    }
    
    // 查询数据库
    let messages = try database.getMessages(...)
    
    // 存入缓存
    messageCache.set(messages, forKey: cacheKey)
    
    return messages
}
```

### 3. 预加载策略

```swift
// 当用户滑动到距离顶部 500pt 时，就开始预加载
let preloadThreshold: CGFloat = 500

func scrollViewDidScroll(_ scrollView: UIScrollView) {
    let offsetY = scrollView.contentOffset.y
    
    if offsetY < preloadThreshold && !isLoadingMore && hasMoreMessages {
        loadMoreMessages()
    }
}
```

### 4. 批量查询优化

```swift
// ❌ 慢：多次查询
for i in 0..<10 {
    let messages = getMessages(conversationID: conv, beforeTime: time - i * 1000, limit: 20)
}

// ✅ 快：一次查询更多
let messages = getMessages(conversationID: conv, beforeTime: time, limit: 200)
```

---

## 使用示例

### Example 1: 基础聊天界面

```swift
class ChatViewController: UIViewController {
    private var messages: [IMMessage] = []
    private let conversationID = "conv_123"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadInitialMessages()
    }
    
    func loadInitialMessages() {
        do {
            // 加载最新的 20 条消息
            messages = try IMClient.shared.messageManager.getHistoryMessages(
                conversationID: conversationID,
                count: 20
            )
            
            tableView.reloadData()
            scrollToBottom()
        } catch {
            showError(error)
        }
    }
    
    func loadMoreMessages() {
        guard let oldestMessage = messages.last else { return }
        
        do {
            let olderMessages = try IMClient.shared.messageManager.getHistoryMessages(
                conversationID: conversationID,
                startTime: oldestMessage.createTime,
                count: 20
            )
            
            messages.append(contentsOf: olderMessages)
            tableView.reloadData()
        } catch {
            showError(error)
        }
    }
}
```

### Example 2: 带加载指示器

```swift
class ChatViewController: UIViewController {
    private let loadingIndicator = UIActivityIndicatorView()
    
    func loadMoreMessages() {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        loadingIndicator.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let olderMessages = try IMClient.shared.messageManager.getHistoryMessages(
                    conversationID: self.conversationID,
                    startTime: self.messages.last?.createTime ?? 0,
                    count: 20
                )
                
                DispatchQueue.main.async {
                    self.messages.append(contentsOf: olderMessages)
                    self.tableView.reloadData()
                    self.loadingIndicator.stopAnimating()
                    self.isLoadingMore = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                    self.loadingIndicator.stopAnimating()
                    self.isLoadingMore = false
                }
            }
        }
    }
}
```

### Example 3: 完整的分页管理

```swift
class MessagePaginationManager {
    private let conversationID: String
    private var messages: [IMMessage] = []
    private var isLoadingMore = false
    private var hasMoreMessages = true
    
    private let pageSize = 20
    
    init(conversationID: String) {
        self.conversationID = conversationID
    }
    
    func loadInitialMessages(completion: @escaping ([IMMessage]) -> Void) {
        do {
            messages = try IMClient.shared.messageManager.getHistoryMessages(
                conversationID: conversationID,
                count: pageSize
            )
            
            hasMoreMessages = IMClient.shared.messageManager.hasMoreMessages(
                conversationID: conversationID,
                currentCount: messages.count
            )
            
            completion(messages)
        } catch {
            print("Failed to load initial messages: \(error)")
            completion([])
        }
    }
    
    func loadMoreMessages(completion: @escaping ([IMMessage]) -> Void) {
        guard !isLoadingMore && hasMoreMessages else {
            completion([])
            return
        }
        
        isLoadingMore = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let startTime = self.messages.last?.createTime ?? 0
                
                let olderMessages = try IMClient.shared.messageManager.getHistoryMessages(
                    conversationID: self.conversationID,
                    startTime: startTime,
                    count: self.pageSize
                )
                
                if olderMessages.count < self.pageSize {
                    self.hasMoreMessages = false
                }
                
                self.messages.append(contentsOf: olderMessages)
                
                DispatchQueue.main.async {
                    completion(olderMessages)
                    self.isLoadingMore = false
                }
            } catch {
                DispatchQueue.main.async {
                    completion([])
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    func hasMore() -> Bool {
        return hasMoreMessages
    }
}
```

---

## 测试场景

### 1. 首次加载
```
Given: 会话有 1000 条消息
When: 打开聊天界面
Then: 只加载最新的 20 条消息
```

### 2. 向上滑动加载更多
```
Given: 已加载 20 条消息
When: 用户向上滑动到顶部
Then: 加载更早的 20 条消息
```

### 3. 全部加载完毕
```
Given: 会话只有 15 条消息
When: 首次加载
Then: 加载 15 条消息，标记为无更多
```

### 4. 性能测试
```
Given: 会话有 100,000 条消息
When: 分页加载
Then: 每次查询耗时 < 50ms
```

---

## 与服务器同步

### 场景：本地没有历史消息

```swift
func loadMoreMessages() {
    // 1. 先查本地
    let localMessages = try database.getMessages(...)
    
    // 2. 如果本地没有，从服务器拉取
    if localMessages.isEmpty {
        httpManager.fetchHistoryMessages(conversationID: conversationID) { result in
            switch result {
            case .success(let serverMessages):
                // 保存到本地
                try? database.saveMessages(serverMessages)
                
                // 返回给 UI
                completion(serverMessages)
                
            case .failure(let error):
                completion([])
            }
        }
    } else {
        completion(localMessages)
    }
}
```

---

## 总结

### 核心要点

1. ✅ **基于时间的分页查询**
   - `WHERE createTime < startTime`
   - `ORDER BY createTime DESC`
   - `LIMIT count`

2. ✅ **数据库索引优化**
   - conversationID 索引
   - createTime 索引

3. ✅ **缓存策略**
   - 内存缓存最近查询
   - 避免重复数据库查询

4. ✅ **预加载策略**
   - 提前触发加载
   - 提升用户体验

5. ✅ **状态管理**
   - isLoadingMore
   - hasMoreMessages

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


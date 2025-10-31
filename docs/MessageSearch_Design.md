# 消息搜索技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [实现细节](#实现细节)
5. [性能优化](#性能优化)
6. [使用示例](#使用示例)

---

## 概述

### 什么是消息搜索？

**消息搜索**是指用户可以通过关键词在聊天消息中快速查找相关内容，支持全局搜索和会话内搜索。

### 为什么需要消息搜索？

**场景：用户想找到某条包含"会议"的消息**

**无搜索功能（不好）**：
```
- 手动滑动查看历史消息
- 耗时：5-10 分钟
- 可能遗漏
- 用户体验：❌ 低效、困难
```

**有搜索功能（好）**：
```
- 输入关键词"会议"
- 1 秒内找到所有相关消息
- 按时间排序
- 用户体验：✅ 快速、准确
```

---

## 核心概念

### 1. 搜索类型

#### 全局搜索
```swift
// 搜索所有会话中的消息
searchMessages(keyword: "重要文件")
// 返回：所有包含"重要文件"的消息
```

#### 会话内搜索
```swift
// 只搜索指定会话
searchMessages(
    keyword: "重要文件",
    conversationID: "conv_123"
)
// 返回：该会话中包含"重要文件"的消息
```

### 2. 搜索参数

```swift
struct SearchParams {
    let keyword: String                // 搜索关键词
    let conversationID: String?        // 会话 ID（可选）
    let messageTypes: [IMMessageType]? // 消息类型筛选（可选）
    let startTime: Int64?              // 时间范围 - 开始（可选）
    let endTime: Int64?                // 时间范围 - 结束（可选）
    let limit: Int                     // 返回数量限制
}
```

### 3. 搜索算法

**Realm 全文搜索**：
```swift
// CONTAINS[cd] - 不区分大小写的包含匹配
realm.objects(IMMessage.self)
    .filter("content CONTAINS[cd] %@", keyword)
```

**匹配规则**：
- `CONTAINS[cd]`：包含（不区分大小写）
- `[c]`：不区分大小写
- `[d]`：忽略变音符号

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────┐
│            UIViewController                 │
│  ┌───────────────────────────────────────┐ │
│  │    UISearchBar                        │ │
│  │  - textDidChange                      │ │
│  │  - 触发搜索                           │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMMessageManager                    │
│  ┌───────────────────────────────────────┐ │
│  │  searchMessages(                      │ │
│  │    keyword,                           │ │
│  │    conversationID,                    │ │
│  │    messageTypes,                      │ │
│  │    startTime, endTime,                │ │
│  │    limit                              │ │
│  │  ) -> [IMMessage]                     │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMDatabaseManager                   │
│  ┌───────────────────────────────────────┐ │
│  │  searchMessages(...)                  │ │
│  │  - 构建查询条件                       │ │
│  │  - 全文搜索                           │ │
│  │  - 类型筛选                           │ │
│  │  - 时间范围筛选                       │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 数据流

```
用户输入关键词
   │
   ▼
触发搜索
   │
   ├─ 1. 构建查询条件
   │     - 关键词：content CONTAINS "关键词"
   │     - 会话 ID：conversationID == "..."（可选）
   │     - 消息类型：messageType IN [...]（可选）
   │     - 时间范围：createTime >= start AND createTime <= end（可选）
   │
   ├─ 2. 执行查询
   │     filter(...).sorted(...).prefix(limit)
   │
   ├─ 3. 返回结果
   │     按时间倒序（最新的在前）
   │
   └─ 4. 显示结果
        UITableView / UICollectionView
```

---

## 实现细节

### 1. 数据库搜索方法

```swift
// IMDatabaseManager.swift

extension IMDatabaseManager {
    
    /// 搜索消息
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选，nil 表示全局搜索）
    ///   - messageTypes: 消息类型筛选（可选）
    ///   - startTime: 开始时间（可选）
    ///   - endTime: 结束时间（可选）
    ///   - limit: 返回数量限制
    /// - Returns: 消息列表
    public func searchMessages(
        keyword: String,
        conversationID: String? = nil,
        messageTypes: [IMMessageType]? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 50
    ) throws -> [IMMessage] {
        guard !keyword.isEmpty else {
            return []
        }
        
        let realm = try getRealm()
        
        // 基础查询条件
        var predicateFormat = "content CONTAINS[cd] %@ AND isDeleted == false"
        var arguments: [Any] = [keyword]
        
        // 会话 ID 筛选
        if let convID = conversationID {
            predicateFormat += " AND conversationID == %@"
            arguments.append(convID)
        }
        
        // 消息类型筛选
        if let types = messageTypes, !types.isEmpty {
            let typeValues = types.map { $0.rawValue }
            predicateFormat += " AND messageType IN %@"
            arguments.append(typeValues)
        }
        
        // 时间范围筛选
        if let start = startTime {
            predicateFormat += " AND createTime >= %@"
            arguments.append(start)
        }
        
        if let end = endTime {
            predicateFormat += " AND createTime <= %@"
            arguments.append(end)
        }
        
        // 构建 NSPredicate
        let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
        
        // 执行查询
        let results = realm.objects(IMMessage.self)
            .filter(predicate)
            .sorted(byKeyPath: "createTime", ascending: false)
            .prefix(limit)
        
        return Array(results)
    }
    
    /// 搜索消息数量
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选）
    /// - Returns: 匹配的消息数量
    public func searchMessageCount(
        keyword: String,
        conversationID: String? = nil
    ) -> Int {
        guard !keyword.isEmpty else {
            return 0
        }
        
        do {
            let realm = try getRealm()
            
            var predicateFormat = "content CONTAINS[cd] %@ AND isDeleted == false"
            var arguments: [Any] = [keyword]
            
            if let convID = conversationID {
                predicateFormat += " AND conversationID == %@"
                arguments.append(convID)
            }
            
            let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
            
            return realm.objects(IMMessage.self)
                .filter(predicate)
                .count
        } catch {
            IMLogger.shared.error("Failed to get search count: \(error)")
            return 0
        }
    }
}
```

### 2. 业务层方法

```swift
// IMMessageManager.swift

extension IMMessageManager {
    
    /// 搜索消息
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选，nil 表示全局搜索）
    ///   - messageTypes: 消息类型筛选（可选）
    ///   - startTime: 开始时间（可选）
    ///   - endTime: 结束时间（可选）
    ///   - limit: 返回数量限制
    /// - Returns: 消息列表
    public func searchMessages(
        keyword: String,
        conversationID: String? = nil,
        messageTypes: [IMMessageType]? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 50
    ) throws -> [IMMessage] {
        // 去除首尾空格
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKeyword.isEmpty else {
            IMLogger.shared.warning("Search keyword is empty")
            return []
        }
        
        let messages = try database.searchMessages(
            keyword: trimmedKeyword,
            conversationID: conversationID,
            messageTypes: messageTypes,
            startTime: startTime,
            endTime: endTime,
            limit: limit
        )
        
        IMLogger.shared.info("Search found \(messages.count) messages for keyword: '\(trimmedKeyword)'")
        
        return messages
    }
    
    /// 搜索消息数量
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选）
    /// - Returns: 匹配的消息数量
    public func searchMessageCount(
        keyword: String,
        conversationID: String? = nil
    ) -> Int {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKeyword.isEmpty else {
            return 0
        }
        
        return database.searchMessageCount(
            keyword: trimmedKeyword,
            conversationID: conversationID
        )
    }
}
```

---

## 性能优化

### 1. 数据库索引

虽然全文搜索不能使用索引，但其他筛选条件可以：

```swift
// 已有的索引
@Persisted(indexed: true) var conversationID: String = ""
@Persisted(indexed: true) var createTime: Int64 = 0
@Persisted(indexed: true) var messageType: IMMessageType = .text

// 查询优化
// 1. 先使用索引字段筛选（conversationID, createTime, messageType）
// 2. 再进行全文搜索（content CONTAINS）
```

### 2. 限制返回数量

```swift
// 避免一次性返回太多结果
let limit = 50  // 默认最多返回 50 条

// 如果需要更多，可以分页
```

### 3. 异步搜索

```swift
// UI 层异步执行搜索
DispatchQueue.global(qos: .userInitiated).async {
    let results = try? IMClient.shared.messageManager.searchMessages(
        keyword: keyword
    )
    
    DispatchQueue.main.async {
        self.displayResults(results ?? [])
    }
}
```

### 4. 防抖动（Debounce）

```swift
// 用户输入时，延迟 300ms 后再搜索
private var searchTimer: Timer?

func searchBarTextDidChange(_ searchBar: UISearchBar) {
    searchTimer?.invalidate()
    
    searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
        self?.performSearch(searchBar.text ?? "")
    }
}
```

### 5. 高亮显示

```swift
// 搜索结果中高亮显示关键词
func highlightKeyword(in text: String, keyword: String) -> NSAttributedString {
    let attributedString = NSMutableAttributedString(string: text)
    
    let regex = try? NSRegularExpression(pattern: keyword, options: .caseInsensitive)
    let range = NSRange(location: 0, length: text.utf16.count)
    
    regex?.enumerateMatches(in: text, range: range) { match, _, _ in
        if let matchRange = match?.range {
            attributedString.addAttribute(
                .backgroundColor,
                value: UIColor.yellow,
                range: matchRange
            )
        }
    }
    
    return attributedString
}
```

---

## 使用示例

### Example 1: 基础全局搜索

```swift
class SearchViewController: UIViewController {
    
    func search(keyword: String) {
        do {
            // 全局搜索
            let messages = try IMClient.shared.messageManager.searchMessages(
                keyword: keyword,
                limit: 50
            )
            
            print("Found \(messages.count) messages")
            displayResults(messages)
        } catch {
            print("Search failed: \(error)")
        }
    }
}
```

### Example 2: 会话内搜索

```swift
class ChatViewController: UIViewController {
    let conversationID = "conv_123"
    
    func searchInConversation(keyword: String) {
        do {
            // 只搜索当前会话
            let messages = try IMClient.shared.messageManager.searchMessages(
                keyword: keyword,
                conversationID: conversationID,
                limit: 50
            )
            
            displayResults(messages)
        } catch {
            print("Search failed: \(error)")
        }
    }
}
```

### Example 3: 高级筛选

```swift
func advancedSearch() {
    do {
        // 搜索最近 7 天内的图片消息
        let endTime = Int64(Date().timeIntervalSince1970 * 1000)
        let startTime = endTime - 7 * 24 * 3600 * 1000
        
        let messages = try IMClient.shared.messageManager.searchMessages(
            keyword: "照片",
            messageTypes: [.image],
            startTime: startTime,
            endTime: endTime,
            limit: 50
        )
        
        print("Found \(messages.count) image messages in last 7 days")
    } catch {
        print("Search failed: \(error)")
    }
}
```

### Example 4: 实时搜索（带防抖动）

```swift
class SearchViewController: UIViewController, UISearchBarDelegate {
    
    private var searchTimer: Timer?
    private var currentSearchTask: DispatchWorkItem?
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // 取消之前的定时器
        searchTimer?.invalidate()
        
        // 取消之前的搜索任务
        currentSearchTask?.cancel()
        
        guard !searchText.isEmpty else {
            clearResults()
            return
        }
        
        // 延迟 300ms 后再搜索
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performSearch(searchText)
        }
    }
    
    private func performSearch(_ keyword: String) {
        // 创建搜索任务
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            do {
                let messages = try IMClient.shared.messageManager.searchMessages(
                    keyword: keyword,
                    limit: 50
                )
                
                DispatchQueue.main.async {
                    guard !task.isCancelled else { return }
                    self.displayResults(messages)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
        
        currentSearchTask = task
        
        // 在后台线程执行
        DispatchQueue.global(qos: .userInitiated).async(execute: task)
    }
}
```

### Example 5: 搜索结果分组（按会话）

```swift
func searchAndGroupByConversation(keyword: String) {
    do {
        let messages = try IMClient.shared.messageManager.searchMessages(
            keyword: keyword,
            limit: 100
        )
        
        // 按会话分组
        let groupedMessages = Dictionary(grouping: messages) { $0.conversationID }
        
        for (convID, messages) in groupedMessages {
            print("Conversation \(convID): \(messages.count) messages")
        }
    } catch {
        print("Search failed: \(error)")
    }
}
```

---

## 测试场景

### 1. 基础搜索
```
Given: 有 100 条消息，其中 10 条包含"重要"
When: 搜索"重要"
Then: 返回 10 条消息
```

### 2. 不区分大小写
```
Given: 消息内容为"Important"
When: 搜索"important"
Then: 能够匹配
```

### 3. 会话内搜索
```
Given: 会话 A 有 5 条包含"会议"的消息，会话 B 有 3 条
When: 在会话 A 内搜索"会议"
Then: 只返回会话 A 的 5 条消息
```

### 4. 类型筛选
```
Given: 有文本消息和图片消息都包含"文件"
When: 搜索"文件"，只选择文本消息
Then: 只返回文本消息
```

### 5. 时间范围
```
Given: 有今天的消息和昨天的消息都包含"报告"
When: 搜索"报告"，时间范围为今天
Then: 只返回今天的消息
```

### 6. 空关键词
```
Given: 关键词为空字符串
When: 执行搜索
Then: 返回空数组
```

### 7. 性能测试
```
Given: 有 10,000 条消息
When: 搜索某个关键词
Then: 查询时间 < 500ms
```

---

## 与 UI 集成

### 搜索界面设计

```
┌─────────────────────────────────────┐
│  ← Back    🔍 Search                │  ← Navigation Bar
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │ 🔍  Search messages...        │  │  ← Search Bar
│  └───────────────────────────────┘  │
├─────────────────────────────────────┤
│  Filters: [All] [Images] [Files]   │  ← 筛选按钮
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📝 会话 A                   │   │
│  │ 找到关键词的消息内容...     │   │  ← 搜索结果
│  │ 2 hours ago                │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📝 会话 B                   │   │
│  │ 另一条包含关键词的消息...   │   │
│  │ Yesterday                  │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

---

## 总结

### 核心要点

1. ✅ **全文搜索**：使用 `CONTAINS[cd]` 实现不区分大小写的搜索
2. ✅ **灵活筛选**：支持会话、类型、时间范围筛选
3. ✅ **性能优化**：限制返回数量、异步执行、防抖动
4. ✅ **用户体验**：实时搜索、高亮显示、结果分组

### 预期效果

| 指标 | 目标 |
|------|------|
| 搜索速度 | < 500ms (10,000 条消息) |
| 准确率 | 100% |
| 用户体验 | ⭐️⭐️⭐️⭐️⭐️ |

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


# 会话未读计数技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [实现细节](#实现细节)
5. [使用示例](#使用示例)

---

## 概述

### 什么是会话未读计数？

**会话未读计数**是指统计每个会话中用户未读的消息数量，并在会话列表中显示小红点或数字角标。

### 为什么需要未读计数？

**场景：用户有多个聊天会话**

**无未读计数（不好）**：
```
会话列表：
  - 张三
  - 李四
  - 王五

问题：
  - 不知道哪个会话有新消息
  - 不知道有多少条未读
  - 容易遗漏重要消息
  - 用户体验：❌ 差
```

**有未读计数（好）**：
```
会话列表：
  - 张三 [5]    ← 5条未读
  - 李四 [99+]  ← 99+条未读
  - 王五        ← 已读

效果：
  ✅ 一目了然哪个会话有新消息
  ✅ 知道未读数量
  ✅ 总角标提醒（App 图标）
  ✅ 用户体验：优秀
```

---

## 核心概念

### 1. 未读计数来源

```swift
// 未读消息来源
1. 接收新消息（对方发来的）
2. 同步离线消息（登录时）
3. 其他设备已读（多端同步）
```

### 2. 已读标记

```swift
// 标记已读的时机
1. 打开会话
2. 查看消息
3. 手动标记为已读
4. 其他设备已读（同步）
```

### 3. 未读计数规则

```swift
// 计数规则
未读数 = 收到的消息数 - 已读的消息数

// 特殊规则
- 自己发送的消息：不计入未读
- 已撤回的消息：减少未读数
- 已读消息：从未读中移除
- 系统消息：可配置是否计入
```

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────┐
│          UITableView (会话列表)             │
│  ┌───────────────────────────────────────┐ │
│  │  Cell 1: 张三  [5]   ← 显示未读数    │ │
│  │  Cell 2: 李四  [99+]                 │ │
│  │  Cell 3: 王五                        │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│     IMConversationManager                   │
│  ┌───────────────────────────────────────┐ │
│  │  getUnreadCount(conversationID)       │ │
│  │  markAsRead(conversationID)           │ │
│  │  getTotalUnreadCount()                │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMConversation (Realm)              │
│  ┌───────────────────────────────────────┐ │
│  │  unreadCount: Int                     │ │
│  │  lastReadTime: Int64                  │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 数据流

#### 收到新消息
```
收到新消息
   │
   ├─ 判断：是否是自己发的？
   │   └─ 是 → 不增加未读数
   │   └─ 否 → 继续
   │
   ├─ 判断：当前是否在该会话？
   │   └─ 是 → 标记为已读，不增加
   │   └─ 否 → 未读数 +1
   │
   ├─ 更新会话未读数
   │
   └─ 通知 UI 刷新
```

#### 标记已读
```
打开会话
   │
   ├─ 获取会话未读数
   │
   ├─ 标记所有消息为已读
   │   └─ 更新 lastReadTime
   │
   ├─ 未读数清零
   │
   └─ 通知 UI 刷新
```

---

## 实现细节

### 1. 数据模型扩展

```swift
// IMConversation.swift

public class IMConversation: Object {
    // ... 现有字段 ...
    
    /// 未读消息数
    @Persisted public var unreadCount: Int = 0
    
    /// 最后已读时间（用于判断哪些消息未读）
    @Persisted public var lastReadTime: Int64 = 0
    
    /// 是否免打扰（免打扰时不计入总未读）
    @Persisted public var isMuted: Bool = false
}
```

### 2. 数据库方法

```swift
// IMDatabaseManager.swift

extension IMDatabaseManager {
    
    /// 增加未读数
    public func incrementUnreadCount(conversationID: String, by count: Int = 1) throws {
        let realm = try getRealm()
        
        try realm.write {
            if let conversation = realm.object(ofType: IMConversation.self, forPrimaryKey: conversationID) {
                conversation.unreadCount += count
                conversation.updateTime = IMUtils.currentTimeMillis()
            }
        }
    }
    
    /// 清空未读数
    public func clearUnreadCount(conversationID: String) throws {
        let realm = try getRealm()
        
        try realm.write {
            if let conversation = realm.object(ofType: IMConversation.self, forPrimaryKey: conversationID) {
                conversation.unreadCount = 0
                conversation.lastReadTime = IMUtils.currentTimeMillis()
            }
        }
    }
    
    /// 获取未读数
    public func getUnreadCount(conversationID: String) -> Int {
        do {
            let realm = try getRealm()
            return realm.object(ofType: IMConversation.self, forPrimaryKey: conversationID)?.unreadCount ?? 0
        } catch {
            IMLogger.shared.error("Failed to get unread count: \(error)")
            return 0
        }
    }
    
    /// 获取总未读数（排除免打扰）
    public func getTotalUnreadCount() -> Int {
        do {
            let realm = try getRealm()
            let conversations = realm.objects(IMConversation.self)
                .filter("isMuted == false")
            
            return conversations.reduce(0) { $0 + $1.unreadCount }
        } catch {
            IMLogger.shared.error("Failed to get total unread count: \(error)")
            return 0
        }
    }
    
    /// 计算会话未读数（基于消息时间）
    public func calculateUnreadCount(conversationID: String) -> Int {
        do {
            let realm = try getRealm()
            
            guard let conversation = realm.object(ofType: IMConversation.self, forPrimaryKey: conversationID) else {
                return 0
            }
            
            let lastReadTime = conversation.lastReadTime
            
            // 统计在 lastReadTime 之后的未读消息
            let unreadMessages = realm.objects(IMMessage.self)
                .filter("conversationID == %@ AND createTime > %@ AND direction == %@ AND isDeleted == false",
                       conversationID, lastReadTime, IMMessageDirection.receive.rawValue)
            
            return unreadMessages.count
        } catch {
            IMLogger.shared.error("Failed to calculate unread count: \(error)")
            return 0
        }
    }
}
```

### 3. 业务层方法

```swift
// IMConversationManager.swift

extension IMConversationManager {
    
    /// 获取会话未读数
    public func getUnreadCount(conversationID: String) -> Int {
        return database.getUnreadCount(conversationID: conversationID)
    }
    
    /// 标记会话为已读
    public func markAsRead(conversationID: String) throws {
        try database.clearUnreadCount(conversationID: conversationID)
        
        // 通知监听器
        notifyConversationChanged(conversationID: conversationID)
        
        IMLogger.shared.info("Marked conversation as read: \(conversationID)")
    }
    
    /// 获取总未读数
    public func getTotalUnreadCount() -> Int {
        return database.getTotalUnreadCount()
    }
    
    /// 设置免打扰
    public func setMuted(conversationID: String, muted: Bool) throws {
        let realm = try database.getRealm()
        
        try realm.write {
            if let conversation = realm.object(ofType: IMConversation.self, forPrimaryKey: conversationID) {
                conversation.isMuted = muted
            }
        }
        
        // 通知监听器
        notifyConversationChanged(conversationID: conversationID)
    }
}
```

### 4. 消息接收时自动更新

```swift
// IMMessageManager.swift

extension IMMessageManager {
    
    private func handleReceivedMessage(_ message: IMMessage) {
        // 保存消息
        try? database.saveMessage(message)
        
        // 判断：是否需要增加未读数
        let shouldIncrement = message.direction == .receive && 
                             !isCurrentConversationActive(message.conversationID)
        
        if shouldIncrement {
            // 增加未读数
            try? database.incrementUnreadCount(conversationID: message.conversationID)
        }
        
        // 通知监听器
        notifyMessageListeners(message)
    }
    
    private func isCurrentConversationActive(_ conversationID: String) -> Bool {
        // 判断当前是否正在查看该会话
        // 可以通过设置 currentConversationID 来追踪
        return currentConversationID == conversationID
    }
}
```

---

## 使用示例

### Example 1: 会话列表显示未读数

```swift
class ConversationListViewController: UITableViewController {
    
    var conversations: [IMConversation] = []
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConversationCell", for: indexPath)
        let conversation = conversations[indexPath.row]
        
        // 显示会话标题
        cell.textLabel?.text = conversation.title
        
        // 显示未读数
        let unreadCount = IMClient.shared.conversationManager.getUnreadCount(
            conversationID: conversation.conversationID
        )
        
        if unreadCount > 0 {
            cell.detailTextLabel?.text = "[\(unreadCount)]"
            cell.detailTextLabel?.textColor = .red
        } else {
            cell.detailTextLabel?.text = ""
        }
        
        return cell
    }
}
```

### Example 2: 打开会话时标记已读

```swift
class ChatViewController: UIViewController {
    
    let conversationID = "conv_123"
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 标记为已读
        try? IMClient.shared.conversationManager.markAsRead(conversationID: conversationID)
        
        // 设置当前活跃会话（新消息不增加未读数）
        IMClient.shared.messageManager.setCurrentConversation(conversationID)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 清除当前活跃会话
        IMClient.shared.messageManager.setCurrentConversation(nil)
    }
}
```

### Example 3: 显示总未读数（App 角标）

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func updateBadgeCount() {
        let totalUnread = IMClient.shared.conversationManager.getTotalUnreadCount()
        
        // 更新 App 图标角标
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = totalUnread
        }
    }
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
}
```

### Example 4: 监听未读数变化

```swift
class ConversationListViewController: UITableViewController, IMConversationListener {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 添加监听器
        IMClient.shared.conversationManager.addListener(self)
    }
    
    // MARK: - IMConversationListener
    
    func onConversationChanged(conversation: IMConversation) {
        // 刷新会话列表
        DispatchQueue.main.async {
            if let index = self.conversations.firstIndex(where: { $0.conversationID == conversation.conversationID }) {
                let indexPath = IndexPath(row: index, section: 0)
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        
        // 更新角标
        updateBadge()
    }
    
    private func updateBadge() {
        let totalUnread = IMClient.shared.conversationManager.getTotalUnreadCount()
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = totalUnread
        }
    }
}
```

### Example 5: 免打扰功能

```swift
class ConversationSettingsViewController: UITableViewController {
    
    @IBAction func muteToggled(_ sender: UISwitch) {
        try? IMClient.shared.conversationManager.setMuted(
            conversationID: conversationID,
            muted: sender.isOn
        )
        
        // 更新总未读数（免打扰不计入）
        updateTotalBadge()
    }
}
```

---

## 性能优化

### 1. 使用索引

```swift
// IMConversation 已有索引
@Persisted(indexed: true) var updateTime: Int64
```

### 2. 缓存总未读数

```swift
class UnreadCountCache {
    private var cachedTotal: Int = 0
    private var lastUpdateTime: TimeInterval = 0
    private let cacheInterval: TimeInterval = 1.0  // 1秒缓存
    
    func getTotalUnreadCount(refresh: Bool = false) -> Int {
        let now = Date().timeIntervalSince1970
        
        if refresh || now - lastUpdateTime > cacheInterval {
            cachedTotal = database.getTotalUnreadCount()
            lastUpdateTime = now
        }
        
        return cachedTotal
    }
}
```

### 3. 批量更新

```swift
// 同步离线消息时，批量更新未读数
func syncOfflineMessages(messages: [IMMessage]) {
    var unreadCountChanges: [String: Int] = [:]
    
    for message in messages where message.direction == .receive {
        unreadCountChanges[message.conversationID, default: 0] += 1
    }
    
    // 批量更新
    try? database.batchUpdateUnreadCount(unreadCountChanges)
}
```

---

## 测试场景

### 1. 接收消息增加未读
```
Given: 会话 A 未读数为 0
When: 收到 3 条新消息
Then: 未读数变为 3
```

### 2. 打开会话清零
```
Given: 会话 A 未读数为 5
When: 打开会话 A
Then: 未读数变为 0
```

### 3. 自己发送不计入
```
Given: 会话 A 未读数为 0
When: 自己发送消息
Then: 未读数仍为 0
```

### 4. 免打扰不计入总数
```
Given: 会话 A 未读 5，免打扰；会话 B 未读 3，未免打扰
When: 计算总未读数
Then: 总未读数为 3（不包括 A）
```

### 5. 多端同步
```
Given: 在设备 A 上标记为已读
When: 设备 B 同步
Then: 设备 B 的未读数也清零
```

---

## 总结

### 核心要点

1. ✅ **实时更新**：收到消息立即更新未读数
2. ✅ **自动清零**：打开会话自动标记已读
3. ✅ **总数统计**：显示 App 角标
4. ✅ **免打扰**：免打扰会话不计入总数
5. ✅ **性能优化**：使用缓存和批量更新

### 预期效果

| 功能 | 效果 |
|------|------|
| 未读提醒 | ✅ 清晰明了 |
| 角标显示 | ✅ 实时更新 |
| 性能 | ✅ 流畅无卡顿 |

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


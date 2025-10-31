# 输入状态同步技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [实现细节](#实现细节)
5. [使用示例](#使用示例)

---

## 概述

### 什么是输入状态同步？

**输入状态同步**是指在聊天过程中，实时显示"对方正在输入..."的提示，让用户知道对方正在准备回复消息。

### 为什么需要输入状态同步？

**场景：用户在等待对方回复**

**无输入状态（不好）**：
```
用户：你在吗？
  - 对方正在打字，但没有任何提示
  - 用户不知道对方是否看到消息
  - 用户可能会继续发送催促消息
  - 用户体验：❌ 缺乏互动感
```

**有输入状态（好）**：
```
用户：你在吗？
  ↓
界面显示："对方正在输入..."
  ↓
用户知道对方正在回复
  - 不会继续发送催促消息
  - 有互动感和期待感
  - 用户体验：✅ 良好，有即时反馈
```

---

## 核心概念

### 1. 输入状态类型

```swift
/// 输入状态
public enum IMTypingStatus {
    case typing     // 正在输入
    case stop       // 停止输入
}
```

### 2. 输入状态事件

```swift
/// 输入状态
public struct IMTypingState {
    let conversationID: String  // 会话 ID
    let userID: String          // 用户 ID
    let status: IMTypingStatus  // 状态
    let timestamp: Int64        // 时间戳
}
```

### 3. 核心机制

#### 发送方（正在输入的用户）
```
用户开始输入（textDidChange）
  ↓
发送 "typing" 状态
  ↓
防抖动（5秒内不重复发送）
  ↓
用户停止输入 3 秒
  ↓
发送 "stop" 状态
```

#### 接收方（看到提示的用户）
```
收到 "typing" 状态
  ↓
显示 "对方正在输入..."
  ↓
10 秒自动超时
  ↓
隐藏提示
```

### 4. 关键参数

```swift
// 发送端
let typingInterval: TimeInterval = 5.0      // 5秒内不重复发送
let stopDelay: TimeInterval = 3.0           // 3秒未输入则发送停止

// 接收端
let typingTimeout: TimeInterval = 10.0      // 10秒超时自动隐藏
```

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────┐
│            UIViewController                 │
│  ┌───────────────────────────────────────┐ │
│  │    UITextView                         │ │
│  │  - textDidChange                      │ │
│  │  - 触发输入状态                       │ │
│  └───────────────────────────────────────┘ │
│  ┌───────────────────────────────────────┐ │
│  │    Typing Indicator View              │ │
│  │  - 显示 "正在输入..."                │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMTypingManager (新增)              │
│  ┌───────────────────────────────────────┐ │
│  │  sendTyping(conversationID)           │ │
│  │  stopTyping(conversationID)           │ │
│  │  防抖动 / 自动停止 / 超时管理         │ │
│  └───────────────────────────────────────┘ │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│         IMProtocolHandler                   │
│  - 发送输入状态协议包                       │
│  - 接收输入状态协议包                       │
└─────────────────────────────────────────────┘
```

### 数据流

#### 发送输入状态
```
用户输入文字
   │
   ▼
UITextView.textDidChange
   │
   ▼
IMTypingManager.sendTyping(conversationID)
   │
   ├─ 检查防抖动（5秒内不重复发送）
   ├─ 启动自动停止定时器（3秒后）
   │
   ▼
IMProtocolHandler.sendTypingPacket
   │
   ▼
WebSocket 发送到服务器
```

#### 接收输入状态
```
服务器推送输入状态
   │
   ▼
WebSocket 接收数据
   │
   ▼
IMProtocolHandler 解析
   │
   ▼
IMTypingManager 处理
   │
   ├─ 更新状态
   ├─ 启动超时定时器（10秒）
   │
   ▼
通知 Delegate
   │
   ▼
UI 显示 "对方正在输入..."
```

---

## 实现细节

### 1. 协议定义

```protobuf
// im_protocol.proto

enum PacketType {
    // ... 其他类型
    TYPING = 300;      // 输入状态
}

message TypingPacket {
    string conversation_id = 1;  // 会话 ID
    int32 status = 2;            // 状态：0=停止，1=正在输入
    int64 timestamp = 3;         // 时间戳
}
```

### 2. 输入状态管理器

```swift
// IMTypingManager.swift

import Foundation

/// 输入状态
public enum IMTypingStatus: Int {
    case stop = 0       // 停止输入
    case typing = 1     // 正在输入
}

/// 输入状态
public struct IMTypingState {
    public let conversationID: String
    public let userID: String
    public let status: IMTypingStatus
    public let timestamp: Int64
}

/// 输入状态监听器
public protocol IMTypingListener: AnyObject {
    /// 输入状态改变
    func onTypingStateChanged(_ state: IMTypingState)
}

/// 输入状态管理器
public class IMTypingManager {
    
    // MARK: - Properties
    
    /// 当前用户 ID
    private let userID: String
    
    /// 协议处理器
    private weak var protocolHandler: IMProtocolHandler?
    
    /// 监听器
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    /// 发送记录（conversationID -> 最后发送时间）
    private var sendingRecords: [String: TimeInterval] = [:]
    private let sendingLock = NSLock()
    
    /// 自动停止定时器（conversationID -> Timer）
    private var stopTimers: [String: Timer] = [:]
    
    /// 接收状态（conversationID -> userID -> 超时时间）
    private var receivingStates: [String: [String: TimeInterval]] = [:]
    private let receivingLock = NSLock()
    
    /// 超时检查定时器
    private var timeoutTimer: Timer?
    
    // MARK: - Configuration
    
    /// 发送间隔（秒）- 防抖动
    public var sendInterval: TimeInterval = 5.0
    
    /// 自动停止延迟（秒）
    public var stopDelay: TimeInterval = 3.0
    
    /// 接收超时（秒）
    public var receiveTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    public init(userID: String, protocolHandler: IMProtocolHandler) {
        self.userID = userID
        self.protocolHandler = protocolHandler
        startTimeoutTimer()
    }
    
    deinit {
        stopAllTimers()
    }
    
    // MARK: - Public Methods
    
    /// 发送"正在输入"状态
    /// - Parameter conversationID: 会话 ID
    public func sendTyping(conversationID: String) {
        sendingLock.lock()
        defer { sendingLock.unlock() }
        
        let now = Date().timeIntervalSince1970
        
        // 检查防抖动
        if let lastSendTime = sendingRecords[conversationID],
           now - lastSendTime < sendInterval {
            IMLogger.shared.verbose("Typing event ignored due to debounce")
            return
        }
        
        // 更新记录
        sendingRecords[conversationID] = now
        
        // 发送状态
        sendTypingStatus(.typing, conversationID: conversationID)
        
        // 启动自动停止定时器
        startStopTimer(for: conversationID)
    }
    
    /// 发送"停止输入"状态
    /// - Parameter conversationID: 会话 ID
    public func stopTyping(conversationID: String) {
        sendingLock.lock()
        defer { sendingLock.unlock() }
        
        // 取消自动停止定时器
        cancelStopTimer(for: conversationID)
        
        // 发送停止状态
        sendTypingStatus(.stop, conversationID: conversationID)
        
        // 清除记录
        sendingRecords.removeValue(forKey: conversationID)
    }
    
    /// 获取会话中正在输入的用户列表
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 正在输入的用户 ID 列表
    public func getTypingUsers(in conversationID: String) -> [String] {
        receivingLock.lock()
        defer { receivingLock.unlock() }
        
        let now = Date().timeIntervalSince1970
        
        guard let users = receivingStates[conversationID] else {
            return []
        }
        
        // 过滤未超时的用户
        return users.filter { $0.value > now }.map { $0.key }
    }
    
    // MARK: - Listener Management
    
    /// 添加监听器
    public func addListener(_ listener: IMTypingListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除监听器
    public func removeListener(_ listener: IMTypingListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    // MARK: - Internal Methods
    
    /// 处理接收到的输入状态
    internal func handleTypingPacket(conversationID: String, userID: String, status: IMTypingStatus) {
        // 忽略自己的状态
        guard userID != self.userID else {
            return
        }
        
        receivingLock.lock()
        
        let now = Date().timeIntervalSince1970
        
        if status == .typing {
            // 正在输入：记录超时时间
            if receivingStates[conversationID] == nil {
                receivingStates[conversationID] = [:]
            }
            receivingStates[conversationID]?[userID] = now + receiveTimeout
            
        } else {
            // 停止输入：移除记录
            receivingStates[conversationID]?.removeValue(forKey: userID)
            if receivingStates[conversationID]?.isEmpty == true {
                receivingStates.removeValue(forKey: conversationID)
            }
        }
        
        receivingLock.unlock()
        
        // 通知监听器
        let state = IMTypingState(
            conversationID: conversationID,
            userID: userID,
            status: status,
            timestamp: Int64(now * 1000)
        )
        
        notifyListeners(state)
        
        IMLogger.shared.verbose("Typing state: \(userID) in \(conversationID) - \(status)")
    }
    
    // MARK: - Private Methods
    
    /// 发送输入状态
    private func sendTypingStatus(_ status: IMTypingStatus, conversationID: String) {
        guard let protocolHandler = protocolHandler else {
            return
        }
        
        // 构造协议包
        let packet: [String: Any] = [
            "type": 300,  // TYPING
            "conversation_id": conversationID,
            "status": status.rawValue,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        
        // 发送
        if let data = try? JSONSerialization.data(withJSONObject: packet) {
            protocolHandler.sendData(data)
        }
        
        IMLogger.shared.verbose("Sent typing status: \(status) for \(conversationID)")
    }
    
    /// 启动自动停止定时器
    private func startStopTimer(for conversationID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 取消现有定时器
            self.stopTimers[conversationID]?.invalidate()
            
            // 创建新定时器
            let timer = Timer.scheduledTimer(withTimeInterval: self.stopDelay, repeats: false) { [weak self] _ in
                self?.stopTyping(conversationID: conversationID)
            }
            
            self.stopTimers[conversationID] = timer
        }
    }
    
    /// 取消自动停止定时器
    private func cancelStopTimer(for conversationID: String) {
        DispatchQueue.main.async { [weak self] in
            self?.stopTimers[conversationID]?.invalidate()
            self?.stopTimers.removeValue(forKey: conversationID)
        }
    }
    
    /// 启动超时检查定时器
    private func startTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkTimeout()
            }
        }
    }
    
    /// 检查超时
    private func checkTimeout() {
        receivingLock.lock()
        
        let now = Date().timeIntervalSince1970
        var expiredStates: [(String, String)] = []  // (conversationID, userID)
        
        for (conversationID, users) in receivingStates {
            for (userID, expireTime) in users where expireTime <= now {
                expiredStates.append((conversationID, userID))
            }
        }
        
        // 移除超时的状态
        for (conversationID, userID) in expiredStates {
            receivingStates[conversationID]?.removeValue(forKey: userID)
            if receivingStates[conversationID]?.isEmpty == true {
                receivingStates.removeValue(forKey: conversationID)
            }
        }
        
        receivingLock.unlock()
        
        // 通知超时
        for (conversationID, userID) in expiredStates {
            let state = IMTypingState(
                conversationID: conversationID,
                userID: userID,
                status: .stop,
                timestamp: Int64(now * 1000)
            )
            notifyListeners(state)
            
            IMLogger.shared.verbose("Typing timeout: \(userID) in \(conversationID)")
        }
    }
    
    /// 停止所有定时器
    private func stopAllTimers() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for timer in self.stopTimers.values {
                timer.invalidate()
            }
            self.stopTimers.removeAll()
            
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
        }
    }
    
    /// 通知监听器
    private func notifyListeners(_ state: IMTypingState) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMTypingListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            for listener in allListeners {
                listener.onTypingStateChanged(state)
            }
        }
    }
}
```

---

## 使用示例

### Example 1: 基础集成

```swift
class ChatViewController: UIViewController, IMTypingListener {
    
    let conversationID = "conv_123"
    var typingIndicatorLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 添加输入状态监听
        IMClient.shared.typingManager?.addListener(self)
    }
    
    // MARK: - UITextViewDelegate
    
    func textViewDidChange(_ textView: UITextView) {
        // 发送"正在输入"状态
        IMClient.shared.typingManager?.sendTyping(conversationID: conversationID)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // 发送"停止输入"状态
        IMClient.shared.typingManager?.stopTyping(conversationID: conversationID)
    }
    
    // MARK: - IMTypingListener
    
    func onTypingStateChanged(_ state: IMTypingState) {
        // 只处理当前会话
        guard state.conversationID == conversationID else {
            return
        }
        
        // 获取正在输入的用户列表
        let typingUsers = IMClient.shared.typingManager?.getTypingUsers(in: conversationID) ?? []
        
        if typingUsers.isEmpty {
            // 隐藏提示
            typingIndicatorLabel.isHidden = true
        } else if typingUsers.count == 1 {
            // 一个人正在输入
            typingIndicatorLabel.text = "对方正在输入..."
            typingIndicatorLabel.isHidden = false
        } else {
            // 多人正在输入
            typingIndicatorLabel.text = "\(typingUsers.count) 人正在输入..."
            typingIndicatorLabel.isHidden = false
        }
    }
}
```

### Example 2: 高级自定义

```swift
class ChatViewController: UIViewController {
    
    var inputTextView: UITextView!
    var typingIndicatorView: TypingIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 自定义参数
        let typingManager = IMClient.shared.typingManager
        typingManager?.sendInterval = 3.0       // 3秒防抖动
        typingManager?.stopDelay = 5.0          // 5秒自动停止
        typingManager?.receiveTimeout = 15.0    // 15秒超时
        
        typingManager?.addListener(self)
    }
}
```

### Example 3: 群聊场景

```swift
class GroupChatViewController: UIViewController, IMTypingListener {
    
    let conversationID = "group_456"
    
    func onTypingStateChanged(_ state: IMTypingState) {
        guard state.conversationID == conversationID else {
            return
        }
        
        let typingUsers = IMClient.shared.typingManager?.getTypingUsers(in: conversationID) ?? []
        
        if typingUsers.isEmpty {
            hideTypingIndicator()
        } else {
            // 获取用户名
            let userNames = typingUsers.compactMap { userID in
                IMClient.shared.userManager.getUser(userID: userID)?.nickname
            }
            
            let text: String
            if userNames.count == 1 {
                text = "\(userNames[0]) 正在输入..."
            } else if userNames.count == 2 {
                text = "\(userNames[0]) 和 \(userNames[1]) 正在输入..."
            } else {
                text = "\(userNames[0]) 等 \(userNames.count) 人正在输入..."
            }
            
            showTypingIndicator(text: text)
        }
    }
}
```

### Example 4: 动画效果

```swift
class TypingIndicatorView: UIView {
    
    private let dotsView = UIView()
    private var animationTimer: Timer?
    
    func startAnimation() {
        // 显示跳动的点点点动画
        var dotCount = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            dotCount = (dotCount + 1) % 4
            let dots = String(repeating: ".", count: dotCount)
            self?.label.text = "对方正在输入\(dots)"
        }
    }
    
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
```

---

## 性能优化

### 1. 防抖动（避免频繁发送）

```swift
// 5秒内不重复发送
if let lastSendTime = sendingRecords[conversationID],
   now - lastSendTime < sendInterval {
    return  // 忽略
}
```

### 2. 自动停止（减少服务器负担）

```swift
// 3秒未输入自动发送停止状态
startStopTimer(for: conversationID)
```

### 3. 超时机制（避免状态残留）

```swift
// 10秒超时自动隐藏
if expireTime <= now {
    // 移除状态
}
```

---

## 测试场景

### 1. 单聊场景
```
Given: A 和 B 在单聊
When: A 开始输入
Then: B 看到 "对方正在输入..."
```

### 2. 群聊场景
```
Given: A、B、C 在群聊
When: A 和 B 同时输入
Then: C 看到 "2 人正在输入..."
```

### 3. 防抖动
```
Given: A 快速输入多个字符
When: 在 5 秒内
Then: 只发送一次状态
```

### 4. 自动停止
```
Given: A 输入后停止
When: 3 秒后
Then: 自动发送停止状态
```

### 5. 超时
```
Given: B 收到 A 的输入状态
When: 10 秒后仍未收到停止或新的输入状态
Then: 自动隐藏提示
```

---

## 总结

### 核心要点

1. ✅ **防抖动**：5秒内不重复发送
2. ✅ **自动停止**：3秒未输入自动停止
3. ✅ **超时机制**：10秒超时自动隐藏
4. ✅ **群聊支持**：显示多人输入状态
5. ✅ **性能优化**：最小化网络请求

### 预期效果

| 功能 | 效果 |
|------|------|
| 实时性 | ✅ 毫秒级响应 |
| 流量消耗 | ✅ 极小（< 100字节/次） |
| 用户体验 | ⭐️⭐️⭐️⭐️⭐️ 互动感强 |

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


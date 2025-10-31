# IMSDK API 文档

## 目录

- [初始化](#初始化)
- [登录登出](#登录登出)
- [消息管理](#消息管理)
- [会话管理](#会话管理)
- [用户管理](#用户管理)
- [群组管理](#群组管理)
- [好友管理](#好友管理)
- [监听器](#监听器)

---

## 初始化

### initialize(config:)

初始化 SDK。

```swift
let config = IMConfig(
    apiURL: "https://your-api-server.com",
    wsURL: "wss://your-websocket-server.com"
)

try IMClient.shared.initialize(config: config)
```

**参数：**
- `config`: SDK 配置

**抛出：**
- `IMError`: 初始化失败时抛出错误

---

## 登录登出

### login(userID:token:completion:)

用户登录。

```swift
IMClient.shared.login(
    userID: "user123",
    token: "your-auth-token"
) { result in
    switch result {
    case .success(let user):
        print("登录成功: \(user.nickname)")
    case .failure(let error):
        print("登录失败: \(error)")
    }
}
```

**参数：**
- `userID`: 用户 ID
- `token`: 认证 Token
- `completion`: 完成回调

### logout(completion:)

用户登出。

```swift
IMClient.shared.logout { result in
    switch result {
    case .success:
        print("登出成功")
    case .failure(let error):
        print("登出失败: \(error)")
    }
}
```

---

## 消息管理

### createTextMessage(content:to:conversationType:)

创建文本消息。

```swift
let message = IMClient.shared.messageManager.createTextMessage(
    content: "Hello, World!",
    to: "receiver_user_id",
    conversationType: .single
)
```

**参数：**
- `content`: 消息内容
- `to`: 接收者 ID（单聊为用户 ID，群聊为群组 ID）
- `conversationType`: 会话类型（单聊、群聊等）

**返回：**
- `IMMessage`: 创建的消息对象

### sendMessage(_:)

发送消息（同步方法）。

**⚠️ 重要：** 返回值表示消息已成功**提交到发送队列**，而非已送达服务器。实际发送状态通过 `IMMessageListener` 监听。

```swift
// 发送消息
do {
    let message = try IMClient.shared.messageManager.sendMessage(message)
    // ✅ 消息已提交到发送队列（不是已送达！）
    print("消息已提交: \(message.messageID)")
    // UI: 显示消息，状态为 sending ⏱️
} catch {
    // ❌ 本地错误（数据库保存失败等）
    print("提交失败: \(error)")
}

// 监听实际发送状态
extension MyViewController: IMMessageListener {
    func onMessageStatusChanged(_ message: IMMessage) {
        switch message.status {
        case .sending:
            // 发送中 ⏱️
            updateUI(message, icon: "⏱️")
        case .sent:
            // 已发送到服务器 ✓
            updateUI(message, icon: "✓")
        case .delivered:
            // 对方已收到 ✓✓
            updateUI(message, icon: "✓✓")
        case .read:
            // 对方已读 ✓✓（蓝色）
            updateUI(message, icon: "✓✓", color: .blue)
        case .failed:
            // 发送失败 ❌
            updateUI(message, icon: "❌")
            showRetryButton()
        }
    }
}
```

**参数：**
- `message`: 要发送的消息

**返回值：**
- `IMMessage`: 已提交到队列的消息

**抛出异常：**
- 如果保存到数据库失败，抛出异常

**状态流转：**
```
sending (发送中) → sent (已发送) → delivered (已送达) → read (已读)
                         ↓
                    failed (失败)
```

### getMessages(conversationID:limit:offset:)

获取会话消息列表。

```swift
let messages = IMClient.shared.messageManager.getMessages(
    conversationID: "conversation_id",
    limit: 20,
    offset: 0
)
```

**参数：**
- `conversationID`: 会话 ID
- `limit`: 获取数量（默认 20）
- `offset`: 偏移量（默认 0）

**返回：**
- `[IMMessage]`: 消息数组

### markMessagesAsRead(conversationID:messageIDs:completion:)

标记消息为已读。

```swift
IMClient.shared.messageManager.markMessagesAsRead(
    conversationID: "conversation_id",
    messageIDs: ["msg1", "msg2"]
) { result in
    // 处理结果
}
```

---

## 会话管理

### getAllConversations()

获取所有会话。

```swift
let conversations = IMClient.shared.conversationManager.getAllConversations()
```

**返回：**
- `[IMConversation]`: 会话数组

### getConversation(conversationID:)

获取指定会话。

```swift
if let conversation = IMClient.shared.conversationManager.getConversation(
    conversationID: "conversation_id"
) {
    print("会话名称: \(conversation.showName)")
}
```

### clearUnreadCount(conversationID:completion:)

清除会话未读数。

```swift
IMClient.shared.conversationManager.clearUnreadCount(
    conversationID: "conversation_id"
) { result in
    // 处理结果
}
```

### getTotalUnreadCount()

获取总未读数。

```swift
let totalUnreadCount = IMClient.shared.conversationManager.getTotalUnreadCount()
print("总未读数: \(totalUnreadCount)")
```

---

## 用户管理

### getUserInfo(userID:forceUpdate:completion:)

获取用户信息。

```swift
IMClient.shared.userManager.getUserInfo(
    userID: "user_id",
    forceUpdate: false
) { result in
    switch result {
    case .success(let user):
        print("昵称: \(user.nickname)")
    case .failure(let error):
        print("获取失败: \(error)")
    }
}
```

**参数：**
- `userID`: 用户 ID
- `forceUpdate`: 是否强制从服务器更新（默认 false）
- `completion`: 完成回调

### updateUserInfo(_:completion:)

更新用户信息。

```swift
let user = IMClient.shared.userManager.getCurrentUser()!
user.nickname = "新昵称"
user.signature = "新签名"

IMClient.shared.userManager.updateUserInfo(user) { result in
    // 处理结果
}
```

---

## 群组管理

### createGroup(groupName:faceURL:introduction:memberUserIDs:completion:)

创建群组。

```swift
IMClient.shared.groupManager.createGroup(
    groupName: "我的群组",
    faceURL: "https://example.com/avatar.jpg",
    introduction: "群组简介",
    memberUserIDs: ["user1", "user2"]
) { result in
    switch result {
    case .success(let group):
        print("群组创建成功: \(group.groupID)")
    case .failure(let error):
        print("创建失败: \(error)")
    }
}
```

### inviteMembers(groupID:userIDs:completion:)

邀请成员加入群组。

```swift
IMClient.shared.groupManager.inviteMembers(
    groupID: "group_id",
    userIDs: ["user3", "user4"]
) { result in
    // 处理结果
}
```

### leaveGroup(groupID:completion:)

退出群组。

```swift
IMClient.shared.groupManager.leaveGroup(groupID: "group_id") { result in
    // 处理结果
}
```

---

## 好友管理

### addFriend(userID:message:completion:)

添加好友。

```swift
IMClient.shared.friendManager.addFriend(
    userID: "user_id",
    message: "你好，我想加你为好友"
) { result in
    // 处理结果
}
```

### getFriendList(completion:)

获取好友列表。

```swift
IMClient.shared.friendManager.getFriendList { result in
    switch result {
    case .success(let friends):
        print("好友数量: \(friends.count)")
    case .failure(let error):
        print("获取失败: \(error)")
    }
}
```

### deleteFriend(userID:completion:)

删除好友。

```swift
IMClient.shared.friendManager.deleteFriend(userID: "user_id") { result in
    // 处理结果
}
```

---

## 监听器

### IMConnectionListener

连接状态监听器。

```swift
class MyClass: IMConnectionListener {
    func onConnected() {
        print("已连接")
    }
    
    func onDisconnected(error: Error?) {
        print("已断开")
    }
    
    func onConnectionStateChanged(_ state: IMConnectionState) {
        print("状态改变: \(state)")
    }
}

// 添加监听器
IMClient.shared.addConnectionListener(self)

// 移除监听器
IMClient.shared.removeConnectionListener(self)
```

### IMMessageListener

消息监听器。

```swift
extension MyClass: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        print("收到新消息: \(message.content)")
    }
    
    func onMessageStatusChanged(_ message: IMMessage) {
        print("消息状态改变: \(message.status)")
    }
}

IMClient.shared.addMessageListener(self)
```

### IMConversationListener

会话监听器。

```swift
extension MyClass: IMConversationListener {
    func onConversationUpdated(_ conversation: IMConversation) {
        print("会话更新: \(conversation.showName)")
    }
    
    func onUnreadCountChanged(_ conversationID: String, count: Int) {
        print("未读数: \(count)")
    }
}

IMClient.shared.addConversationListener(self)
```

---

## 错误处理

所有错误都使用 `IMError` 枚举：

```swift
public enum IMError: Error {
    case notInitialized           // SDK 未初始化
    case notLoggedIn             // 用户未登录
    case networkError(String)    // 网络错误
    case databaseError(String)   // 数据库错误
    case invalidParameter(String)// 参数错误
    case authenticationFailed(String) // 认证失败
    case timeout                 // 超时
    case cancelled               // 已取消
    case unknown(String)         // 未知错误
}
```

---

## 最佳实践

### 1. 初始化时机

在 App 启动时初始化 SDK：

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let config = IMConfig(
        apiURL: "https://api.example.com",
        wsURL: "wss://ws.example.com"
    )
    try? IMClient.shared.initialize(config: config)
    return true
}
```

### 2. 登录时机

用户认证成功后立即登录 IM：

```swift
func afterUserAuthentication(userID: String, token: String) {
    IMClient.shared.login(userID: userID, token: token) { result in
        // 处理登录结果
    }
}
```

### 3. 监听器管理

在适当的生命周期添加和移除监听器：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    IMClient.shared.addMessageListener(self)
}

deinit {
    IMClient.shared.removeMessageListener(self)
}
```

### 4. 错误处理

始终处理可能的错误：

```swift
IMClient.shared.messageManager.sendMessage(message) { result in
    switch result {
    case .success(let message):
        // 更新 UI
        break
    case .failure(let error):
        // 显示错误提示
        showAlert(message: error.localizedDescription)
    }
}
```


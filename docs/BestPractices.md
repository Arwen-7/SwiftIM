# IMSDK 最佳实践

本文档提供使用 IMSDK 的最佳实践和常见问题解决方案。

## 目录

1. [初始化和配置](#初始化和配置)
2. [登录和认证](#登录和认证)
3. [消息处理](#消息处理)
4. [性能优化](#性能优化)
5. [错误处理](#错误处理)
6. [内存管理](#内存管理)
7. [安全实践](#安全实践)
8. [常见问题](#常见问题)

---

## 初始化和配置

### 1. 应用启动时初始化

在 AppDelegate 的 `didFinishLaunchingWithOptions` 中初始化 SDK：

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
    // 配置日志
    let logConfig = IMLoggerConfig(
        minimumLevel: .info,  // 生产环境使用 .info，开发环境使用 .debug
        enableConsole: true,
        enableFileOutput: true
    )
    
    // 配置 SDK
    let config = IMConfig(
        apiURL: "https://api.example.com",
        wsURL: "wss://ws.example.com",
        logConfig: logConfig,
        timeout: 30
    )
    
    do {
        try IMClient.shared.initialize(config: config)
    } catch {
        print("SDK initialization failed: \(error)")
    }
    
    return true
}
```

### 2. 环境切换

开发、测试、生产环境使用不同的配置：

```swift
enum Environment {
    case development
    case staging
    case production
    
    var apiURL: String {
        switch self {
        case .development: return "https://dev-api.example.com"
        case .staging: return "https://staging-api.example.com"
        case .production: return "https://api.example.com"
        }
    }
    
    var wsURL: String {
        switch self {
        case .development: return "wss://dev-ws.example.com"
        case .staging: return "wss://staging-ws.example.com"
        case .production: return "wss://ws.example.com"
        }
    }
}

let env = Environment.production
let config = IMConfig(apiURL: env.apiURL, wsURL: env.wsURL)
```

---

## 登录和认证

### 1. 自动登录

保存登录状态，应用启动时自动登录：

```swift
class AuthManager {
    static let shared = AuthManager()
    
    private let userIDKey = "com.app.userID"
    private let tokenKey = "com.app.token"
    
    func saveLoginInfo(userID: String, token: String) {
        UserDefaults.standard.set(userID, forKey: userIDKey)
        KeychainHelper.save(token, forKey: tokenKey) // 使用 Keychain 存储 Token
    }
    
    func autoLogin(completion: @escaping (Bool) -> Void) {
        guard let userID = UserDefaults.standard.string(forKey: userIDKey),
              let token = KeychainHelper.load(forKey: tokenKey) else {
            completion(false)
            return
        }
        
        IMClient.shared.login(userID: userID, token: token) { result in
            completion(result.isSuccess)
        }
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
        KeychainHelper.delete(forKey: tokenKey)
        IMClient.shared.logout()
    }
}
```

### 2. Token 刷新

Token 过期前主动刷新：

```swift
extension YourClass: IMConnectionListener {
    func onTokenWillExpire() {
        // Token 即将过期，刷新 Token
        refreshToken { newToken in
            // 重新登录
            if let userID = IMClient.shared.getCurrentUserID() {
                IMClient.shared.login(userID: userID, token: newToken) { _ in }
            }
        }
    }
}
```

---

## 消息处理

### 1. 消息发送重试

发送失败时重试：

```swift
func sendMessageWithRetry(_ message: IMMessage, retryCount: Int = 3) {
    IMClient.shared.messageManager.sendMessage(message) { result in
        switch result {
        case .success:
            print("Message sent successfully")
            
        case .failure(let error):
            if retryCount > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                    self.sendMessageWithRetry(message, retryCount: retryCount - 1)
                }
            } else {
                print("Failed to send message after retries: \(error)")
            }
        }
    }
}
```

### 2. 消息去重

防止重复消息：

```swift
class MessageDeduplicator {
    private var receivedMessageIDs = Set<String>()
    private let lock = NSLock()
    
    func isDuplicate(messageID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if receivedMessageIDs.contains(messageID) {
            return true
        }
        
        receivedMessageIDs.insert(messageID)
        
        // 限制集合大小，防止内存泄漏
        if receivedMessageIDs.count > 10000 {
            receivedMessageIDs.removeFirst()
        }
        
        return false
    }
}

extension YourClass: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        if !messageDeduplicator.isDuplicate(messageID: message.messageID) {
            // 处理新消息
            handleNewMessage(message)
        }
    }
}
```

### 3. 批量标记已读

用户进入会话时批量标记已读：

```swift
func enterConversation(conversationID: String) {
    let messages = IMClient.shared.messageManager.getMessages(
        conversationID: conversationID,
        limit: 100
    )
    
    let unreadMessageIDs = messages
        .filter { !$0.isRead && $0.direction == .receive }
        .map { $0.messageID }
    
    if !unreadMessageIDs.isEmpty {
        IMClient.shared.messageManager.markMessagesAsRead(
            conversationID: conversationID,
            messageIDs: unreadMessageIDs
        ) { _ in }
    }
    
    // 清除会话未读数
    IMClient.shared.conversationManager.clearUnreadCount(
        conversationID: conversationID
    ) { _ in }
}
```

---

## 性能优化

### 1. 分页加载消息

避免一次性加载大量消息：

```swift
class MessageListViewController: UIViewController {
    private var messages: [IMMessage] = []
    private let pageSize = 20
    private var isLoading = false
    
    func loadMoreMessages() {
        guard !isLoading else { return }
        isLoading = true
        
        let oldestTimestamp = messages.first?.sendTime ?? Int64.max
        
        let newMessages = IMClient.shared.messageManager.getMessagesBefore(
            conversationID: conversationID,
            timestamp: oldestTimestamp,
            limit: pageSize
        )
        
        messages.insert(contentsOf: newMessages, at: 0)
        tableView.reloadData()
        
        isLoading = false
    }
}
```

### 2. 图片压缩和缓存

发送图片前压缩：

```swift
func sendImage(_ image: UIImage) {
    // 压缩图片
    guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
    
    // 上传图片
    uploadImage(imageData) { imageURL in
        // 创建并发送消息
        let message = IMClient.shared.messageManager.createImageMessage(
            imageURL: imageURL,
            to: receiverID,
            conversationType: .single
        )
        IMClient.shared.messageManager.sendMessage(message) { _ in }
    }
}
```

### 3. 用户信息批量获取

批量获取用户信息而不是逐个获取：

```swift
func loadUserInfo(for messages: [IMMessage]) {
    let userIDs = Set(messages.map { $0.senderID })
    
    IMClient.shared.userManager.getUsersInfo(userIDs: Array(userIDs)) { result in
        if case .success(let users) = result {
            // 更新 UI
            self.updateUI(with: users)
        }
    }
}
```

---

## 错误处理

### 1. 统一错误处理

```swift
func handleIMError(_ error: IMError) {
    switch error {
    case .notInitialized:
        showAlert(message: "SDK 未初始化")
        
    case .notLoggedIn:
        // 跳转到登录页面
        navigateToLogin()
        
    case .networkError(let message):
        showAlert(message: "网络错误: \(message)")
        
    case .authenticationFailed:
        // Token 失效，重新登录
        logout()
        navigateToLogin()
        
    case .timeout:
        showAlert(message: "请求超时，请检查网络")
        
    default:
        showAlert(message: error.localizedDescription)
    }
}
```

### 2. 网络状态监听

监听网络状态变化：

```swift
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    var isConnected: Bool = true
    var onStatusChanged: ((Bool) -> Void)?
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            
            if self?.isConnected != connected {
                self?.isConnected = connected
                DispatchQueue.main.async {
                    self?.onStatusChanged?(connected)
                }
            }
        }
        
        monitor.start(queue: queue)
    }
}

// 使用
NetworkMonitor.shared.onStatusChanged = { connected in
    if connected {
        // 网络恢复，重连
        if !IMClient.shared.isConnected {
            // 自动重连逻辑
        }
    } else {
        // 网络断开，显示提示
        showNetworkAlert()
    }
}
```

---

## 内存管理

### 1. 正确移除监听器

在 deinit 中移除监听器：

```swift
class ChatViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        IMClient.shared.addMessageListener(self)
        IMClient.shared.addConversationListener(self)
    }
    
    deinit {
        IMClient.shared.removeMessageListener(self)
        IMClient.shared.removeConversationListener(self)
    }
}
```

### 2. 避免循环引用

使用 weak self：

```swift
IMClient.shared.messageManager.sendMessage(message) { [weak self] result in
    guard let self = self else { return }
    
    switch result {
    case .success:
        self.handleSuccess()
    case .failure(let error):
        self.handleError(error)
    }
}
```

### 3. 及时清理缓存

定期清理缓存：

```swift
func clearCacheIfNeeded() {
    let diskCache = IMDiskCache()
    
    diskCache.getCacheSize { size in
        // 如果缓存超过 100MB，清理
        if size > 100 * 1024 * 1024 {
            diskCache.removeAll { _ in
                print("Cache cleared")
            }
        }
    }
}
```

---

## 安全实践

### 1. 使用 Keychain 存储敏感信息

```swift
class KeychainHelper {
    static func save(_ value: String, forKey key: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

### 2. 避免日志泄露敏感信息

```swift
// ❌ 错误：记录敏感信息
IMLogger.shared.info("User token: \(token)")

// ✅ 正确：只记录必要信息
IMLogger.shared.info("User logged in: \(userID)")
```

---

## 常见问题

### Q1: 消息发送失败怎么办？

**A:** 检查以下几点：
1. 是否已登录（`IMClient.shared.isLoggedIn`）
2. 是否已连接（`IMClient.shared.isConnected`）
3. 网络是否正常
4. 检查错误日志

### Q2: 如何处理离线消息？

**A:** SDK 会在连接成功后自动同步离线消息，你只需要监听 `onMessageReceived` 回调即可。

### Q3: 如何优化消息列表滚动性能？

**A:** 
1. 使用 UITableView/UICollectionView 的复用机制
2. 异步加载图片
3. 分页加载历史消息
4. 缓存 Cell 高度

### Q4: 消息重复怎么办？

**A:** 使用消息去重机制（参考上文"消息去重"部分）。

### Q5: 如何实现@功能？

**A:** 在消息 content 中使用特殊格式，如 `@{userID:nickname}`，发送时解析并通知被@用户。

---

## 总结

遵循以上最佳实践可以帮助你更好地使用 IMSDK，构建稳定、高效的 IM 应用。如有其他问题，请参考 [API 文档](API.md) 或提交 Issue。


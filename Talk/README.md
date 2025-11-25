# Talk - SwiftIM SDK 示例应用

这是一个完整的 iOS 即时通讯应用示例，演示了如何使用 SwiftIM SDK 构建聊天应用。

## 功能特性

- ✅ 用户登录/登出
- ✅ 对话列表展示
- ✅ 实时消息收发
- ✅ 未读消息提示
- ✅ 消息时间智能显示
- ✅ 自动重连机制
- ✅ 离线消息同步

## 项目结构

```
Talk/
├── Models/
│   └── TalkConfig.swift          # 应用配置
├── Extensions/
│   ├── UIColor+Extensions.swift  # 颜色扩展
│   └── Date+Extensions.swift     # 日期扩展
├── Views/
│   ├── ConversationCell.swift    # 对话列表 Cell
│   └── MessageCell.swift         # 消息 Cell
├── ViewControllers/
│   ├── ConversationListViewController.swift  # 对话列表页
│   ├── ChatViewController.swift              # 聊天页
│   └── SettingsViewController.swift          # 设置页
├── AppDelegate.swift
└── SceneDelegate.swift
```

## 配置步骤

### 1. 添加 SwiftIM SDK 依赖

在 Xcode 中打开 Talk.xcodeproj，然后：

1. 选择项目 -> Talk target
2. 选择 "General" 标签页
3. 滚动到 "Frameworks, Libraries, and Embedded Content" 部分
4. 点击 "+" 按钮
5. 选择 "Add Other..." -> "Add Package Dependency..."
6. 点击 "Add Local..." 按钮
7. 导航到 `IM-iOS-SDK` 目录（Talk 的父目录）
8. 选择整个 `IM-iOS-SDK` 文件夹
9. 在弹出的对话框中，确保选中 "SwiftIM" 产品
10. 点击 "Add Package"

**或者使用更简单的方法：**

1. 在 Xcode 中，选择 File -> Add Package Dependencies...
2. 点击 "Add Local..." 按钮
3. 选择 `IM-iOS-SDK` 目录（包含 Package.swift 的目录）
4. 点击 "Add Package"
5. 在产品列表中勾选 "SwiftIM"
6. 点击 "Add Package"

### 2. 配置服务器地址

编辑 `Talk/Models/TalkConfig.swift`，修改服务器地址：

```swift
struct TalkConfig {
    /// IM 服务器地址
    /// 使用 TCP 协议（推荐，性能更好）：tcp://your-server:8082
    /// 使用 WebSocket 协议（兼容）：ws://your-server:8081/ws
    static let imServerURL = "tcp://your-server:8082"
    
    /// API 服务器地址
    static let apiServerURL = "http://your-server:8080"
}
```

**注意**：
- 默认使用 TCP 协议，端口 8082，性能更好
- 如需使用 WebSocket，将 URL 改为 `ws://your-server:8081/ws`

### 3. 启动 IM 服务器

确保 IM 服务器已启动并运行在配置的地址上。

在 `IM-Server` 目录下运行：

```bash
cd ../IM-Server
go run cmd/server/main.go
```

### 4. 运行应用

1. 在 Xcode 中选择目标设备（模拟器或真机）
2. 点击运行按钮（Command + R）
3. 首次运行会自动打开设置页面
4. 输入用户 ID（任意字符串）
5. 点击"登录"按钮

## 使用说明

### 登录

1. 打开应用后，如果未登录会自动弹出设置页面
2. 输入用户 ID（例如：user1, user2, alice, bob 等）
3. Token 可以留空（演示模式下会自动生成）
4. 点击"登录"按钮

### 创建对话

1. 在对话列表页面，点击右上角的"撰写"按钮
2. 输入对方的用户 ID
3. 点击确定后会自动跳转到聊天页面

### 发送消息

1. 在聊天页面底部的输入框中输入文字
2. 点击"发送"按钮
3. 消息会立即显示在聊天界面中

### 接收消息

- 应用会自动接收实时消息
- 新消息会显示在对应的聊天界面
- 对话列表会显示未读消息数量

### 测试多用户聊天

可以使用以下方式测试：

1. **使用多个模拟器**：
   - 在一个模拟器上登录 user1
   - 在另一个模拟器上登录 user2
   - 相互发送消息

2. **使用模拟器 + 真机**：
   - 模拟器登录 user1
   - 真机登录 user2
   - 相互发送消息

3. **使用 Web 客户端**（如果有）：
   - 应用登录 user1
   - Web 登录 user2
   - 相互发送消息

## 核心代码说明

### SDK 初始化

在 `SceneDelegate.swift` 中初始化 SDK：

```swift
private func initializeSDK() {
    let config = IMConfig(
        apiURL: TalkConfig.apiServerURL,
        imURL: TalkConfig.imServerURL
    )
    
    try IMClient.shared.initialize(config: config)
}
```

### 用户登录

```swift
IMClient.shared.login(userID: userID, token: token) { result in
    switch result {
    case .success:
        print("登录成功，长连接已建立")
        // 获取当前用户信息
        if let user = IMClient.shared.currentUser {
            print("用户昵称: \(user.nickname)")
        }
    case .failure(let error):
        print("登录失败: \(error)")
    }
}
```

### 加载对话列表

```swift
IMClient.shared.conversationManager?.getAllConversations { result in
    switch result {
    case .success(let conversations):
        self.conversations = conversations
        self.tableView.reloadData()
    case .failure(let error):
        print("加载失败: \(error)")
    }
}
```

### 发送消息

```swift
IMClient.shared.messageManager?.sendTextMessage(
    conversationID: conversationID,
    text: text
) { result in
    switch result {
    case .success(let message):
        print("发送成功: \(message.messageID)")
    case .failure(let error):
        print("发送失败: \(error)")
    }
}
```

### 接收消息

实现 `IMMessageListener` 协议：

```swift
extension ChatViewController: IMMessageListener {
    func onRecvNewMessage(_ message: IMMessage) {
        DispatchQueue.main.async {
            self.messages.append(message)
            self.tableView.reloadData()
        }
    }
}
```

### 监听连接状态

实现 `IMConnectionListener` 协议：

```swift
extension SettingsViewController: IMConnectionListener {
    func onConnected() {
        print("已连接")
    }
    
    func onDisconnected(error: Error?) {
        print("已断开: \(error?.localizedDescription ?? "")")
    }
}
```

## 常见问题

### 1. SDK 找不到

如果编译时提示找不到 `SwiftIM` 模块：
- 确认已正确添加 Package 依赖
- 尝试 Product -> Clean Build Folder (Shift + Command + K)
- 重启 Xcode

### 2. 连接失败

如果无法连接到服务器：
- 检查服务器是否已启动
- 检查服务器地址配置是否正确
- 检查网络连接
- 查看 Xcode 控制台的日志输出

### 3. 消息发送失败

- 确认已成功登录
- 确认网络连接正常
- 查看服务器日志

### 4. 收不到消息

- 确认对方已发送消息
- 确认连接状态正常
- 检查消息监听器是否正确添加

## 技术栈

- Swift 5.9+
- iOS 13.0+
- SwiftIM SDK
- UIKit

## 下一步

你可以在此基础上扩展更多功能：

- [ ] 图片消息
- [ ] 语音消息
- [ ] 视频消息
- [ ] 文件传输
- [ ] 群聊功能
- [ ] 好友管理
- [ ] 用户资料编辑
- [ ] 消息撤回
- [ ] 已读回执
- [ ] 输入状态显示
- [ ] 表情包
- [ ] 消息搜索
- [ ] 聊天记录导出

## 许可证

MIT License

## 联系方式

如有问题，请提交 Issue 或 Pull Request。


# IMSDK - 企业级 iOS IM SDK

[![Swift Version](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2013%2B-blue.svg)](https://www.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

一个高性能、可扩展的企业级即时通讯 iOS SDK，支持千万级用户。

## ✨ 特性

- 🚀 **高性能**：支持千万级用户，优化的消息处理和存储
- 🔒 **安全可靠**：端到端加密，本地数据加密存储
- 💬 **完整消息类型**：文本、图片、语音、视频、文件、自定义消息
- 👥 **群组管理**：支持大群聊、群公告、群成员管理
- 📱 **离线消息**：自动同步离线消息，保证消息不丢失
- 🔄 **断线重连**：智能重连机制，网络异常自动恢复
- 💾 **本地存储**：高效的本地数据库，支持消息历史查询
- 🎯 **Protocol-Oriented**：面向协议设计，易于扩展和测试

## 📦 安装

### Swift Package Manager

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/IM-iOS-SDK.git", from: "1.0.0")
]
```

或在 Xcode 中：
1. File > Add Packages...
2. 输入仓库 URL
3. 选择版本并添加到项目

## 🏗️ 架构设计

### 分层架构

```
┌─────────────────────────────────────────────┐
│          接口层 (API Layer)                   │
│    IMClient - 主入口和委托                   │
└─────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────┐
│          业务层 (Business Layer)              │
│  消息、用户、会话、群组、好友管理              │
└─────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────┐
│          核心层 (Core Layer)                  │
│  网络、数据库、协议处理、同步                  │
└─────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────┐
│          基础层 (Foundation Layer)            │
│  日志、加密、缓存、工具类                      │
└─────────────────────────────────────────────┘
```

## 🚀 快速开始

### 初始化 SDK

```swift
import IMSDK

// 配置 SDK
let config = IMConfig(
    apiURL: "https://your-api-server.com",
    wsURL: "wss://your-websocket-server.com"
)

// 初始化
IMClient.shared.initialize(config: config)

// 设置监听器
IMClient.shared.addMessageListener(self)
IMClient.shared.addConnectionListener(self)
```

### 登录

```swift
IMClient.shared.login(
    userID: "user123",
    token: "your-auth-token"
) { result in
    switch result {
    case .success:
        print("登录成功")
    case .failure(let error):
        print("登录失败: \(error)")
    }
}
```

### 发送消息

```swift
// 创建文本消息
let message = TextMessage(content: "Hello, World!")

// 发送消息
IMClient.shared.messageManager.sendMessage(
    message: message,
    to: "receiverUserID",
    conversationType: .single
) { result in
    switch result {
    case .success(let sentMessage):
        print("消息发送成功: \(sentMessage.messageID)")
    case .failure(let error):
        print("发送失败: \(error)")
    }
}
```

### 接收消息

```swift
extension YourClass: IMMessageListener {
    func onMessageReceived(_ message: Message) {
        print("收到新消息: \(message.content)")
    }
    
    func onMessageStatusChanged(_ message: Message) {
        print("消息状态改变: \(message.status)")
    }
}
```

## 📚 文档

详细文档请查看 [Wiki](https://github.com/yourusername/IM-iOS-SDK/wiki)

- [接入指南](docs/integration.md)
- [API 文档](docs/api.md)
- [最佳实践](docs/best-practices.md)
- [常见问题](docs/faq.md)

## 🧪 测试

```bash
swift test
```

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📮 联系方式

- Email: support@example.com
- 官网: https://example.com


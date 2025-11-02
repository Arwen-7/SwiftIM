# Talk 快速入门指南

欢迎使用 Talk - SwiftIM SDK 示例应用！本文档将帮助你快速开始。

## 📋 前置条件

在开始之前，请确保你已安装：

- ✅ macOS 13.0+ (Ventura)
- ✅ Xcode 15.0+
- ✅ iOS 13.0+ SDK
- ✅ Swift 5.9+

## 🚀 快速开始（5 分钟上手）

### 步骤 1：配置 SDK 依赖

在终端中运行配置脚本：

```bash
cd /Users/arwen/Project/IM/IM-iOS-SDK/Talk
./configure_sdk.sh
```

按照脚本提示，在 Xcode 中添加 SwiftIM SDK 依赖。

**或者手动添加：**

1. 用 Xcode 打开 `Talk.xcodeproj`
2. 选择 File → Add Package Dependencies...
3. 点击 "Add Local..."
4. 选择 `IM-iOS-SDK` 目录（Talk 的父目录）
5. 确保勾选 "SwiftIM" 产品
6. 点击 "Add Package"

### 步骤 2：启动 IM 服务器

在新的终端窗口中：

```bash
cd /Users/arwen/Project/IM/IM-Server
go run cmd/server/main.go
```

你应该看到类似的输出：
```
✅ Server started on :8080
✅ WebSocket endpoint: ws://localhost:8080/ws
```

### 步骤 3：运行 Talk 应用

1. 在 Xcode 中选择目标设备（模拟器）
2. 点击运行按钮 (Command + R)
3. 首次运行会打开设置页面

### 步骤 4：登录

在设置页面：

1. 输入用户 ID（例如：`alice`）
2. Token 留空（演示模式）
3. 点击"登录"按钮

🎉 成功！你现在可以开始使用 Talk 了。

## 💬 开始聊天

### 创建对话

1. 在对话列表页面，点击右上角的"撰写"按钮（✏️）
2. 输入对方的用户 ID（例如：`bob`）
3. 点击"确定"

### 发送消息

1. 在聊天页面底部的输入框中输入消息
2. 点击"发送"按钮
3. 消息会立即显示

### 测试多用户聊天

**方式一：使用两个模拟器**

在终端中启动第二个模拟器：

```bash
# 查看可用的模拟器
xcrun simctl list devices | grep Booted

# 启动第二个模拟器
open -a Simulator --args -CurrentDeviceUDID <device-id>
```

然后：
1. 在第一个模拟器登录 `alice`
2. 在第二个模拟器登录 `bob`
3. Alice 创建与 Bob 的对话
4. 相互发送消息

**方式二：使用模拟器 + 真机**

1. 在模拟器上登录 `alice`
2. 在真机上登录 `bob`
3. 相互发送消息

## 📁 项目文件说明

### 已创建的文件

```
Talk/
├── Talk/
│   ├── Models/
│   │   └── TalkConfig.swift                    # 应用配置
│   ├── Extensions/
│   │   ├── UIColor+Extensions.swift            # 颜色扩展
│   │   └── Date+Extensions.swift               # 日期扩展
│   ├── Views/
│   │   ├── ConversationCell.swift              # 对话列表单元格
│   │   └── MessageCell.swift                   # 消息单元格
│   ├── ViewControllers/
│   │   ├── ConversationListViewController.swift # 对话列表页
│   │   ├── ChatViewController.swift            # 聊天页
│   │   └── SettingsViewController.swift        # 设置页
│   ├── AppDelegate.swift                       # 应用代理（已修改）
│   └── SceneDelegate.swift                     # 场景代理（已修改）
│
├── Talk.xcodeproj/                             # Xcode 项目
├── README.md                                   # 项目说明
├── INTEGRATION_GUIDE.md                        # SDK 集成指南
├── PROJECT_OVERVIEW.md                         # 项目概览
├── GETTING_STARTED.md                          # 本文件
└── configure_sdk.sh                            # 配置脚本
```

### 核心文件说明

| 文件 | 说明 | 关键功能 |
|-----|------|---------|
| `TalkConfig.swift` | 全局配置 | 服务器地址、常量定义 |
| `ConversationListViewController.swift` | 对话列表 | 显示对话、创建对话、监听更新 |
| `ChatViewController.swift` | 聊天页面 | 消息收发、历史加载、键盘处理 |
| `SettingsViewController.swift` | 设置页面 | 登录/登出、配置管理 |
| `ConversationCell.swift` | 自定义 Cell | 对话列表项显示 |
| `MessageCell.swift` | 自定义 Cell | 消息气泡显示 |
| `SceneDelegate.swift` | 场景代理 | SDK 初始化、根视图设置 |

## 🎯 功能演示

### 1. 发送第一条消息

```
Alice 登录 → 创建与 Bob 的对话 → 输入 "你好！" → 点击发送 → ✅ 消息发送成功
```

### 2. 接收消息

```
Bob 登录 → 自动显示对话列表 → 看到 Alice 的对话（红点） → 点击进入 → 看到 "你好！"
```

### 3. 实时对话

```
Alice 和 Bob 同时在线 → Alice 发送消息 → Bob 立即收到（无需刷新）
```

### 4. 离线消息

```
Bob 离线 → Alice 发送消息 → Bob 重新登录 → 自动同步离线消息
```

## 🔧 配置选项

### 修改服务器地址

编辑 `Talk/Models/TalkConfig.swift`：

```swift
struct TalkConfig {
    // 修改为你的服务器地址
    static let imServerURL = "ws://192.168.1.100:8080/ws"
    static let apiServerURL = "http://192.168.1.100:8080"
}
```

### 调整日志级别

编辑 `AppDelegate.swift`：

```swift
IMLogger.shared.configure(IMLoggerConfig(
    level: .verbose,  // 可选: .verbose, .debug, .info, .warning, .error
    enableConsole: true,
    enableFile: false
))
```

### 自定义 UI 颜色

编辑 `Extensions/UIColor+Extensions.swift`：

```swift
extension UIColor {
    static let talkPrimary = UIColor.systemBlue     // 主题色
    static let talkBubbleSent = UIColor.systemBlue  // 发送气泡
    // ... 更多颜色
}
```

## 📱 界面说明

### 对话列表页

```
┌─────────────────────────────────┐
│  消息                    ✏️  ⚙️  │
├─────────────────────────────────┤
│  👤 Bob                         │
│     你好！              12:30  1 │
├─────────────────────────────────┤
│  👤 Charlie                     │
│     在吗？              昨天     │
└─────────────────────────────────┘
```

- 点击对话进入聊天页
- 点击 ✏️ 创建新对话
- 点击 ⚙️ 打开设置
- 滑动删除对话

### 聊天页

```
┌─────────────────────────────────┐
│  ← Bob                          │
├─────────────────────────────────┤
│                                 │
│  👤 ┌─────────┐                │
│     │ 你好！  │    12:30        │
│     └─────────┘                │
│                                 │
│                    ┌─────────┐ │
│         12:31     │ 你好呀！ │ 👤│
│                    └─────────┘ │
├─────────────────────────────────┤
│  [  输入消息...        ]  发送  │
└─────────────────────────────────┘
```

- 左边是接收的消息（灰色气泡）
- 右边是发送的消息（蓝色气泡）
- 底部输入框自动适应键盘

### 设置页

```
┌─────────────────────────────────┐
│  ✕ 设置                         │
├─────────────────────────────────┤
│  当前用户: alice                │
│  状态: 已连接 ✓                 │
│                                 │
│  用户 ID                        │
│  [        alice         ]       │
│                                 │
│  Token                          │
│  [                      ]       │
│                                 │
│  服务器地址                      │
│  [ ws://localhost:8080/ws ]     │
│                                 │
│  ┌─────────────────────────┐   │
│  │       登出               │   │
│  └─────────────────────────┘   │
└─────────────────────────────────┘
```

## 🐛 故障排除

### 问题 1: SDK 找不到

**错误**: `No such module 'SwiftIM'`

**解决**:
```bash
# 1. 清理构建缓存
cd Talk
rm -rf ~/Library/Developer/Xcode/DerivedData

# 2. 重新打开 Xcode
open Talk.xcodeproj

# 3. 在 Xcode 中: Product → Clean Build Folder (Shift+Cmd+K)

# 4. 重新添加 Package 依赖（见上文）
```

### 问题 2: 连接失败

**错误**: 登录后显示"未连接"

**检查清单**:
- [ ] IM 服务器是否启动？
- [ ] 服务器地址配置是否正确？
- [ ] 网络是否可达？（ping 服务器）
- [ ] 查看 Xcode 控制台日志

**调试命令**:
```bash
# 检查服务器是否运行
lsof -i :8080

# 测试 WebSocket 连接
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: test" \
  http://localhost:8080/ws
```

### 问题 3: 消息发送失败

**可能原因**:
- 网络断开
- Token 过期
- 服务器错误

**解决步骤**:
1. 检查连接状态（设置页）
2. 重新登录
3. 查看服务器日志
4. 查看 Xcode 控制台

### 问题 4: 编译错误

**常见错误及解决**:

| 错误 | 解决方法 |
|-----|---------|
| `Cannot find type 'IMClient' in scope` | 添加 `import SwiftIM` |
| `Type '...' does not conform to protocol` | 实现所有必需的协议方法 |
| `Use of unresolved identifier` | 检查拼写和导入 |

## 📚 学习路径

### 初级（1-2 天）

1. ✅ 完成快速开始
2. ✅ 理解项目结构
3. ✅ 阅读核心文件代码
4. ✅ 尝试修改 UI 样式

### 中级（3-5 天）

1. 📖 深入理解 SDK API
2. 🔍 研究消息流转机制
3. 🎨 自定义消息 Cell
4. 📝 添加新功能（如消息撤回）

### 高级（1-2 周）

1. 🚀 性能优化
2. 🔧 架构改进
3. 📦 添加多媒体支持
4. 🌐 集成推送通知

## 📖 相关文档

- [README.md](README.md) - 项目说明
- [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md) - 详细集成指南
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) - 项目架构和设计
- [SwiftIM SDK 文档](../docs/) - SDK 完整文档

## 💡 提示和技巧

### 1. 使用 Xcode 调试工具

```
View → Debug Area → Show Debug Area (Cmd+Shift+Y)
```

### 2. 查看网络请求

在 AppDelegate 中启用详细日志：
```swift
IMLogger.shared.configure(IMLoggerConfig(level: .verbose))
```

### 3. 快速重新登录

在设置页登出后，上次输入的用户 ID 会被保存，下次可以直接点登录。

### 4. 模拟器快捷键

- `Cmd + D` - 切换深色/浅色模式
- `Cmd + Shift + H` - 返回主屏幕
- `Cmd + K` - 显示/隐藏键盘

## 🎉 下一步

恭喜！你已经成功运行了 Talk 应用。

**建议接下来：**

1. 📝 尝试添加新功能
2. 🎨 自定义 UI 样式
3. 📱 在真机上测试
4. 🚀 部署到服务器
5. 📦 发布到 TestFlight

## ❓ 需要帮助？

- 📖 查看文档：[docs/](../docs/)
- 🐛 提交问题：GitHub Issues
- 💬 社区讨论：GitHub Discussions

---

**祝你使用愉快！** 🎊

如果这个项目对你有帮助，请给个 ⭐️ Star！


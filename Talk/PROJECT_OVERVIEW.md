# Talk 项目概览

## 项目简介

Talk 是一个完整的 iOS 即时通讯应用示例，展示了如何使用 SwiftIM SDK 构建功能完善的聊天应用。该项目采用原生 UIKit 开发，代码结构清晰，易于理解和扩展。

## 技术特性

### ✅ 已实现的功能

- **用户认证**
  - 用户登录/登出
  - 自动登录（保存登录状态）
  - Token 认证
  - 登录状态持久化

- **对话管理**
  - 对话列表展示
  - 对话排序（按最后消息时间）
  - 未读消息数量显示
  - 创建新对话
  - 删除对话（滑动操作）
  - 对话信息更新（实时）

- **消息功能**
  - 发送文本消息
  - 接收实时消息
  - 消息历史加载
  - 消息状态显示（发送中/已发送/失败）
  - 消息时间智能显示
  - 自动滚动到最新消息

- **连接管理**
  - WebSocket 实时连接
  - 自动重连机制
  - 连接状态监听
  - 离线消息同步
  - 网络状态感知

- **用户体验**
  - 现代化的 UI 设计
  - 流畅的动画效果
  - 键盘自适应
  - 空状态提示
  - 加载指示器
  - 错误提示

## 项目架构

### 目录结构

```
Talk/
├── Talk/
│   ├── Models/                      # 数据模型
│   │   └── TalkConfig.swift         # 应用配置
│   │
│   ├── Extensions/                  # 扩展
│   │   ├── UIColor+Extensions.swift # 颜色扩展
│   │   └── Date+Extensions.swift    # 日期扩展
│   │
│   ├── Views/                       # 自定义视图
│   │   ├── ConversationCell.swift   # 对话列表 Cell
│   │   └── MessageCell.swift        # 消息 Cell
│   │
│   ├── ViewControllers/             # 视图控制器
│   │   ├── ConversationListViewController.swift  # 对话列表
│   │   ├── ChatViewController.swift              # 聊天页面
│   │   └── SettingsViewController.swift          # 设置页面
│   │
│   ├── AppDelegate.swift            # 应用代理
│   ├── SceneDelegate.swift          # 场景代理
│   └── Info.plist                   # 配置文件
│
├── Talk.xcodeproj/                  # Xcode 项目文件
├── README.md                        # 项目说明
├── INTEGRATION_GUIDE.md             # 集成指南
├── PROJECT_OVERVIEW.md              # 项目概览（本文件）
└── configure_sdk.sh                 # SDK 配置脚本
```

### 架构设计

```
┌─────────────────────────────────────────┐
│          View Controllers               │
│  (ConversationList, Chat, Settings)     │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│            SwiftIM SDK                  │
│  ┌─────────────────────────────────┐   │
│  │     IMClient (Singleton)        │   │
│  ├─────────────────────────────────┤   │
│  │  • ConversationManager          │   │
│  │  • MessageManager               │   │
│  │  • UserManager                  │   │
│  │  • ConnectionManager            │   │
│  └─────────────────────────────────┘   │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│          Network Layer                  │
│    (WebSocket + HTTP + Database)        │
└─────────────────────────────────────────┘
```

## 核心组件说明

### 1. TalkConfig

应用的全局配置文件，包含：
- 服务器地址配置
- UI 常量定义
- UserDefaults 键名定义

```swift
struct TalkConfig {
    static let imServerURL = "ws://localhost:8080/ws"
    static let apiServerURL = "http://localhost:8080"
}
```

### 2. ConversationListViewController

对话列表页面，主要功能：
- 显示所有对话
- 实时更新对话状态
- 创建新对话
- 跳转到聊天页面
- 监听消息和对话变化

**关键方法：**
```swift
func loadConversations()              // 加载对话列表
func createConversation(with userID:) // 创建新对话
func deleteConversation(at:)          // 删除对话
```

**实现的协议：**
- `UITableViewDataSource` - 列表数据源
- `UITableViewDelegate` - 列表交互
- `IMConversationListener` - 对话监听
- `IMMessageListener` - 消息监听

### 3. ChatViewController

聊天页面，主要功能：
- 显示消息历史
- 发送/接收消息
- 键盘自适应
- 自动滚动
- 消息状态更新

**关键方法：**
```swift
func loadMessages()           // 加载消息历史
func sendMessage(text:)       // 发送消息
func scrollToBottom()         // 滚动到底部
func markMessagesAsRead()     // 标记已读
```

**实现的协议：**
- `UITableViewDataSource` - 消息列表数据源
- `UITableViewDelegate` - 消息列表交互
- `UITextViewDelegate` - 输入框代理
- `IMMessageListener` - 消息监听

### 4. SettingsViewController

设置页面，主要功能：
- 用户登录/登出
- 服务器配置
- 连接状态显示
- 登录状态管理

**关键方法：**
```swift
func loginButtonTapped()      // 登录
func logoutButtonTapped()     // 登出
func updateUI()               // 更新 UI
```

**实现的协议：**
- `IMConnectionListener` - 连接状态监听

### 5. ConversationCell

对话列表单元格，显示：
- 用户头像
- 对话名称
- 最后一条消息
- 消息时间
- 未读消息数量

### 6. MessageCell

消息单元格，支持：
- 左右布局切换（发送/接收）
- 消息气泡样式
- 消息时间显示
- 多行文本自适应

## SDK 集成说明

### 初始化流程

```
App 启动
    ↓
AppDelegate.didFinishLaunching
    ↓
SceneDelegate.scene(_:willConnectTo:)
    ↓
初始化 SDK (IMClient.shared.initialize)
    ↓
检查登录状态
    ↓
自动登录（如果已保存）
    ↓
显示对话列表
```

### 监听器注册

应用中注册了以下监听器：

1. **ConversationListViewController**
   - `IMConversationListener` - 监听对话变化
   - `IMMessageListener` - 监听新消息（更新列表）

2. **ChatViewController**
   - `IMMessageListener` - 监听消息收发

3. **SettingsViewController**
   - `IMConnectionListener` - 监听连接状态

### 数据流转

```
用户操作
    ↓
ViewController 调用 SDK API
    ↓
SDK 处理业务逻辑
    ↓
通过监听器回调通知
    ↓
ViewController 更新 UI
```

## UI/UX 设计

### 颜色方案

定义在 `UIColor+Extensions.swift` 中：

- **主题色**: `.talkPrimary` (系统蓝)
- **背景色**: `.talkBackground` (分组背景)
- **文本色**: `.talkTextPrimary` / `.talkTextSecondary`
- **气泡色**: 
  - 发送: `.talkBubbleSent` (蓝色)
  - 接收: `.talkBubbleReceived` (灰色)

### 布局规范

- **间距**: 8pt 的倍数（8, 12, 15, 20, 30）
- **圆角**: 8-12pt
- **字体**: 系统字体
  - 标题: 16-17pt, Medium
  - 正文: 14-16pt, Regular
  - 辅助: 11-12pt, Regular

### 交互设计

- **轻触反馈**: Cell 高亮
- **滑动操作**: 删除对话
- **下拉刷新**: 加载更多消息（可扩展）
- **键盘处理**: 自动适应，点击隐藏
- **空状态**: 友好的提示图标和文字

## 扩展指南

### 添加新的消息类型

1. 在 SDK 中定义消息类型（IMMessageType）
2. 创建对应的 Cell 类
3. 在 ChatViewController 中注册和处理

### 添加群聊功能

1. 使用 IMGroupManager
2. 修改 ConversationCell 显示群组信息
3. 在 ChatViewController 中处理群组消息

### 添加多媒体消息

1. 使用 IMFileManager 上传文件
2. 创建专门的多媒体 Cell
3. 实现预览和下载功能

### 集成推送通知

1. 配置 APNs
2. 在 AppDelegate 中注册推送
3. 处理远程通知
4. 与 SDK 的消息同步

## 测试指南

### 单元测试

建议测试的模块：
- TalkConfig 配置验证
- 日期格式化功能
- 颜色扩展方法

### UI 测试

建议测试的场景：
- 登录流程
- 发送消息
- 接收消息
- 对话创建
- 对话删除

### 集成测试

测试多用户场景：
1. 启动两个模拟器
2. 分别登录不同用户
3. 相互发送消息
4. 验证消息同步

## 性能优化

### 已实现的优化

- **Cell 复用**: UITableView 标准复用机制
- **图片缓存**: 头像加载（待实现网络图片）
- **延迟加载**: 消息分页加载
- **内存管理**: 使用 weak 引用避免循环引用

### 可优化的方向

- 消息列表虚拟化（超长列表）
- 图片压缩和缩略图
- 数据库索引优化
- 网络请求合并

## 依赖管理

### Swift Package Manager

项目使用 SPM 管理依赖：

```swift
dependencies: [
    .package(path: "../")  // SwiftIM SDK (本地包)
]
```

### SDK 依赖

SwiftIM SDK 依赖：
- Alamofire (5.8.0+) - HTTP 网络
- Starscream (4.0.0+) - WebSocket
- CryptoSwift (1.8.0+) - 加密
- SwiftProtobuf (1.25.0+) - 协议

## 常见问题

### Q1: 如何修改服务器地址？

编辑 `Talk/Models/TalkConfig.swift`：
```swift
static let imServerURL = "ws://your-server:port/ws"
static let apiServerURL = "http://your-server:port"
```

### Q2: 如何添加新的页面？

1. 创建新的 ViewController
2. 在导航中添加跳转逻辑
3. 注册必要的 SDK 监听器
4. 在 deinit 中移除监听器

### Q3: 如何自定义 UI 样式？

修改 `UIColor+Extensions.swift` 中的颜色定义，或在各个 ViewController 中自定义视图样式。

### Q4: 如何调试 SDK 问题？

1. 在 AppDelegate 中设置日志级别为 `.debug`
2. 查看 Xcode 控制台输出
3. 检查网络请求和响应
4. 使用断点调试

## 版本历史

### v1.0.0 (2025-11-02)

**首次发布**

功能：
- ✅ 基础聊天功能
- ✅ 对话列表管理
- ✅ 用户登录/登出
- ✅ 实时消息收发
- ✅ 离线消息同步
- ✅ 自动重连
- ✅ 连接状态监听

UI：
- ✅ 对话列表页
- ✅ 聊天页面
- ✅ 设置页面
- ✅ 自定义 Cell
- ✅ 适配深色模式

文档：
- ✅ README.md
- ✅ INTEGRATION_GUIDE.md
- ✅ PROJECT_OVERVIEW.md
- ✅ 配置脚本

## 贡献指南

欢迎提交 Pull Request！

建议的贡献方向：
- 🎨 UI/UX 改进
- ⚡️ 性能优化
- 🐛 Bug 修复
- 📝 文档完善
- ✨ 新功能实现

## 许可证

MIT License

## 联系方式

- Issue: [GitHub Issues](https://github.com/your-repo/issues)
- Email: your-email@example.com

---

**最后更新**: 2025-11-02
**作者**: Arwen
**版本**: 1.0.0


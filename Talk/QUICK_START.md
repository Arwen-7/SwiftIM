# Talk 快速启动指南

## 🎯 快速开始

### 1. 启动服务器（终端 1）

```bash
cd /Users/arwen/Project/IM/IM-Server
go run cmd/server/main.go
```

等待看到类似输出：
```
✅ IM Server started on :8080
✅ WebSocket endpoint: ws://localhost:8080/ws
```

### 2. 编译运行 Talk 应用

#### 方式 A: 使用 Xcode（推荐）

1. 双击打开文件：
   ```
   /Users/arwen/Project/IM/IM-iOS-SDK/Talk/Talk.xcodeproj
   ```

2. 等待 Xcode 解析依赖（首次打开需要一些时间）

3. 选择目标设备：
   - Product -> Destination -> iPhone 15 (或其他模拟器)

4. 运行应用：
   - 点击播放按钮，或按 `⌘R`

#### 方式 B: 使用命令行（需要 Xcode）

```bash
# 确保已安装 Xcode
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# 编译运行
cd /Users/arwen/Project/IM/IM-iOS-SDK/Talk
xcodebuild -project Talk.xcodeproj \
  -scheme Talk \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

### 3. 登录应用

首次运行会自动打开设置页面：

1. **用户 ID**: 输入任意字符串（例如：`user1`）
2. **Token**: 可以留空（演示模式会自动生成）
3. **服务器地址**: 默认 `ws://localhost:8080/ws`（如需修改可更改）
4. 点击 **登录** 按钮

登录成功后会显示：
```
✅ 当前用户: user1
状态: 已连接
```

### 4. 测试聊天

#### 单人测试（自己给自己发消息）
1. 点击右上角的 ✉️ (撰写) 按钮
2. 输入对方用户 ID（例如：`user1` - 自己）
3. 输入消息并发送
4. 消息会出现在聊天窗口

#### 多人测试（需要两个设备/模拟器）

**设备 1（模拟器 iPhone 15）：**
```bash
# 运行第一个实例
cd /Users/arwen/Project/IM/IM-iOS-SDK/Talk
xcodebuild -project Talk.xcodeproj \
  -scheme Talk \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  run
```
登录为 `user1`

**设备 2（模拟器 iPhone 15 Pro）：**
在 Xcode 中：
- Window -> Devices and Simulators
- 启动另一个模拟器（例如 iPhone 15 Pro）
- 再次运行 Talk 应用
- 登录为 `user2`

**开始聊天：**
- 在 user1 的设备上创建与 user2 的对话
- 发送消息，user2 会实时收到
- user2 回复，user1 会实时收到

## 📱 应用功能

### 对话列表
- ✅ 显示所有对话
- ✅ 显示最后一条消息
- ✅ 显示未读消息数量
- ✅ 智能时间显示（今天、昨天、日期）
- ✅ 滑动删除对话

### 聊天页面
- ✅ 实时收发消息
- ✅ 自动标记已读
- ✅ 键盘自动适配
- ✅ 消息气泡样式
- ✅ 发送状态提示

### 设置页面
- ✅ 用户登录/登出
- ✅ 连接状态显示
- ✅ 服务器地址配置

## 🐛 问题排查

### 问题 1: 无法连接服务器
**症状**: 登录失败，显示"网络未连接"

**解决方案**:
1. 检查服务器是否启动：
   ```bash
   curl http://localhost:8080
   # 应该返回服务器响应
   ```

2. 检查端口是否被占用：
   ```bash
   lsof -i :8080
   # 如果有其他进程占用，需要先停止
   ```

3. 查看服务器日志，确认连接请求

### 问题 2: 消息发送失败
**症状**: 消息显示"发送失败"

**解决方案**:
1. 检查网络连接状态（设置页面）
2. 重新登录
3. 重启服务器和应用

### 问题 3: 收不到对方消息
**症状**: 对方发送消息，但没有收到

**解决方案**:
1. 确认双方都已成功登录
2. 检查服务器日志，查看消息是否发送
3. 尝试重启应用或重新连接

### 问题 4: Xcode 找不到 SwiftIM 模块
**症状**: `No such module 'SwiftIM'`

**解决方案**:
1. 确认 Package 依赖已添加：
   - File -> Add Package Dependencies
   - Add Local -> 选择 IM-iOS-SDK 目录
   
2. 清理构建：
   ```
   Product -> Clean Build Folder (⇧⌘K)
   ```

3. 重新构建：
   ```
   Product -> Build (⌘B)
   ```

4. 如果还不行，重启 Xcode

### 问题 5: 模拟器无法启动
**症状**: Xcode 提示模拟器错误

**解决方案**:
```bash
# 重启模拟器服务
sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService

# 重新打开 Xcode
```

## 📊 查看日志

### 应用日志
在 Xcode 中：
- View -> Debug Area -> Activate Console (⇧⌘C)
- 查看实时日志输出

### 服务器日志
在服务器终端查看输出，或查看日志文件：
```bash
tail -f /Users/arwen/Project/IM/IM-Server/logs/im-server.log
```

## 🔧 配置选项

### 修改服务器地址
编辑 `Talk/Models/TalkConfig.swift`：
```swift
struct TalkConfig {
    static let imServerURL = "ws://your-server:8080/ws"
    static let apiServerURL = "http://your-server:8080"
}
```

### 修改日志级别
编辑 `Talk/AppDelegate.swift`：
```swift
IMLogger.shared.configure(IMLoggerConfig(
    level: .debug,        // .debug, .info, .warning, .error
    enableConsole: true,  // 控制台输出
    enableFile: false     // 文件输出
))
```

## 📚 相关文档

- [编译问题修复报告](COMPILATION_FIXES.md) - 查看所有修复的编译问题
- [实现总结](IMPLEMENTATION_SUMMARY.md) - 查看实现细节
- [README](README.md) - 完整的项目文档
- [SDK 文档](../docs/) - SDK API 文档

## 💡 提示

1. **第一次登录很慢？** 这是正常的，因为需要初始化数据库和建立连接

2. **消息顺序混乱？** 刷新一下对话列表或重新进入聊天页面

3. **想要更多功能？** 查看 README.md 中的"下一步"部分，了解如何扩展功能

4. **需要帮助？** 查看源代码注释或提交 Issue

## 🎉 成功标志

如果看到以下情况，说明一切正常：

- ✅ 服务器启动成功，监听在 8080 端口
- ✅ 应用成功编译并启动
- ✅ 登录成功，显示"已连接"状态
- ✅ 可以创建对话并发送消息
- ✅ 消息实时显示在聊天界面

**祝你使用愉快！** 🚀






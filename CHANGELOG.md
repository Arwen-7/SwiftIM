# IM-iOS-SDK Changelog

## [Unreleased] - 2025-10-27

### ✨ Added - WebSocket 独立协议实现

#### 核心功能
- **IMWebSocketMessage** - WebSocket 专用轻量级消息封装格式（18字节 header）
  - 支持 9 种命令类型的完整编解码
  - Big Endian 字节序
  - 完整的错误处理（`invalidDataLength`, `invalidCommand`, `bodyLengthMismatch`）

- **WebSocket 消息结构** (`IMProtocolMessages+WebSocket.swift`)
  - `WSAuthResponse` - 认证响应
  - `WSPushMessage` - 推送消息
  - `WSBatchMessages` - 批量消息
  - `WSRevokeMessagePush` - 撤回通知
  - `WSReadReceiptPush` - 已读回执
  - `WSTypingStatusPush` - 输入状态
  - `WSKickOutNotification` - 踢出通知
  - `WSSyncResponse` - 同步响应
  - `WSHeartbeatResponse` - 心跳响应

- **9 个 WebSocket 消息处理器** (`IMClient.swift`)
  - `handleWebSocketPushMessage` - 接收新消息并保存
  - `handleWebSocketAuthResponse` - 处理认证结果，自动触发离线同步
  - `handleWebSocketHeartbeatResponse` - 心跳响应，计算时间差
  - `handleWebSocketBatchMessages` - 批量消息处理，支持去重和统计
  - `handleWebSocketRevokeMessage` - 消息撤回通知
  - `handleWebSocketReadReceipt` - 已读回执同步
  - `handleWebSocketTypingStatus` - 输入状态推送
  - `handleWebSocketKickOut` - 强制下线通知
  - `handleWebSocketSyncResponse` - 离线消息同步响应

- **IMClient 路由增强**
  - 基于 `transportType` 的分层路由
  - TCP: 使用 `IMPacket` + `IMMessageRouter`
  - WebSocket: 使用 `IMWebSocketMessage` + command-based handlers

#### 错误处理
- 新增 `IMError.kickedOut(String)` - 被服务器踢出错误

#### 跨平台支持
- 修复 `UIKit` 导入问题，支持 iOS/macOS
  - `IMFileManager.swift`
  - `IMFileManagerExtensions.swift`
  - `IMCache.swift`
- 修复 `CryptoSwift` API 使用（`Data.bytes` → `Array(data)`）
- 修复 `Alamofire` 导入缺失（`IMUserManager.swift`）

#### 测试
- 新增 `IMWebSocketMessageTests.swift` - 14 个单元测试
  - 编码测试（简单、空body、大序列号）
  - 解码测试（简单、空body、所有命令类型）
  - 错误处理测试（数据长度、无效命令、body不匹配）
  - 往返测试（多种消息、二进制数据）
  - 性能测试（1000次编码/解码）

#### 文档
- 新增 `docs/WebSocket_Protocol_Implementation.md` - 协议实现文档
- 新增 `docs/WebSocket_Handlers_Implementation.md` - 处理器实现文档
- 新增 `docs/WebSocket_Implementation_Summary.md` - 实现总结
- 更新 `Sources/IMSDK/Core/Protocol/IMProtocol.proto` - 添加 `WebSocketMessage` 定义

#### 架构优化
- TCP 和 WebSocket 传输层分离，各自使用最优的消息格式
- WebSocket 避免重复的 header 开销（无需 magic、version、CRC）
- 统一的 `IMTransportProtocol` 接口，上层无感知
- 清晰的分层架构：传输层 → 路由层 → 业务层

### 🐛 Fixed
- 修复 macOS 编译错误（UIKit 不可用）
- 修复 `CryptoSwift.Data.bytes` 属性不存在
- 修复 `IMUserManager` 缺少 Alamofire 导入
- 修复 `IMClient` 网络状态占位符错误

### 📝 Technical Details

#### 消息格式对比

**TCP (IMPacket)**:
```
16字节 Header: Magic(2) + Version(1) + Reserved(1) + Length(4) 
             + Command(2) + Sequence(4) + CRC16(2)
+ Protobuf Body
```

**WebSocket (IMWebSocketMessage)**:
```
18字节 Header: Command(2) + Sequence(4) + Timestamp(8) + BodyLength(4)
+ JSON/Protobuf Body
```

**优势**:
- WebSocket Frame 提供消息边界，无需手动处理粘包/拆包
- WebSocket Frame 提供校验，无需 CRC16
- 更轻量，更符合 WebSocket 语义

#### 编译状态
- ✅ 编译通过（`swift build`）
- ⚠️ 少量警告（Protobuf 版本、未使用变量）

---

## 版本历史

### 待发布
- WebSocket 独立协议实现
- 双传输层架构（TCP + WebSocket）
- 完整的消息处理器
- 跨平台支持

### 已实现的核心功能
- IM 基础架构（分层设计）
- TCP Socket 传输层（自研协议）
- WebSocket 传输层（Starscream）
- 消息队列与重传机制
- 增量消息同步
- 消息分页加载
- 消息搜索
- 网络监听
- 输入状态同步
- 会话未读计数
- 消息去重机制
- 富媒体消息（图片、音频、视频、文件）
- 断点续传
- 文件压缩
- 视频封面提取
- 消息撤回（P0）
- 消息已读回执（P0）
- SQLite + WAL 数据库
- 端到端加密
- 重连机制
- 心跳保活
- Protobuf 序列化
- CRC16 校验
- 序列号连续性检查

---

## 未来计划

### 短期
- [ ] 运行 WebSocket 单元测试
- [ ] 编译 Protobuf 生成正式代码
- [ ] WebSocket 消息迁移到 Protobuf 二进制编解码

### 中期
- [ ] 集成测试（端到端）
- [ ] 性能测试与优化
- [ ] 性能监控指标

### 长期
- [ ] QUIC/HTTP3 支持
- [ ] 更多 IM 高级特性

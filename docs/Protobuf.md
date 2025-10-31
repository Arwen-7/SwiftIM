# Protobuf 协议文档

## 概述

IMSDK 使用 [Protocol Buffers](https://developers.google.com/protocol-buffers) 作为消息协议格式，相比 JSON 具有以下优势：

- ✅ **更小的体积**：二进制格式，传输数据量更少
- ✅ **更快的速度**：序列化/反序列化性能更高
- ✅ **向后兼容**：schema 演化，兼容旧版本
- ✅ **类型安全**：强类型定义，减少错误

## 协议结构

### 数据包（Packet）

所有通信都使用统一的数据包格式：

```protobuf
message Packet {
    PacketType type = 1;        // 包类型
    int64 seq = 2;              // 序列号
    bytes data = 3;             // 数据（Protobuf 或 JSON）
    int64 timestamp = 4;        // 时间戳
}
```

### 包类型（PacketType）

```protobuf
enum PacketType {
    PACKET_TYPE_UNKNOWN = 0;
    HEARTBEAT = 1;              // 心跳
    HEARTBEAT_ACK = 2;          // 心跳响应
    MESSAGE = 100;              // 消息
    MESSAGE_ACK = 101;          // 消息确认
    MESSAGE_READ = 102;         // 消息已读
    MESSAGE_REVOKE = 103;       // 消息撤回
    SYNC = 200;                 // 同步请求
    SYNC_ACK = 201;             // 同步响应
    NOTIFICATION = 300;         // 通知
}
```

## 消息类型

### 1. 心跳（Heartbeat）

**说明**：保持连接活跃（实际由 WebSocket Ping/Pong 处理）

```protobuf
message Heartbeat {
    int64 timestamp = 1;
}

message HeartbeatAck {
    int64 timestamp = 1;
}
```

### 2. 消息确认（MessageAck）

**说明**：确认消息已收到/已读

```protobuf
message MessageAck {
    string message_id = 1;      // 消息 ID
    int32 status = 2;           // 状态：0=发送中, 1=已发送, 2=已送达, 3=已读
}
```

### 3. 消息已读（MessageRead）

**说明**：批量标记消息为已读

```protobuf
message MessageRead {
    repeated string message_ids = 1;  // 消息 ID 列表
}
```

### 4. 同步请求（SyncRequest）

**说明**：请求增量消息同步

```protobuf
message SyncRequest {
    int64 last_seq = 1;         // 最后同步的序列号
}

message SyncResponse {
    repeated Packet packets = 1; // 增量消息包
    int64 current_seq = 2;      // 当前最新序列号
    bool has_more = 3;          // 是否还有更多
}
```

### 5. 通知（Notification）

**说明**：系统通知、好友请求等

```protobuf
message Notification {
    string type = 1;            // 通知类型
    bytes data = 2;             // 通知数据
}
```

## 数据流转

### 发送消息流程

```
1. 创建 IMMessage 对象
   ↓
2. 序列化为 JSON（消息体）
   ↓
3. 创建 Packet，type=MESSAGE
   ↓
4. 序列化 Packet 为 Protobuf 二进制
   ↓
5. 通过 WebSocket 发送
```

### 接收消息流程

```
1. WebSocket 收到二进制数据
   ↓
2. 反序列化为 Packet（Protobuf）
   ↓
3. 根据 type 判断消息类型
   ↓
4. 提取 data 字段
   ↓
5. 反序列化为具体类型（Protobuf 或 JSON）
   ↓
6. 处理业务逻辑
```

## 混合使用 Protobuf 和 JSON

### 设计原则

- **协议层**使用 Protobuf（Packet）
  - 更高效的传输
  - 统一的包格式
  
- **业务层**使用 JSON（Message）
  - 更灵活的扩展
  - 更容易调试
  - 保持兼容性

### 示例

```swift
// 1. 创建消息（JSON）
let message = IMMessage()
message.messageID = "123"
message.content = "Hello"
let messageJSON = try JSONEncoder().encode(message)

// 2. 封装为 Packet（Protobuf）
var packet = Im_Packet()
packet.type = .message
packet.seq = 1
packet.data = messageJSON
packet.timestamp = currentTime

// 3. 序列化并发送
let packetData = try packet.serializedData()
websocket.send(data: packetData)
```

## 生成 Swift 代码

### 前置条件

```bash
# 安装 protoc 编译器
brew install protobuf

# 安装 Swift Protobuf 插件
brew install swift-protobuf
```

### 生成代码

```bash
# 使用脚本自动生成
./Scripts/generate_proto.sh

# 或手动生成
protoc \
    --proto_path=Protos \
    --swift_out=Sources/IMSDK/Core/Protocol/Generated \
    Protos/im_protocol.proto
```

### 生成的文件

```
Sources/IMSDK/Core/Protocol/Generated/
└── im_protocol.pb.swift    # Protobuf 生成的 Swift 代码
```

## 使用示例

### 编码

```swift
// 创建心跳包
var heartbeat = Im_Heartbeat()
heartbeat.timestamp = IMUtils.currentTimeMillis()

// 封装为 Packet
var packet = Im_Packet()
packet.type = .heartbeat
packet.seq = 1
packet.data = try heartbeat.serializedData()

// 序列化并发送
let data = try packet.serializedData()
websocket.send(data: data)
```

### 解码

```swift
// 接收数据
let receivedData: Data = ...

// 反序列化 Packet
let packet = try Im_Packet(serializedData: receivedData)

// 根据类型处理
switch packet.type {
case .heartbeatAck:
    let ack = try Im_HeartbeatAck(serializedData: packet.data)
    print("Heartbeat ACK: \(ack.timestamp)")
    
case .messageAck:
    let ack = try Im_MessageAck(serializedData: packet.data)
    print("Message ACK: \(ack.messageID)")
    
default:
    break
}
```

## 性能对比

### JSON vs Protobuf

| 维度 | JSON | Protobuf | 提升 |
|------|------|----------|------|
| 数据大小 | 100% | 30-50% | 50-70% |
| 序列化速度 | 100% | 200-300% | 2-3倍 |
| 反序列化速度 | 100% | 200-400% | 2-4倍 |

### 实际场景

假设一条消息 200 字节：

```
JSON 格式：
- Packet 外层（JSON）: ~80 字节
- Message 内容（JSON）: ~200 字节
- 总计: ~280 字节

Protobuf 格式：
- Packet 外层（Protobuf）: ~20 字节
- Message 内容（JSON）: ~200 字节
- 总计: ~220 字节

节省: ~21%
```

## 扩展协议

### 添加新的消息类型

1. **修改 .proto 文件**

```protobuf
// 添加新的包类型
enum PacketType {
    // ...
    VOICE_CALL = 400;          // 语音通话
    VIDEO_CALL = 401;          // 视频通话
}

// 添加新的消息定义
message VoiceCall {
    string call_id = 1;
    string caller_id = 2;
    string callee_id = 3;
    int32 status = 4;
}
```

2. **重新生成代码**

```bash
./Scripts/generate_proto.sh
```

3. **实现业务逻辑**

```swift
// 编码
func encodeVoiceCall(_ call: VoiceCall) throws -> Data {
    var voiceCall = Im_VoiceCall()
    voiceCall.callID = call.id
    voiceCall.callerID = call.callerID
    voiceCall.calleeID = call.calleeID
    
    let packet = Im_Packet(type: .voiceCall, seq: nextSeq(), data: try voiceCall.serializedData())
    return try packet.serializedData()
}

// 解码
case .voiceCall:
    let call = try Im_VoiceCall(serializedData: packet.data)
    handleVoiceCall(call)
```

## 向后兼容

### 字段演化规则

1. ✅ **可以添加**新字段（老版本会忽略）
2. ✅ **可以删除**旧字段（标记为 reserved）
3. ❌ **不能修改**字段编号
4. ❌ **不能修改**字段类型

### 版本兼容示例

```protobuf
// v1.0
message User {
    string user_id = 1;
    string nickname = 2;
}

// v2.0 - 添加新字段
message User {
    string user_id = 1;
    string nickname = 2;
    string avatar = 3;      // 新增
    int32 age = 4;          // 新增
}

// v3.0 - 删除旧字段
message User {
    string user_id = 1;
    string nickname = 2;
    reserved 3;             // 标记为保留
    string avatar_url = 4;  // 重命名
    int32 age = 5;
}
```

## 最佳实践

1. **保持协议简单**
   - 只定义必要字段
   - 避免嵌套过深

2. **使用合适的类型**
   - 整数：int32, int64
   - 字符串：string
   - 二进制：bytes
   - 列表：repeated

3. **预留扩展空间**
   - 跳过一些编号（如 10, 20, 30...）
   - 便于后续插入字段

4. **文档化**
   - 添加注释说明字段含义
   - 记录版本变更

## 参考资料

- [Protocol Buffers 官方文档](https://developers.google.com/protocol-buffers)
- [Swift Protobuf 文档](https://github.com/apple/swift-protobuf/blob/main/Documentation)
- [Protobuf 语言指南](https://developers.google.com/protocol-buffers/docs/proto3)


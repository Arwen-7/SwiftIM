# Sequence 设计方案

## 📋 设计理念

参考 **OpenIM SDK** 和 **微信 Mars** 的成熟设计，我们采用**简单可靠**的 Sequence 设计方案。

## 🎯 核心原则

### **Sequence 只用于请求-响应匹配**

```swift
// 客户端发送请求
let seq = sequenceGenerator.next()  // seq = 1
transport.send(command: .sendMsgReq, sequence: seq, body: ...)

// 服务器响应
// 服务器回显相同的 seq = 1
response(command: .sendMsgRsp, sequence: 1, ...)

// 客户端接收
if let callback = pendingRequests.removeValue(forKey: 1) {
    // ✅ 通过 seq 匹配到请求，执行回调
    callback(.success(body))
}
```

### **不检测服务器推送的 Sequence 连续性**

**原因：**
1. ✅ **TCP 本身已保证字节流可靠传输**
   - TCP 协议栈确保数据不丢失、不重复、按序到达
   - 应用层无需再次检测

2. ✅ **服务器推送可能来自不同实例**
   - 负载均衡场景下，推送可能来自不同服务器
   - Sequence 可能不连续，但这是正常的

3. ✅ **消息顺序由业务层 Message.seq 保证**
   - 服务器为每条消息分配全局唯一的 `message.seq`
   - 用于消息排序、去重、增量同步

## 📊 分层设计

参考 OpenIM SDK 的分层架构：

| 层次 | 字段名 | 生成者 | 作用域 | 用途 |
|------|--------|--------|--------|------|
| **业务层** | `message.seq` | 服务器 | 全局 | 消息排序、去重、增量同步 |
| **协议层** | `packet.sequence` | 客户端 | 单次连接 | 请求-响应匹配 |
| **传输层** | TCP 序列号 | TCP 栈 | TCP 连接 | 字节流可靠传输 |

### **各层职责：**

#### 1️⃣ **传输层（TCP）**
```
职责：保证字节流可靠传输
- 自动重传丢失的包
- 保证数据按序到达
- 检测并丢弃重复数据
```

#### 2️⃣ **协议层（Packet Sequence）**
```swift
// 只用于请求-响应匹配
private var pendingRequests: [UInt32: Completion] = [:]

// 客户端请求
let seq = sequenceGenerator.next()
pendingRequests[seq] = completion

// 服务器响应（回显相同的 seq）
if let callback = pendingRequests.removeValue(forKey: seq) {
    callback(.success(body))
}
```

#### 3️⃣ **业务层（Message Seq）**
```swift
// 服务器分配的全局序列号
struct IMMessage {
    var seq: Int64        // 全局唯一，用于排序
    var messageID: String // 消息唯一标识
    var sendTime: Int64   // 发送时间
    // ...
}

// 增量同步
func syncOfflineMessages() {
    let localMaxSeq = database.getMaxSeq()
    // 从本地最大 seq + 1 开始同步
    httpManager.syncMessages(lastSeq: localMaxSeq) { ... }
}

// 消息去重
func saveMessage(_ message: IMMessage) {
    if database.getMessage(messageID: message.messageID) != nil {
        return  // 已存在，跳过
    }
    database.save(message)
}
```

## 🔍 与之前方案的对比

### ❌ **之前的复杂方案（已废弃）**

```swift
// 尝试检测服务器推送的 sequence 连续性
private var lastServerPushSequence: UInt32 = 0

func checkServerPushSequence(_ received: UInt32) {
    let expected = lastServerPushSequence + 1
    if received != expected {
        // ❌ 误判：服务器推送可能来自不同实例
        // ❌ 多余：TCP 已经保证可靠传输
    }
}
```

**问题：**
- 过度设计，增加复杂度
- 可能误判正常情况为丢包
- 与 TCP 的可靠性保证重复

### ✅ **简化方案（当前）**

```swift
// Sequence 只用于请求-响应匹配
func handlePacket(_ packet: IMPacket) {
    // 1. 尝试匹配响应
    if let callback = pendingRequests.removeValue(forKey: sequence) {
        callback(.success(body))  // ✅ 匹配成功
        return
    }
    
    // 2. 处理推送（不检查 sequence）
    onReceive?(body)  // ✅ 交给业务层处理
}
```

**优势：**
- ✅ 简单可靠
- ✅ 符合业界实践（OpenIM、微信 Mars）
- ✅ 职责清晰，分层明确
- ✅ 避免误判和过度设计

## 📚 参考资料

### **OpenIM SDK**
- GitHub: [openimsdk/openim-sdk-core](https://github.com/openimsdk/openim-sdk-core)
- 设计特点：
  - `OperationID`（UUID）：业务层追踪
  - `Sequence`（递增）：协议层请求匹配
  - `Message.seq`（全局）：消息层排序同步

### **微信 Mars**
- 设计特点：
  - Sequence 只用于请求-响应匹配
  - 不检测服务器推送的 sequence 连续性
  - 消息有独立的 Message Seq

## 🎯 总结

**我们的设计遵循以下原则：**

1. ✅ **相信 TCP 的可靠性**
   - TCP 协议栈已经处理了丢包、重传、乱序
   - 应用层无需重复劳动

2. ✅ **Sequence 单一职责**
   - 只用于请求-响应匹配
   - 不用于丢包检测

3. ✅ **业务层负责消息逻辑**
   - 使用 `message.seq` 进行排序、去重
   - 使用增量同步保证消息完整性

4. ✅ **简单即是美**
   - 避免过度设计
   - 遵循成熟 IM SDK 的最佳实践

---

**参考文档：**
- [OpenIM SDK Core](https://github.com/openimsdk/openim-sdk-core)
- [TCP 协议可靠性保证](https://datatracker.ietf.org/doc/html/rfc793)


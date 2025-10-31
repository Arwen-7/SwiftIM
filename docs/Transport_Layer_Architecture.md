# 传输层架构设计文档

## 📐 整体架构

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      业务层（Business Layer）                │
│                                                               │
│  IMClient, IMMessageManager, IMConversationManager, etc.   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  传输层抽象（Transport Protocol）            │
│                                                               │
│                   IMTransportProtocol                        │
│  统一接口：connect, disconnect, send, onReceive, etc.       │
└─────────────────────────────────────────────────────────────┘
                              ↓
              ┌───────────────┴────────────────┐
              ↓                                ↓
┌──────────────────────────┐      ┌──────────────────────────┐
│  IMWebSocketTransport    │      │    IMTCPTransport        │
│  （WebSocket 传输层）     │      │   （TCP Socket 传输层）   │
├──────────────────────────┤      ├──────────────────────────┤
│ • 包装现有 WebSocket     │      │ • 自研二进制协议         │
│ • 标准 WebSocket 协议    │      │ • 粘包/拆包处理          │
│ • Web 端兼容性好         │      │ • 极致性能优化           │
│ • 快速开发迭代           │      │ • 亿级用户支持           │
└──────────────────────────┘      └──────────────────────────┘
         ↓                                    ↓
┌──────────────────────────┐      ┌──────────────────────────┐
│   IMWebSocketManager     │      │   IMTCPSocketManager     │
│   (Starscream)           │      │   (Network.framework)    │
└──────────────────────────┘      └──────────────────────────┘
```

### 核心组件

#### 1. **IMTransportProtocol（传输层协议）**
```swift
/// 统一的传输层接口
public protocol IMTransportProtocol: AnyObject {
    var transportType: IMTransportType { get }
    var state: IMTransportState { get }
    var isConnected: Bool { get }
    
    var onStateChange: ((IMTransportState) -> Void)? { get set }
    var onReceive: ((Data) -> Void)? { get set }
    var onError: ((IMTransportError) -> Void)? { get set }
    
    func connect(url: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void)
    func disconnect()
    func send(data: Data, completion: ((Result<Void, IMTransportError>) -> Void)?)
    func send(text: String, completion: ((Result<Void, IMTransportError>) -> Void)?)
}
```

**设计优势**：
- ✅ 业务层不关心底层实现（WebSocket 还是 TCP）
- ✅ 可以在运行时动态切换传输层
- ✅ 易于测试（可以 Mock）
- ✅ 易于扩展（未来可添加 QUIC 等）

#### 2. **IMPacket（自定义二进制协议）**

**包头格式**（16 字节）：
```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Magic  | Ver    | CmdID  | Seq    | BodyLen          | Reserved        |
| 2 byte | 1 byte | 2 byte | 4 byte | 4 byte           | 3 byte          |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

- **Magic**: 0xEF89（协议魔数，用于识别合法包）
- **Ver**: 协议版本（当前为 1）
- **CmdID**: 命令类型（连接、认证、消息、心跳等）
- **Seq**: 序列号（请求-响应匹配、去重、排序）
- **BodyLen**: 包体长度
- **Reserved**: 保留字段（未来扩展）

**包体**：使用 Protobuf 序列化

**优势**：
- ✅ 协议开销小（仅 16 字节包头）
- ✅ 二进制高效（比 JSON 省流量 60-80%）
- ✅ 支持扩展（保留字段）
- ✅ 易于版本管理

#### 3. **IMPacketCodec（粘包/拆包处理器）**

TCP 是流式协议，需要处理：
- **粘包**：多个包粘在一起
- **拆包**：一个包被拆成多段

**处理逻辑**：
```
接收缓冲区：[数据流]
    ↓
1. 读取 16 字节包头
    ↓
2. 从包头获取包体长度
    ↓
3. 检查缓冲区是否有完整的包体
    ├─ 是 → 提取完整包 → 继续解析下一个
    └─ 否 → 等待更多数据
```

#### 4. **IMTCPSocketManager（TCP Socket 管理）**

基于 **Network.framework**（iOS 12+）

**优势**：
- ✅ 原生 TLS 支持
- ✅ 自动处理网络切换（WiFi ↔ 4G）
- ✅ 支持 IPv4/IPv6 双栈
- ✅ 更好的性能和电量管理

**核心功能**：
- TCP 连接建立
- 数据发送/接收
- Keep-Alive 配置
- 连接状态监控

#### 5. **IMTransportFactory（传输层工厂）**

根据配置创建不同的传输层：

```swift
// 创建 WebSocket 传输层
let transport = IMTransportFactory.createWebSocketTransport(url: "wss://im.example.com")

// 创建 TCP 传输层
let transport = IMTransportFactory.createTCPTransport(url: "tcps://im.example.com:8888")

// 根据配置创建
let config = IMTransportConfig(type: .tcp, url: "tcps://im.example.com:8888")
let transport = IMTransportFactory.createTransport(with: config)
```

#### 6. **IMTransportSwitcher（协议切换器）**

**运行时动态切换传输层**：

```swift
let switcher = IMTransportSwitcher(initialType: .webSocket, url: "wss://im.example.com")

// 连接
switcher.connect(url: url, token: token) { result in
    // ...
}

// 智能切换（根据网络质量）
switcher.smartSwitch(quality: .poor) { result in
    switch result {
    case .success:
        print("切换成功：WebSocket → TCP")
    case .failure(let error):
        print("切换失败：\(error)")
    }
}

// 手动切换
switcher.switchTo(type: .tcp) { result in
    // ...
}
```

**智能切换策略**：
```
网络质量优秀/良好：WebSocket（兼容性好、Web 支持）
网络质量较差/很差：TCP（更可靠、协议开销小）
```

---

## 🚀 使用指南

### 基础用法

#### 1. 使用 WebSocket 传输层

```swift
import IMSDK

// 创建 WebSocket 传输层
let transport = IMTransportFactory.createWebSocketTransport(url: "wss://im.example.com")

// 设置回调
transport.onStateChange = { state in
    print("状态变化：\(state)")
}

transport.onReceive = { data in
    print("收到数据：\(data.count) 字节")
}

transport.onError = { error in
    print("错误：\(error)")
}

// 连接
transport.connect(url: "wss://im.example.com", token: "your_token") { result in
    switch result {
    case .success:
        print("连接成功")
        
        // 发送数据
        let message = "Hello, WebSocket!".data(using: .utf8)!
        transport.send(data: message, completion: nil)
        
    case .failure(let error):
        print("连接失败：\(error)")
    }
}
```

#### 2. 使用 TCP 传输层

```swift
import IMSDK

// 创建 TCP 传输层
let transport = IMTransportFactory.createTCPTransport(url: "tcps://im.example.com:8888")

// 设置回调
transport.onStateChange = { state in
    print("状态变化：\(state)")
}

transport.onReceive = { data in
    // 接收到的是完整的协议包体（已处理粘包/拆包）
    print("收到数据：\(data.count) 字节")
}

// 连接
transport.connect(url: "tcps://im.example.com:8888", token: "your_token") { result in
    switch result {
    case .success:
        print("TCP 连接成功")
        
        // 发送消息（需要封装成协议包）
        let seq = IMSequenceGenerator.shared.next()
        let messageBody = """
        {"text":"Hello, TCP!","time":\(IMUtils.currentTimeMillis())}
        """.data(using: .utf8)!
        
        let codec = IMPacketCodec()
        let packet = codec.encode(command: .sendMsgReq, sequence: seq, body: messageBody)
        
        transport.send(data: packet, completion: nil)
        
    case .failure(let error):
        print("TCP 连接失败：\(error)")
    }
}
```

#### 3. 使用协议切换器

```swift
import IMSDK

// 创建协议切换器（默认使用 WebSocket）
let switcher = IMTransportSwitcher(initialType: .webSocket, url: "wss://im.example.com")

// 设置回调
switcher.onStateChange = { state in
    print("状态：\(state)")
}

switcher.onReceive = { data in
    print("收到数据：\(data.count) 字节")
}

switcher.onTransportSwitch = { oldType, newType in
    print("协议切换：\(oldType) → \(newType)")
}

// 连接
switcher.connect(url: "wss://im.example.com", token: "your_token") { result in
    switch result {
    case .success:
        print("连接成功，当前协议：\(switcher.currentTransportType)")
        
        // 模拟检测到弱网环境，智能切换到 TCP
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            switcher.smartSwitch(quality: .poor) { result in
                switch result {
                case .success:
                    print("已切换到 TCP 协议（更适合弱网）")
                case .failure(let error):
                    print("切换失败：\(error)")
                }
            }
        }
        
    case .failure(let error):
        print("连接失败：\(error)")
    }
}
```

### 高级配置

#### 自定义传输层配置

```swift
var config = IMTransportConfig(
    type: .tcp,
    url: "tcps://im.example.com:8888",
    connectionTimeout: 30.0,
    heartbeatInterval: 30.0,
    heartbeatTimeout: 10.0,
    autoReconnect: true,
    maxReconnectAttempts: 5,
    reconnectInterval: 5.0
)

// TCP 专用配置
config.tcpConfig = IMTCPConfig(
    enableNagle: false,           // 禁用 Nagle 算法（降低延迟）
    enableKeepAlive: true,
    keepAliveInterval: 60.0,
    receiveBufferSize: 65536,     // 64KB
    sendBufferSize: 65536,
    useTLS: true
)

let transport = IMTransportFactory.createTransport(with: config)
```

#### WebSocket 专用配置

```swift
var config = IMTransportConfig(
    type: .webSocket,
    url: "wss://im.example.com"
)

// WebSocket 专用配置
config.webSocketConfig = IMWebSocketConfig(
    headers: ["User-Agent": "IMSDK/1.0"],
    enableCompression: true,
    maxFrameSize: 1_048_576  // 1MB
)

let transport = IMTransportFactory.createTransport(with: config)
```

---

## 📊 性能对比

### WebSocket vs TCP

| 指标 | WebSocket | TCP (自研协议) | 说明 |
|------|----------|----------------|------|
| **协议开销** | ~30-50 bytes | ~16 bytes | TCP 更省流量 |
| **消息延迟** | 50-100ms | 20-50ms | TCP 更低延迟 |
| **连接建立** | 100-300ms | 50-150ms | TCP 更快 |
| **浏览器支持** | ✅ 原生支持 | ❌ 不支持 | WebSocket 优势 |
| **开发成本** | ✅ 低 | ⚠️ 高 | WebSocket 更简单 |
| **维护成本** | ✅ 低 | ⚠️ 高 | WebSocket 更容易 |
| **适用规模** | 千万级 | 亿级 | TCP 可支持更大规模 |

### 建议

```
用户规模 < 1000 万：WebSocket ✅
    → 开发快、维护简单、性能足够

用户规模 1000 万 - 1 亿：WebSocket + TCP 双协议 ✅
    → WebSocket 为主，TCP 用于弱网优化

用户规模 > 1 亿：TCP 为主 ✅
    → 极致性能，可控性强
```

---

## 🧪 测试

### 单元测试示例

```swift
import XCTest
@testable import IMSDK

class IMPacketCodecTests: XCTestCase {
    
    func testEncodeDecodePacket() {
        let codec = IMPacketCodec()
        
        // 创建测试数据
        let body = "Test Message".data(using: .utf8)!
        let seq: UInt32 = 12345
        
        // 编码
        let encoded = codec.encode(command: .sendMsgReq, sequence: seq, body: body)
        
        // 解码
        let packets = try! codec.decode(data: encoded)
        
        // 验证
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].header.command, .sendMsgReq)
        XCTAssertEqual(packets[0].header.sequence, seq)
        XCTAssertEqual(packets[0].body, body)
    }
    
    func testStickingPackets() {
        let codec = IMPacketCodec()
        
        // 创建多个包
        let packet1 = IMPacket(command: .heartbeatReq, sequence: 1, body: Data([0x01]))
        let packet2 = IMPacket(command: .heartbeatReq, sequence: 2, body: Data([0x02]))
        let packet3 = IMPacket(command: .heartbeatReq, sequence: 3, body: Data([0x03]))
        
        // 模拟粘包
        var stickedData = Data()
        stickedData.append(packet1.encode())
        stickedData.append(packet2.encode())
        stickedData.append(packet3.encode())
        
        // 解码
        let packets = try! codec.decode(data: stickedData)
        
        // 验证
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(packets[0].header.sequence, 1)
        XCTAssertEqual(packets[1].header.sequence, 2)
        XCTAssertEqual(packets[2].header.sequence, 3)
    }
    
    func testFragmentation() {
        let codec = IMPacketCodec()
        
        let packet = IMPacket(command: .sendMsgReq, sequence: 100, body: Data(repeating: 0xFF, count: 1000))
        let fullData = packet.encode()
        
        // 模拟拆包
        let part1 = fullData.prefix(500)
        let part2 = fullData.suffix(from: 500)
        
        // 第一部分（不完整）
        var packets1 = try! codec.decode(data: part1)
        XCTAssertEqual(packets1.count, 0) // 数据不足，无法解析
        
        // 第二部分（补全）
        let packets2 = try! codec.decode(data: part2)
        XCTAssertEqual(packets2.count, 1) // 解析出完整的包
        XCTAssertEqual(packets2[0].header.sequence, 100)
    }
}
```

---

## 🎯 总结

### 已完成的功能

✅ **传输层协议接口**（IMTransportProtocol）
✅ **自定义二进制协议**（IMPacket、IMPacketHeader）
✅ **粘包/拆包处理**（IMPacketCodec）
✅ **TCP Socket 管理**（IMTCPSocketManager）
✅ **TCP 传输层实现**（IMTCPTransport）
✅ **WebSocket 传输层适配**（IMWebSocketTransport）
✅ **传输层工厂**（IMTransportFactory）
✅ **协议切换器**（IMTransportSwitcher）

### 核心优势

1. **统一接口** - 业务层无感知切换
2. **双协议支持** - WebSocket + TCP 自研协议
3. **运行时切换** - 根据网络质量动态切换
4. **极致性能** - TCP 协议开销仅 16 字节
5. **易于扩展** - 未来可添加 QUIC 等新协议

### 下一步工作

- ⏳ 实现 Protobuf 消息序列化（tcp-5）
- ⏳ 集成到 IMClient（tcp-12）
- ⏳ 单元测试和集成测试（tcp-13, tcp-14）
- ⏳ 性能基准测试（tcp-15）

---

**文档版本**: 1.0.0  
**最后更新**: 2025-01-26  
**作者**: IMSDK Team


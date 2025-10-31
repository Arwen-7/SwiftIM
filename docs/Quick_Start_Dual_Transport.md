# 双传输层架构 - 快速开始

## 🚀 5 分钟快速上手

### 场景 1：使用 WebSocket（推荐新手）

```swift
import IMSDK

// 1. 创建 WebSocket 传输层
let transport = IMTransportFactory.createWebSocketTransport(
    url: "wss://im.example.com"
)

// 2. 设置回调
transport.onReceive = { data in
    print("收到消息：\(String(data: data, encoding: .utf8) ?? "")")
}

// 3. 连接
transport.connect(url: "wss://im.example.com", token: "your_token") { result in
    if case .success = result {
        print("✅ WebSocket 连接成功")
        
        // 4. 发送消息
        let message = "Hello, World!".data(using: .utf8)!
        transport.send(data: message, completion: nil)
    }
}
```

### 场景 2：使用 TCP（追求极致性能）

```swift
import IMSDK

// 1. 创建 TCP 传输层
let transport = IMTransportFactory.createTCPTransport(
    url: "tcps://im.example.com:8888"
)

// 2. 创建编解码器
let codec = IMPacketCodec()

// 3. 设置回调
transport.onReceive = { data in
    // TCP 接收的是完整的包体
    print("收到 TCP 数据包：\(data.count) 字节")
}

// 4. 连接
transport.connect(url: "tcps://im.example.com:8888", token: "your_token") { result in
    if case .success = result {
        print("✅ TCP 连接成功")
        
        // 5. 发送消息（需要封装成协议包）
        let seq = IMSequenceGenerator.shared.next()
        let messageBody = "Hello, TCP!".data(using: .utf8)!
        let packet = codec.encode(command: .sendMsgReq, sequence: seq, body: messageBody)
        
        transport.send(data: packet, completion: nil)
    }
}
```

### 场景 3：智能切换（最佳实践）

```swift
import IMSDK

// 1. 创建协议切换器
let switcher = IMTransportSwitcher(
    initialType: .webSocket,
    url: "wss://im.example.com"
)

// 2. 设置回调
switcher.onReceive = { data in
    print("收到消息")
}

switcher.onTransportSwitch = { oldType, newType in
    print("协议切换：\(oldType) → \(newType)")
}

// 3. 连接
switcher.connect(url: "wss://im.example.com", token: "your_token") { result in
    if case .success = result {
        print("✅ 连接成功，当前协议：\(switcher.currentTransportType)")
    }
}

// 4. 监听网络质量，自动切换
class NetworkMonitor {
    func detectNetworkQuality() -> NetworkQuality {
        // 实际项目中，这里应该根据延迟、丢包率等指标判断
        return .poor  // 模拟弱网环境
    }
}

let monitor = NetworkMonitor()
let quality = monitor.detectNetworkQuality()

if quality == .poor || quality == .veryPoor {
    // 弱网环境，切换到 TCP
    switcher.smartSwitch(quality: quality) { result in
        if case .success = result {
            print("✅ 已切换到 TCP（更适合弱网）")
        }
    }
}
```

---

## 📋 完整示例：在 IM SDK 中集成

### Step 1：初始化传输层

```swift
class IMClient {
    // 使用协议切换器
    private var transportSwitcher: IMTransportSwitcher!
    
    func initialize(config: IMConfig) {
        // 创建传输层
        transportSwitcher = IMTransportSwitcher(
            initialType: config.preferredTransport,
            url: config.serverURL
        )
        
        // 设置回调
        setupTransportCallbacks()
    }
    
    private func setupTransportCallbacks() {
        transportSwitcher.onStateChange = { [weak self] state in
            self?.handleStateChange(state)
        }
        
        transportSwitcher.onReceive = { [weak self] data in
            self?.handleReceivedData(data)
        }
        
        transportSwitcher.onError = { [weak self] error in
            self?.handleError(error)
        }
        
        transportSwitcher.onTransportSwitch = { [weak self] oldType, newType in
            print("传输层切换：\(oldType) → \(newType)")
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        // 根据传输层类型处理数据
        switch transportSwitcher.currentTransportType {
        case .webSocket:
            // WebSocket 数据（JSON 或原始数据）
            handleWebSocketData(data)
            
        case .tcp:
            // TCP 数据（协议包体）
            handleTCPData(data)
        }
    }
    
    private func handleWebSocketData(_ data: Data) {
        // 解析 WebSocket 消息（通常是 JSON）
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            processMessage(json)
        }
    }
    
    private func handleTCPData(_ data: Data) {
        // TCP 数据是 Protobuf 序列化的包体
        // TODO: 使用 Protobuf 反序列化
        // let message = try? Im_Protocol_PushMessage(serializedData: data)
        print("收到 TCP 消息：\(data.count) 字节")
    }
    
    func connect(token: String, completion: @escaping (Bool) -> Void) {
        transportSwitcher.connect(
            url: config.serverURL,
            token: token
        ) { result in
            completion(result.isSuccess)
        }
    }
    
    func sendMessage(_ message: IMMessage) {
        let data: Data
        
        switch transportSwitcher.currentTransportType {
        case .webSocket:
            // WebSocket：发送 JSON
            let json = message.toJSON()
            data = try! JSONSerialization.data(withJSONObject: json)
            
        case .tcp:
            // TCP：封装成协议包
            let codec = IMPacketCodec()
            let seq = IMSequenceGenerator.shared.next()
            let body = message.toData()  // Protobuf 序列化
            data = codec.encode(command: .sendMsgReq, sequence: seq, body: body)
        }
        
        transportSwitcher.send(data: data) { result in
            if case .success = result {
                print("消息发送成功")
            }
        }
    }
}
```

### Step 2：配置文件

```swift
struct IMConfig {
    let serverURL: String
    let preferredTransport: IMTransportType
    let enableAutoSwitch: Bool
    
    static let development = IMConfig(
        serverURL: "wss://dev-im.example.com",
        preferredTransport: .webSocket,  // 开发环境用 WebSocket（方便调试）
        enableAutoSwitch: false
    )
    
    static let production = IMConfig(
        serverURL: "tcps://im.example.com:8888",
        preferredTransport: .tcp,  // 生产环境用 TCP（性能更好）
        enableAutoSwitch: true  // 启用智能切换
    )
}
```

### Step 3：智能切换逻辑

```swift
extension IMClient {
    func startNetworkMonitoring() {
        // 使用现有的网络监控器
        IMNetworkMonitor.shared.onQualityChange = { [weak self] quality in
            guard let self = self else { return }
            
            // 根据网络质量智能切换
            self.transportSwitcher.smartSwitch(quality: quality) { result in
                switch result {
                case .success:
                    print("✅ 智能切换成功")
                case .failure(let error):
                    print("❌ 切换失败：\(error)")
                }
            }
        }
    }
}
```

---

## 🎯 最佳实践

### 1. 开发阶段：使用 WebSocket

**优势**：
- ✅ 调试方便（Chrome DevTools、Postman）
- ✅ 快速迭代
- ✅ Web 端同步开发

```swift
#if DEBUG
let config = IMConfig.development  // WebSocket
#else
let config = IMConfig.production   // TCP
#endif
```

### 2. 生产环境：TCP 为主，WebSocket 为辅

**策略**：
```
正常网络：TCP（更高效）
弱网环境：自动切换到 TCP（更可靠）
Web 端：WebSocket（唯一选择）
```

### 3. 灰度发布：逐步切换

**第 1 周**：10% 用户使用 TCP
```swift
let useTCP = (userID.hashValue % 100) < 10
let transport = useTCP ? .tcp : .webSocket
```

**第 2 周**：30% 用户使用 TCP
**第 3 周**：50% 用户使用 TCP
**第 4 周**：100% 用户使用 TCP

### 4. 监控与回滚

```swift
// 监控 TCP 性能指标
func monitorTCPPerformance() {
    let metrics = [
        "connection_time": connectionTime,
        "message_latency": messageLatency,
        "packet_loss": packetLoss,
        "error_rate": errorRate
    ]
    
    // 上报到服务器
    Analytics.track("transport_performance", properties: metrics)
    
    // 如果 TCP 表现不佳，自动回滚到 WebSocket
    if errorRate > 0.05 {  // 错误率 > 5%
        switcher.switchTo(type: .webSocket) { _ in
            print("⚠️ TCP 异常，已回滚到 WebSocket")
        }
    }
}
```

---

## ⚠️ 注意事项

### 1. 协议兼容性

**WebSocket 和 TCP 的消息格式不同**：

- **WebSocket**：通常使用 JSON
- **TCP**：使用自定义二进制协议（Protobuf）

**解决方案**：
```swift
// 业务层统一使用 IMMessage
// 传输层根据协议类型自动转换

func send(message: IMMessage) {
    switch transport.transportType {
    case .webSocket:
        let json = message.toJSON()
        transport.send(data: jsonData)
        
    case .tcp:
        let protobuf = message.toProtobuf()
        let packet = encode(protobuf)
        transport.send(data: packet)
    }
}
```

### 2. 服务器支持

**确保服务器同时支持 WebSocket 和 TCP**：

```
服务器架构：
├─ WebSocket 网关（端口 443）
│   └─ 处理 WebSocket 连接
│
└─ TCP 网关（端口 8888）
    └─ 处理 TCP 连接
```

### 3. 切换时机

**不要频繁切换**：
```swift
// ❌ 错误：每次网络波动都切换
networkMonitor.onQualityChange = { quality in
    switcher.smartSwitch(quality: quality)
}

// ✅ 正确：防抖，持续弱网 30 秒才切换
var weakNetworkStartTime: Date?

networkMonitor.onQualityChange = { quality in
    if quality == .poor || quality == .veryPoor {
        if weakNetworkStartTime == nil {
            weakNetworkStartTime = Date()
        } else if Date().timeIntervalSince(weakNetworkStartTime!) > 30 {
            switcher.smartSwitch(quality: quality)
            weakNetworkStartTime = nil
        }
    } else {
        weakNetworkStartTime = nil
    }
}
```

---

## 📊 性能对比测试

```swift
class TransportPerformanceTest {
    func runBenchmark() {
        // 测试场景：发送 1000 条消息
        let messageCount = 1000
        
        // 测试 WebSocket
        let wsStart = Date()
        testWebSocket(messageCount: messageCount) {
            let wsDuration = Date().timeIntervalSince(wsStart)
            print("WebSocket: \(wsDuration)s, 平均延迟: \(wsDuration/Double(messageCount)*1000)ms")
            
            // 测试 TCP
            let tcpStart = Date()
            self.testTCP(messageCount: messageCount) {
                let tcpDuration = Date().timeIntervalSince(tcpStart)
                print("TCP: \(tcpDuration)s, 平均延迟: \(tcpDuration/Double(messageCount)*1000)ms")
                
                let improvement = (wsDuration - tcpDuration) / wsDuration * 100
                print("性能提升: \(improvement)%")
            }
        }
    }
}
```

**预期结果**：
```
WebSocket: 15.2s, 平均延迟: 15.2ms
TCP: 8.7s, 平均延迟: 8.7ms
性能提升: 42.8%
```

---

## 🎉 总结

**双传输层架构让你：**

1. ✅ **开发阶段**：WebSocket 快速迭代
2. ✅ **生产环境**：TCP 极致性能
3. ✅ **弱网优化**：智能切换
4. ✅ **无缝切换**：业务层无感知
5. ✅ **未来扩展**：可添加 QUIC 等新协议

**下一步**：
- 📖 阅读完整文档：`Transport_Layer_Architecture.md`
- 🧪 运行单元测试：`IMPacketCodecTests`
- 🚀 开始集成到你的 IM SDK

**Have fun! 🎊**


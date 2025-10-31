# Protobuf 序列化实现指南

## 📋 概述

我们已经实现了完整的消息序列化系统，包括：
- ✅ 协议消息定义（基于 `.proto` 规范）
- ✅ 消息编解码器（JSON 序列化）
- ✅ 完整的包编码器（协议 + 包头）
- ✅ 消息路由器（自动路由不同类型的消息）

**当前实现**：使用 **JSON 序列化**（易于调试，兼容性好）  
**未来优化**：可以无缝切换到 **Protobuf 二进制序列化**（性能更好）

---

## 🏗️ 架构层次

```
┌─────────────────────────────────────────────────────────┐
│                     应用层                               │
│    IMClient.sendMessage(message)                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                 IMMessageEncoder                        │
│   encodeMessage(message) → 完整的二进制包               │
└─────────────────────────────────────────────────────────┘
         ↓                                      ↓
┌──────────────────────┐          ┌──────────────────────┐
│  IMProtocolCodec     │          │   IMPacketCodec      │
│  消息 → JSON         │          │   包头 + 包体        │
└──────────────────────┘          └──────────────────────┘
         ↓                                      ↓
┌─────────────────────────────────────────────────────────┐
│           完整的二进制包（16 字节包头 + JSON 包体）      │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 快速开始

### 1. 基础编码

```swift
import IMSDK

// 创建消息编码器
let encoder = IMMessageEncoder()

// 编码认证请求
let authData = try encoder.encodeAuthRequest(
    userID: "user123",
    token: "your_token"
)
// authData 是完整的二进制包，可以直接通过 TCP 发送

// 编码发送消息请求
let message = IMMessage()
message.clientMsgID = UUID().uuidString
message.conversationID = "conv_123"
message.content = "Hello, World!"
message.messageType = .text

let (messageData, sequence) = try encoder.encodeSendMessageRequest(message: message)
// messageData: 完整的二进制包
// sequence: 序列号（用于匹配响应）

// 编码心跳请求
let heartbeatData = try encoder.encodeHeartbeatRequest()
```

### 2. 基础解码

```swift
// 接收到 TCP 数据流
func onReceiveData(_ data: Data) {
    do {
        // 解码数据包（自动处理粘包/拆包）
        let packets = try encoder.decodeData(data)
        
        for (command, sequence, body) in packets {
            handlePacket(command: command, sequence: sequence, body: body)
        }
    } catch {
        print("解码失败：\(error)")
    }
}

func handlePacket(command: IMCommandType, sequence: UInt32, body: Data) {
    switch command {
    case .authRsp:
        let response = try encoder.decodeBody(IMAuthResponse.self, from: body)
        if response.errorCode == 0 {
            print("认证成功，maxSeq: \(response.maxSeq)")
        }
        
    case .sendMsgRsp:
        let response = try encoder.decodeBody(IMSendMessageResponse.self, from: body)
        if response.errorCode == 0 {
            print("消息发送成功，messageID: \(response.messageID)")
        }
        
    case .pushMsg:
        let pushMsg = try encoder.decodeBody(IMPushMessage.self, from: body)
        let imMessage = pushMsg.toIMMessage()
        // 处理收到的新消息
        
    default:
        print("未处理的命令：\(command)")
    }
}
```

---

## 🎯 完整示例：TCP 消息收发

### 发送消息

```swift
class TCPMessageSender {
    let encoder = IMMessageEncoder()
    let transport: IMTCPTransport
    
    func sendMessage(_ message: IMMessage, completion: @escaping (Bool) -> Void) {
        do {
            // 1. 编码消息
            let (data, sequence) = try encoder.encodeSendMessageRequest(message: message)
            
            // 2. 记录待确认的请求
            pendingRequests[sequence] = completion
            
            // 3. 通过 TCP 发送
            transport.send(data: data) { result in
                if case .failure = result {
                    completion(false)
                    self.pendingRequests.removeValue(forKey: sequence)
                }
            }
            
            // 4. 设置超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if let callback = self.pendingRequests.removeValue(forKey: sequence) {
                    callback(false)  // 超时
                }
            }
            
        } catch {
            print("编码失败：\(error)")
            completion(false)
        }
    }
    
    func handleSendMessageResponse(_ response: IMSendMessageResponse, sequence: UInt32) {
        if let callback = pendingRequests.removeValue(forKey: sequence) {
            callback(response.errorCode == 0)
        }
    }
}
```

### 接收消息

```swift
class TCPMessageReceiver {
    let encoder = IMMessageEncoder()
    
    func onReceiveData(_ data: Data) {
        do {
            let packets = try encoder.decodeData(data)
            
            for (command, sequence, body) in packets {
                switch command {
                case .pushMsg:
                    handlePushMessage(body: body)
                    
                case .batchMsg:
                    handleBatchMessages(body: body)
                    
                case .revokeMsgPush:
                    handleRevokeMessage(body: body)
                    
                case .readReceiptPush:
                    handleReadReceipt(body: body)
                    
                default:
                    break
                }
            }
        } catch {
            print("解码失败：\(error)")
        }
    }
    
    private func handlePushMessage(body: Data) {
        do {
            let pushMsg = try encoder.decodeBody(IMPushMessage.self, from: body)
            let message = pushMsg.toIMMessage()
            
            // 保存到数据库
            try database.saveMessage(message)
            
            // 通知业务层
            NotificationCenter.default.post(
                name: .IMNewMessageReceived,
                object: message
            )
            
        } catch {
            print("处理推送消息失败：\(error)")
        }
    }
    
    private func handleBatchMessages(body: Data) {
        do {
            let batchMsg = try encoder.decodeBody(IMBatchMessages.self, from: body)
            
            for pushMsg in batchMsg.messages {
                let message = pushMsg.toIMMessage()
                try database.saveMessage(message)
            }
            
            print("批量保存消息：\(batchMsg.messages.count) 条")
            
        } catch {
            print("处理批量消息失败：\(error)")
        }
    }
}
```

---

## 🎨 使用消息路由器（推荐）

消息路由器提供了更优雅的消息处理方式：

```swift
class IMTCPMessageHandler {
    let router = IMMessageRouter()
    
    func setup() {
        // 注册各种消息处理器
        
        // 认证响应
        router.register(command: .authRsp, type: IMAuthResponse.self) { response, seq in
            self.handleAuthResponse(response)
        }
        
        // 发送消息响应
        router.register(command: .sendMsgRsp, type: IMSendMessageResponse.self) { response, seq in
            self.handleSendMessageResponse(response, sequence: seq)
        }
        
        // 推送消息
        router.register(command: .pushMsg, type: IMPushMessage.self) { pushMsg, seq in
            let message = pushMsg.toIMMessage()
            self.handleNewMessage(message)
        }
        
        // 批量消息
        router.register(command: .batchMsg, type: IMBatchMessages.self) { batchMsg, seq in
            for pushMsg in batchMsg.messages {
                let message = pushMsg.toIMMessage()
                self.handleNewMessage(message)
            }
        }
        
        // 心跳响应
        router.register(command: .heartbeatRsp, type: IMHeartbeatResponse.self) { response, seq in
            print("心跳响应，服务器时间：\(response.serverTime)")
        }
        
        // 撤回消息推送
        router.register(command: .revokeMsgPush, type: IMRevokeMessagePush.self) { push, seq in
            self.handleRevokeMessage(push)
        }
        
        // 已读回执推送
        router.register(command: .readReceiptPush, type: IMReadReceiptPush.self) { push, seq in
            self.handleReadReceipt(push)
        }
        
        // 输入状态推送
        router.register(command: .typingStatusPush, type: IMTypingStatusPush.self) { push, seq in
            self.handleTypingStatus(push)
        }
        
        // 踢出通知
        router.register(command: .kickOut, type: IMKickOutNotification.self) { notification, seq in
            self.handleKickOut(notification)
        }
    }
    
    func onReceiveData(_ data: Data) {
        // 一行代码搞定所有消息路由
        router.route(data: data)
    }
}
```

---

## 📊 性能统计

```swift
let encoder = IMMessageEncoder()

// 编码和解码消息...

// 查看编解码统计
print("协议编解码统计：\(encoder.codecStats)")
// 输出：
// IMProtocolCodec.Stats {
//     totalEncoded: 1523,
//     totalDecoded: 1489,
//     encodeErrors: 2,
//     decodeErrors: 1
// }

// 查看包处理统计
print("包处理统计：\(encoder.packetStats)")
// 输出：
// IMPacketCodec.Stats {
//     totalBytesReceived: 532844,
//     totalPacketsDecoded: 1489,
//     totalPacketsEncoded: 1523,
//     decodeErrors: 1,
//     currentBufferSize: 234
// }

// 重置统计
encoder.resetStats()
```

---

## 🔧 高级用法

### 1. 自定义序列号

```swift
// 手动指定序列号（用于重传等场景）
let customSeq: UInt32 = 12345
let data = try encoder.encodeMessage(
    request,
    command: .sendMsgReq,
    sequence: customSeq
)
```

### 2. 批量编码

```swift
func sendMultipleMessages(_ messages: [IMMessage]) {
    for message in messages {
        do {
            let (data, sequence) = try encoder.encodeSendMessageRequest(message: message)
            transport.send(data: data, completion: nil)
        } catch {
            print("编码失败：\(error)")
        }
    }
}
```

### 3. 清空缓冲区

```swift
// 在连接断开时清空接收缓冲区
encoder.clearBuffer()
```

---

## 🚀 未来优化：切换到 Protobuf 二进制序列化

当前实现使用 JSON 序列化，**未来可以无缝切换到 Protobuf**：

### 步骤 1：编译 proto 文件

```bash
# 运行编译脚本
./Scripts/generate_proto.sh
```

### 步骤 2：修改编解码器

```swift
// 在 IMProtocolCodec.swift 中
public func encode<T: Message>(_ message: T) throws -> Data {
    // JSON 序列化（当前）
    // return try jsonEncoder.encode(message)
    
    // Protobuf 序列化（未来）
    return try message.serializedData()
}

public func decode<T: Message>(_ type: T.Type, from data: Data) throws -> T {
    // JSON 反序列化（当前）
    // return try jsonDecoder.decode(type, from: data)
    
    // Protobuf 反序列化（未来）
    return try T(serializedData: data)
}
```

**性能提升预期**：
- 序列化速度：提升 2-3 倍
- 反序列化速度：提升 2-3 倍
- 数据大小：减少 30-50%

---

## 📋 总结

✅ **已实现**：
- 协议消息定义（11 种消息类型）
- 消息编解码器（JSON 序列化）
- 完整的包编码器（协议 + 包头）
- 消息路由器（自动路由）
- 便捷的编码/解码方法
- 统计信息收集

✅ **优势**：
- 统一的编解码接口
- 自动处理粘包/拆包
- 类型安全（编译时检查）
- 易于调试（JSON 可读）
- 易于扩展（添加新消息类型）

⏳ **未来优化**：
- 切换到 Protobuf 二进制序列化（更快、更小）
- 消息压缩（GZIP/Brotli）
- 消息加密（AES）

---

**文档版本**: 1.0.0  
**最后更新**: 2025-01-26  
**作者**: IMSDK Team


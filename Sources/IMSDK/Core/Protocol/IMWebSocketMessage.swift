/// IMWebSocketMessage - WebSocket 专用消息格式
/// 
/// ⚠️ 注意：此文件已不再被使用，仅作为学习参考保留
/// 
/// 当前项目已完全迁移到 Protobuf (Im_Protocol_WebSocketMessage)
/// 此文件展示了在使用 Protobuf 之前的手动实现方式
/// 
/// 学习要点：
/// 1. 如何设计轻量级的二进制协议
/// 2. 如何使用 Data 进行手动编解码
/// 3. 字节序处理（大端序 vs 小端序）
/// 4. 如何设计协议的可扩展性
/// 5. 错误处理和验证
///
/// 对比 Protobuf 的优缺点：
/// ✅ 手动实现优点：
///   - 完全可控，格式简单
///   - 无需额外工具
///   - 学习底层协议设计
/// ❌ 手动实现缺点：
///   - 容易出错
///   - 维护成本高
///   - 性能不如 Protobuf
///   - 缺乏跨语言支持
///
/// 这就是为什么我们最终选择了 Protobuf

import Foundation

/// WebSocket 消息封装格式（手动实现版本）
/// 
/// 协议格式（自定义二进制）：
/// ```
/// +--------+--------+--------+--------+--------+
/// | Magic  | Ver    | Cmd    | Seq    | Body   |
/// | 2 byte | 1 byte | 2 byte | 4 byte | N byte |
/// +--------+--------+--------+--------+--------+
/// ```
/// 
/// - Magic: 0xEF89 魔数（用于验证）
/// - Ver: 协议版本
/// - Cmd: 命令类型（映射到 IMCommandType）
/// - Seq: 序列号（用于请求-响应匹配）
/// - Body: 消息体（Protobuf 或 JSON）
public struct IMWebSocketMessage {
    
    // MARK: - Constants
    
    /// 协议魔数（用于识别有效消息）
    private static let kMagicNumber: UInt16 = 0xEF89
    
    /// 协议版本
    private static let kProtocolVersion: UInt8 = 1
    
    /// 头部固定长度（魔数 2 + 版本 1 + 命令 2 + 序列号 4 = 9 字节）
    internal static let kHeaderSize = 9
    
    // MARK: - Properties
    
    public let command: IMCommandType
    public let sequence: UInt32
    public let body: Data
    public let timestamp: Int64
    
    // MARK: - Initialization
    
    public init(command: IMCommandType, sequence: UInt32, body: Data, timestamp: Int64) {
        self.command = command
        self.sequence = sequence
        self.body = body
        self.timestamp = timestamp
    }
    
    // MARK: - Encoding (Swift → Data)
    
    /// 编码为二进制数据
    /// 
    /// 学习要点：
    /// 1. 使用 withUnsafeBytes 进行高效的内存操作
    /// 2. 大端序（Big Endian）网络字节序
    /// 3. Data 的拼接方式
    public func encode() throws -> Data {
        var data = Data()
        
        // 1. 魔数（2 字节，大端序）
        var magic = Self.kMagicNumber.bigEndian
        data.append(Data(bytes: &magic, count: 2))
        
        // 2. 版本（1 字节）
        var version = Self.kProtocolVersion
        data.append(Data(bytes: &version, count: 1))
        
        // 3. 命令类型（2 字节，大端序）
        var cmd = UInt16(command.rawValue).bigEndian
        data.append(Data(bytes: &cmd, count: 2))
        
        // 4. 序列号（4 字节，大端序）
        var seq = sequence.bigEndian
        data.append(Data(bytes: &seq, count: 4))
        
        // 5. 消息体
        data.append(body)
        
        return data
    }
    
    // MARK: - Decoding (Data → Swift)
    
    /// 从二进制数据解码
    /// 
    /// 学习要点：
    /// 1. 数据验证（长度检查、魔数验证）
    /// 2. 使用 advanced(by:) 进行指针偏移
    /// 3. withUnsafeBytes 读取固定大小的数据
    /// 4. 错误处理的层次
    public static func decode(_ data: Data) throws -> IMWebSocketMessage {
        // 1. 验证最小长度
        guard data.count >= kHeaderSize else {
            throw IMWebSocketMessageError.invalidDataLength(data.count)
        }
        
        var offset = 0
        
        // 2. 读取并验证魔数
        let magic = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt16 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian
        }
        offset += 2
        
        guard magic == kMagicNumber else {
            throw IMWebSocketMessageError.invalidMagicNumber(magic)
        }
        
        // 3. 读取并验证版本
        let version = data[offset]
        offset += 1
        
        guard version == kProtocolVersion else {
            throw IMWebSocketMessageError.unsupportedVersion(version)
        }
        
        // 4. 读取命令类型
        let commandRaw = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt16 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian
        }
        offset += 2
        
        guard let command = IMCommandType(rawValue: UInt16(commandRaw)) else {
            throw IMWebSocketMessageError.invalidCommand(commandRaw)
        }
        
        // 5. 读取序列号
        let sequence = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt32 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
        }
        offset += 4
        
        // 6. 读取消息体
        let body = data.advanced(by: offset)
        
        // 7. 时间戳（当前时间）
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        return IMWebSocketMessage(
            command: command,
            sequence: sequence,
            body: body,
            timestamp: timestamp
        )
    }
}

// MARK: - Error Types

/// WebSocket 消息错误
/// 
/// 学习要点：
/// 1. 如何设计清晰的错误类型
/// 2. 使用关联值携带错误上下文
/// 3. LocalizedError 协议提供用户友好的错误消息
public enum IMWebSocketMessageError: Error, LocalizedError {
    case invalidDataLength(Int)
    case invalidMagicNumber(UInt16)
    case unsupportedVersion(UInt8)
    case invalidCommand(UInt16)
    case bodyLengthMismatch(expected: Int, actual: Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataLength(let length):
            return "Invalid data length: \(length) bytes, expected at least \(IMWebSocketMessage.kHeaderSize) bytes"
        case .invalidMagicNumber(let magic):
            return "Invalid magic number: 0x\(String(magic, radix: 16)), expected 0xEF89"
        case .unsupportedVersion(let version):
            return "Unsupported protocol version: \(version), expected 1"
        case .invalidCommand(let cmd):
            return "Invalid command type: \(cmd)"
        case .bodyLengthMismatch(let expected, let actual):
            return "Body length mismatch: expected \(expected) bytes, got \(actual) bytes"
        }
    }
}

// MARK: - Learning Examples

/// 使用示例（仅供学习参考）
/// 
/// ```swift
/// // 编码示例
/// let message = IMWebSocketMessage(
///     command: .cmdPushMsg,
///     sequence: 12345,
///     body: myProtobufData,
///     timestamp: Int64(Date().timeIntervalSince1970 * 1000)
/// )
/// let encodedData = try message.encode()
/// // 发送 encodedData 到 WebSocket
/// 
/// // 解码示例
/// // 从 WebSocket 接收到 data
/// let decodedMessage = try IMWebSocketMessage.decode(data)
/// print("Command: \(decodedMessage.command)")
/// print("Sequence: \(decodedMessage.sequence)")
/// // 解析 decodedMessage.body（可能是 Protobuf）
/// ```

// MARK: - Design Notes

/*
 设计笔记（学习参考）：
 
 1. 为什么需要魔数（Magic Number）？
    - 快速验证数据的有效性
    - 避免解析非法数据导致崩溃
    - 协议识别（区分不同协议）
 
 2. 为什么使用大端序（Big Endian）？
    - 网络字节序标准
    - 跨平台兼容性
    - 便于调试（与抓包工具一致）
 
 3. 为什么需要版本号？
    - 协议升级和兼容性
    - 客户端和服务器可以协商版本
    - 便于灰度发布
 
 4. 为什么需要序列号？
    - 请求-响应匹配
    - 消息去重
    - 消息排序
    - 超时检测
 
 5. 为什么最终选择 Protobuf？
    - 更好的性能（编解码速度快）
    - 更小的数据量（压缩率高）
    - 自动生成代码（减少错误）
    - 跨语言支持（服务端可能用其他语言）
    - 向前/向后兼容性（字段可选）
    - 工具生态完善（protoc、验证、文档）
 
 6. 手动实现 vs Protobuf 对比：
 
    手动实现：
    ✅ 学习价值高（理解底层原理）
    ✅ 完全可控
    ✅ 格式简单直观
    ❌ 容易出错（字节对齐、字节序）
    ❌ 维护成本高
    ❌ 性能不如 Protobuf
    ❌ 缺乏跨语言支持
 
    Protobuf：
    ✅ 高性能
    ✅ 跨语言
    ✅ 自动生成
    ✅ 向前/向后兼容
    ✅ 成熟稳定
    ❌ 需要额外工具
    ❌ 学习曲线
    ❌ 调试相对困难（二进制格式）
 
 7. 实际生产环境建议：
    - 使用 Protobuf（或类似的成熟方案）
    - 手动实现仅适合学习或特殊场景
    - 考虑使用 MessagePack、FlatBuffers 等替代方案
 
 8. 延伸阅读：
    - Protocol Buffers 官方文档
    - 网络字节序（Network Byte Order）
    - TLV（Type-Length-Value）编码
    - Varint 变长整数编码
    - ZigZag 编码（有符号整数）
*/


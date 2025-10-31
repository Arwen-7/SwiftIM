//
//  IMPacket.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - 协议包定义

/// 协议魔数（用于识别合法的包）
public let kProtocolMagic: UInt16 = 0xEF89

/// 当前协议版本
public let kProtocolVersion: UInt8 = 1

/// 包头长度（16 字节）
public let kPacketHeaderSize: Int = 16

/// 命令类型（与 proto 文件中的 CommandType 对应）
public enum IMCommandType: UInt16 {
    // 连接相关（1-99）
    case connectReq = 1
    case connectRsp = 2
    case disconnectReq = 3
    case disconnectRsp = 4
    case heartbeatReq = 5
    case heartbeatRsp = 6
    
    // 认证相关（100-199）
    case authReq = 100
    case authRsp = 101
    case reauthReq = 102
    case reauthRsp = 103
    case kickOut = 104
    
    // 消息相关（200-299）
    case sendMsgReq = 200
    case sendMsgRsp = 201
    case pushMsg = 202
    case msgAck = 203
    case batchMsg = 204
    case revokeMsgReq = 205
    case revokeMsgRsp = 206
    case revokeMsgPush = 207
    
    // 同步相关（300-399）
    case syncReq = 300
    case syncRsp = 301
    case syncFinished = 302
    
    // 在线状态（400-499）
    case onlineStatusReq = 400
    case onlineStatusRsp = 401
    case statusChangePush = 402
    
    // 已读回执（500-599）
    case readReceiptReq = 500
    case readReceiptRsp = 501
    case readReceiptPush = 502
    
    // 输入状态（600-699）
    case typingStatusReq = 600
    case typingStatusPush = 601
}

// MARK: - 包头

/// 协议包头（16 字节）
///
/// 内存布局：
/// ```
/// +--------+--------+--------+--------+--------+--------+--------+--------+
/// | Magic  | Ver    | Flags  | CmdID  | Seq    | BodyLen| CRC16  |
/// | 2 byte | 1 byte | 1 byte | 2 byte | 4 byte | 4 byte | 2 byte |
/// +--------+--------+--------+--------+--------+--------+--------+--------+
/// ```
public struct IMPacketHeader {
    /// 魔数（0xEF89，用于识别合法的包）
    public let magic: UInt16
    
    /// 协议版本（当前为1）
    public let version: UInt8
    
    /// 标志位（预留，用于扩展功能：加密、压缩等）
    public let flags: UInt8
    
    /// 命令类型
    public let command: IMCommandType
    
    /// 序列号（用于请求-响应匹配、去重、排序、丢包检测）
    public let sequence: UInt32
    
    /// 包体长度
    public let bodyLength: UInt32
    
    /// CRC16 校验值（校验包头前14字节，确保包头完整性）
    public let crc16: UInt16
    
    /// 初始化包头
    public init(
        command: IMCommandType,
        sequence: UInt32,
        bodyLength: UInt32,
        flags: UInt8 = 0
    ) {
        self.magic = kProtocolMagic
        self.version = kProtocolVersion
        self.flags = flags
        self.command = command
        self.sequence = sequence
        self.bodyLength = bodyLength
        
        // 计算 CRC16（校验前14字节）
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: kProtocolMagic.bigEndian) { Data($0) })
        data.append(kProtocolVersion)
        data.append(flags)
        data.append(contentsOf: withUnsafeBytes(of: command.rawValue.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: bodyLength.bigEndian) { Data($0) })
        
        self.crc16 = IMCRC16.calculate(data)
    }
    
    /// 验证包头合法性（魔数、版本、CRC）
    public var isValid: Bool {
        // 1. 检查魔数
        guard magic == kProtocolMagic else {
            return false
        }
        
        // 2. 检查版本
        guard version == kProtocolVersion else {
            return false
        }
        
        // 3. 验证 CRC
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian) { Data($0) })
        data.append(version)
        data.append(flags)
        data.append(contentsOf: withUnsafeBytes(of: command.rawValue.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: bodyLength.bigEndian) { Data($0) })
        
        let calculatedCRC = IMCRC16.calculate(data)
        return calculatedCRC == crc16
    }
    
    /// 序列化为二进制数据（Big-Endian）
    public func encode() -> Data {
        var data = Data(capacity: kPacketHeaderSize)
        
        // Magic（2 bytes）
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian) { Array($0) })
        
        // Version（1 byte）
        data.append(version)
        
        // Flags（1 byte）
        data.append(flags)
        
        // Command（2 bytes）
        data.append(contentsOf: withUnsafeBytes(of: command.rawValue.bigEndian) { Array($0) })
        
        // Sequence（4 bytes）
        data.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Array($0) })
        
        // BodyLength（4 bytes）
        data.append(contentsOf: withUnsafeBytes(of: bodyLength.bigEndian) { Array($0) })
        
        // CRC16（2 bytes）
        data.append(contentsOf: withUnsafeBytes(of: crc16.bigEndian) { Array($0) })
        
        return data
    }
    
    /// 从二进制数据反序列化
    public static func decode(from data: Data) -> IMPacketHeader? {
        guard data.count >= kPacketHeaderSize else {
            return nil
        }
        
        var offset = 0
        
        // Magic（2 bytes）
        let magic = data.withUnsafeBytes { ptr in
            UInt16(bigEndian: ptr.load(fromByteOffset: offset, as: UInt16.self))
        }
        guard magic == kProtocolMagic else {
            return nil  // 魔数不匹配
        }
        offset += 2
        
        // Version（1 byte）
        let version = data[offset]
        guard version == kProtocolVersion else {
            return nil  // 版本不匹配
        }
        offset += 1
        
        // Flags（1 byte）
        let flags = data[offset]
        offset += 1
        
        // Command（2 bytes）
        let commandRaw = data.withUnsafeBytes { ptr in
            UInt16(bigEndian: ptr.load(fromByteOffset: offset, as: UInt16.self))
        }
        offset += 2
        
        guard let command = IMCommandType(rawValue: commandRaw) else {
            return nil
        }
        
        // Sequence（4 bytes）
        let sequence = data.withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.load(fromByteOffset: offset, as: UInt32.self))
        }
        offset += 4
        
        // BodyLength（4 bytes）
        let bodyLength = data.withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.load(fromByteOffset: offset, as: UInt32.self))
        }
        offset += 4
        
        // CRC16（2 bytes）
        let crc16 = data.withUnsafeBytes { ptr in
            UInt16(bigEndian: ptr.load(fromByteOffset: offset, as: UInt16.self))
        }
        
        // 创建包头（会自动计算 CRC）
        let header = IMPacketHeader(
            command: command,
            sequence: sequence,
            bodyLength: bodyLength,
            flags: flags
        )
        
        // 验证 CRC
        guard header.crc16 == crc16 else {
            return nil  // CRC 校验失败
        }
        
        return header
    }
}

// MARK: - 完整的协议包

/// 完整的协议包（包头 + 包体）
public struct IMPacket {
    /// 包头
    public let header: IMPacketHeader
    
    /// 包体（Protobuf 序列化的数据）
    public let body: Data
    
    public init(command: IMCommandType, sequence: UInt32, body: Data) {
        self.header = IMPacketHeader(
            command: command,
            sequence: sequence,
            bodyLength: UInt32(body.count)
        )
        self.body = body
    }
    
    public init(header: IMPacketHeader, body: Data) {
        self.header = header
        self.body = body
    }
    
    /// 完整包的长度
    public var totalLength: Int {
        return kPacketHeaderSize + body.count
    }
    
    /// 序列化为完整的二进制数据
    public func encode() -> Data {
        var data = Data(capacity: totalLength)
        data.append(header.encode())
        data.append(body)
        return data
    }
    
    /// 从二进制数据反序列化
    /// - Parameter data: 完整的包数据（包头 + 包体）
    /// - Returns: 解析出的包，如果数据不完整或格式错误则返回 nil
    public static func decode(from data: Data) -> IMPacket? {
        guard data.count >= kPacketHeaderSize else {
            return nil
        }
        
        // 1. 解析包头
        let headerData = data.prefix(kPacketHeaderSize)
        guard let header = IMPacketHeader.decode(from: headerData) else {
            return nil
        }
        
        // 2. 验证包体长度
        let expectedLength = kPacketHeaderSize + Int(header.bodyLength)
        guard data.count >= expectedLength else {
            return nil
        }
        
        // 3. 提取包体
        let body = data.subdata(in: kPacketHeaderSize..<expectedLength)
        
        return IMPacket(header: header, body: body)
    }
}

// MARK: - 序列号生成器

/// 序列号生成器（线程安全）
public final class IMSequenceGenerator {
    private var currentSeq: UInt32 = 0
    private let lock = NSLock()
    
    public static let shared = IMSequenceGenerator()
    
    public init() {}
    
    /// 生成下一个序列号
    public func next() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        
        if currentSeq == UInt32.max {
            currentSeq = 1  // 溢出后从 1 开始（0 保留）
        } else {
            currentSeq += 1
        }
        
        return currentSeq
    }
    
    /// 重置序列号（通常在重连后调用）
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        currentSeq = 0
    }
}

// MARK: - CustomStringConvertible

extension IMPacketHeader: CustomStringConvertible {
    public var description: String {
        return """
        IMPacketHeader {
            magic: 0x\(String(format: "%04X", magic)),
            version: \(version),
            command: \(command) (\(command.rawValue)),
            sequence: \(sequence),
            bodyLength: \(bodyLength),
            reserved: (\(reserved.0), \(reserved.1), \(reserved.2))
        }
        """
    }
}

extension IMPacket: CustomStringConvertible {
    public var description: String {
        return """
        IMPacket {
            header: \(header),
            bodySize: \(body.count) bytes
        }
        """
    }
}


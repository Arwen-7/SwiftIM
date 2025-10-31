//
//  IMMessageEncoder.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - TCP 数据包解码器

/// TCP 数据包解码器（处理粘包/拆包）
///
/// **职责：**
/// - 解码 TCP 字节流，处理粘包和拆包
/// - 提取包头信息（command, sequence）和包体（Protobuf body）
///
/// **工作流程：**
/// ```
/// TCP 字节流 → IMPacketCodec 解码 → [(command, sequence, body)]
///     ↓
/// body (Protobuf 数据) → 上层使用 SwiftProtobuf 解析
/// ```
///
/// **注意：**
/// - 本类只负责 TCP 层面的数据包解码（粘包/拆包）
/// - 消息体的 Protobuf 解析由 `IMMessageRouter` 负责
public final class IMMessageEncoder {
    
    // MARK: - Components
    
    /// 包编解码器（处理粘包/拆包）
    private let packetCodec: IMPacketCodec
    
    // MARK: - Initialization
    
    public init() {
        self.packetCodec = IMPacketCodec()
    }
    
    // MARK: - TCP Packet Decoding
    
    /// 解码 TCP 数据流（处理粘包/拆包）
    /// - Parameter data: 原始 TCP 字节流
    /// - Returns: 解码出的数据包数组 [(command, sequence, body)]
    /// - Throws: 解码错误
    public func decodeData(_ data: Data) throws -> [(command: IMCommandType, sequence: UInt32, body: Data)] {
        // 1. 解析 TCP 数据包（处理粘包/拆包）
        let packets = try packetCodec.decode(data: data)
        
        // 2. 提取包头信息和包体
        var results: [(command: IMCommandType, sequence: UInt32, body: Data)] = []
        for packet in packets {
            results.append((
                command: packet.header.command,
                sequence: packet.header.sequence,
                body: packet.body
            ))
        }
        
        return results
    }
    
    // MARK: - Statistics
    
    /// 获取包处理统计信息
    public var packetStats: IMPacketCodec.Stats {
        return packetCodec.stats
    }
    
    /// 重置统计信息
    public func resetStats() {
        packetCodec.resetStats()
    }
    
    /// 清空接收缓冲区
    public func clearBuffer() {
        packetCodec.clearBuffer()
    }
}


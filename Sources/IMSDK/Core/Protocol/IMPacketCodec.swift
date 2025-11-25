//
//  IMPacketCodec.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//

import Foundation

// MARK: - 错误定义

/// 粘包/拆包处理器错误
public enum IMPacketCodecError: Error, LocalizedError {
    case bufferOverflow(Int)           // 缓冲区溢出
    case invalidPacketHeader           // 包头格式错误
    case packetTooLarge(Int)           // 包体过大
    case crcCheckFailed                // CRC 校验失败
    case sequenceAbnormal(UInt32, UInt32)  // 序列号异常（expected, received）
    
    public var errorDescription: String? {
        switch self {
        case .bufferOverflow(let size):
            return "Buffer overflow: \(size) bytes"
        case .invalidPacketHeader:
            return "Invalid packet header (magic or version mismatch)"
        case .packetTooLarge(let size):
            return "Packet too large: \(size) bytes"
        case .crcCheckFailed:
            return "CRC check failed"
        case .sequenceAbnormal(let expected, let received):
            return "Sequence abnormal: expected=\(expected), received=\(received)"
        }
    }
}

// MARK: - 配置

/// 粘包/拆包处理器配置
public struct IMPacketCodecConfig {
    /// 最大缓冲区大小（默认 2MB）
    public var maxBufferSize: Int = 2 * 1024 * 1024
    
    /// 最大包大小（默认 1MB）
    public var maxPacketSize: UInt32 = 1 * 1024 * 1024
    
    /// 是否启用序列号连续性检查
    public var enableSequenceCheck: Bool = true
    
    /// 最大容忍的序列号跳跃（用于检测异常，默认100）
    public var maxSequenceGap: UInt32 = 100
    
    public init() {}
}

// MARK: - 统计信息

extension IMPacketCodec {
    /// 统计信息
    public struct Stats {
        /// 总接收字节数
        public var totalBytesReceived: Int64 = 0
        
        /// 总发送字节数
        public var totalBytesSent: Int64 = 0
        
        /// 总解码包数
        public var totalPacketsDecoded: Int = 0
        
        /// 总编码包数
        public var totalPacketsEncoded: Int = 0
        
        /// 解码错误次数
        public var decodeErrors: Int = 0
        
        /// 编码错误次数
        public var encodeErrors: Int = 0
        
        /// 当前缓冲区大小
        public var currentBufferSize: Int = 0
        
        /// 检测到的丢包次数
        public var packetLossCount: Int = 0
        
        /// CRC 校验失败次数
        public var crcFailureCount: Int = 0
        
        /// 魔数错误次数
        public var magicErrorCount: Int = 0
        
        /// 版本错误次数
        public var versionErrorCount: Int = 0
        
        /// 序列号异常次数
        public var sequenceAbnormalCount: Int = 0
    }
}

// MARK: - 粘包/拆包处理器

/// 粘包/拆包处理器
///
/// 负责处理 TCP 流式数据的粘包和拆包问题：
/// - **粘包**：多个包连在一起接收
/// - **拆包**：一个包分多次接收
///
/// ## 核心功能
/// 1. CRC16 校验（确保包头完整性）
/// 2. 序列号连续性检查（检测丢包）
/// 3. 快速失败策略（不做扫描恢复）
/// 4. 完善的统计和监控
public class IMPacketCodec {
    
    // MARK: - Properties
    
    /// 配置
    public let config: IMPacketCodecConfig
    
    /// 接收缓冲区
    private var receiveBuffer = Data()
    
    /// 统计信息
    public private(set) var stats = Stats()
    
    /// 上一个成功解析的包的序列号
    private var lastValidSequence: UInt32 = 0
    
    /// 线程安全锁
    private let lock = NSLock()
    private let sequenceLock = NSLock()
    
    // MARK: - Callbacks
    
    /// 检测到丢包的回调（expected, received, gap）
    public var onPacketLoss: ((_ expected: UInt32, _ received: UInt32, _ gap: UInt32) -> Void)?
    
    /// 发生严重错误的回调（需要重连）
    public var onFatalError: ((_ error: IMPacketCodecError) -> Void)?
    
    // MARK: - Initialization
    
    public init(config: IMPacketCodecConfig = IMPacketCodecConfig()) {
        self.config = config
    }
    
    // MARK: - Public Methods
    
    /// 编码协议包
    /// - Parameters:
    ///   - command: 命令类型
    ///   - sequence: 序列号
    ///   - body: 包体数据
    /// - Returns: 编码后的完整数据包
    public func encode(command: IMCommandType, sequence: UInt32, body: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        // 创建包头
        let header = IMPacketHeader(
            command: command,
            sequence: sequence,
            bodyLength: UInt32(body.count)
        )
        
        // 编码包头 + 包体
        var data = header.encode()
        data.append(body)
        
        // 更新统计
        stats.totalBytesSent += Int64(data.count)
        stats.totalPacketsEncoded += 1
        
        return data
    }
    
    /// 编码完整的协议包
    /// - Parameter packet: 协议包
    /// - Returns: 编码后的数据
    public func encode(packet: IMPacket) -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        let data = packet.encode()
        
        // 更新统计
        stats.totalBytesSent += Int64(data.count)
        stats.totalPacketsEncoded += 1
        
        return data
    }
    
    /// 解码协议包（处理粘包/拆包）
    /// - Parameter data: 接收到的原始数据
    /// - Returns: 解析出的完整协议包数组
    /// - Throws: 解码错误
    public func decode(data: Data) throws -> [IMPacket] {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. 追加到接收缓冲区
        receiveBuffer.append(data)
        stats.totalBytesReceived += Int64(data.count)
        stats.currentBufferSize = receiveBuffer.count
        
        // 2. 检查缓冲区是否溢出（快速失败策略）
        if receiveBuffer.count > config.maxBufferSize {
            // 缓冲区溢出，清空并抛出异常
            IMLogger.shared.error("Buffer overflow: \(receiveBuffer.count) bytes, clearing buffer")
            receiveBuffer.removeAll()
            stats.decodeErrors += 1
            onFatalError?(.bufferOverflow(receiveBuffer.count))
            throw IMPacketCodecError.bufferOverflow(receiveBuffer.count)
        }
        
        // 3. 尝试解析出所有完整的包
        var packets: [IMPacket] = []
        
        while true {
            // 3.1 检查是否有足够的数据读取包头
            guard receiveBuffer.count >= kPacketHeaderSize else {
                // 数据不足，等待更多数据
                break
            }
            
            // 3.2 解析包头（包含魔数、版本、CRC 校验）
            let headerData = receiveBuffer.prefix(kPacketHeaderSize)
            
            // 额外的安全检查：确保 headerData 确实有 16 字节
            guard headerData.count == kPacketHeaderSize else {
                IMLogger.shared.error("Header data size mismatch: \(headerData.count) != \(kPacketHeaderSize)")
                stats.decodeErrors += 1
                onFatalError?(.invalidPacketHeader)
                throw IMPacketCodecError.invalidPacketHeader
            }
            
            guard let header = IMPacketHeader.decode(from: headerData) else {
                // 包头解析失败（魔数不匹配、版本不对、CRC 校验失败）
                handleHeaderDecodeFailure(headerData)
                throw IMPacketCodecError.invalidPacketHeader
            }
            
            // 3.3 检查包体长度是否合法（快速失败策略）
            if header.bodyLength > config.maxPacketSize {
                // 包体过大，清空缓冲区并抛出异常
                IMLogger.shared.error("Packet too large: \(header.bodyLength) bytes, clearing buffer")
                receiveBuffer.removeAll()
                stats.decodeErrors += 1
                onFatalError?(.packetTooLarge(Int(header.bodyLength)))
                throw IMPacketCodecError.packetTooLarge(Int(header.bodyLength))
            }
            
            // 3.4 检查是否有足够的数据读取完整的包
            let totalPacketSize = kPacketHeaderSize + Int(header.bodyLength)
            guard receiveBuffer.count >= totalPacketSize else {
                // 数据不足，等待更多数据（拆包情况）
                break
            }
            
            // 3.5 提取完整的包
            receiveBuffer.removeFirst(kPacketHeaderSize)  // 移除包头
            let body = receiveBuffer.prefix(Int(header.bodyLength))
            receiveBuffer.removeFirst(Int(header.bodyLength))  // 移除包体
            
            // 3.6 创建协议包
            let packet = IMPacket(header: header, body: Data(body))
            
            // 3.7 序列号连续性检查（检测丢包）
            if config.enableSequenceCheck && lastValidSequence > 0 {
                checkSequenceContinuity(packet: packet)
            }
            
            packets.append(packet)
            stats.totalPacketsDecoded += 1
            stats.currentBufferSize = receiveBuffer.count
            
            // 更新最后有效序列号
            sequenceLock.lock()
            lastValidSequence = header.sequence
            sequenceLock.unlock()
        }
        
        return packets
    }
    
    // MARK: - Private Methods
    
    /// 处理包头解码失败
    private func handleHeaderDecodeFailure(_ headerData: Data) {
        // 分析失败原因
        var isMagicError = false
        var isVersionError = false
        
        // 1. 检查魔数
        if headerData.count >= 2 {
            let magic = headerData.withUnsafeBytes { ptr in
                UInt16(bigEndian: ptr.load(fromByteOffset: 0, as: UInt16.self))
            }
            if magic != kProtocolMagic {
                IMLogger.shared.error("Magic number mismatch: expected=0x\(String(format: "%04X", kProtocolMagic)), actual=0x\(String(format: "%04X", magic))")
                stats.magicErrorCount += 1
                isMagicError = true
            }
        }
        
        // 2. 检查版本
        if headerData.count >= 3 {
            let version = headerData[2]
            if version != kProtocolVersion {
                IMLogger.shared.error("Version mismatch: expected=\(kProtocolVersion), actual=\(version)")
                stats.versionErrorCount += 1
                isVersionError = true
            }
        }
        
        // 3. 如果数据完整（16字节）且魔数、版本都正确，那就是 CRC 错误
        if headerData.count == kPacketHeaderSize && !isMagicError && !isVersionError {
            IMLogger.shared.error("CRC check failed (magic and version are correct)")
            stats.crcFailureCount += 1
        }
        
        // 快速失败：清空缓冲区
        receiveBuffer.removeAll()
        stats.decodeErrors += 1
    }
    
    /// 检查序列号连续性（检测丢包）
    private func checkSequenceContinuity(packet: IMPacket) {
        sequenceLock.lock()
        let expected = lastValidSequence + 1
        let received = packet.header.sequence
        sequenceLock.unlock()
        
        // 处理序列号回绕（从 UInt32::MAX 回到 0）
        if received == 0 && lastValidSequence > (UInt32.max - 1000) {
            // 序列号回绕，正常情况
            IMLogger.shared.debug("Sequence wrapped around: \(lastValidSequence) -> \(received)")
            return
        }
        
        // 计算间隔
        let gap = received > expected ? received - expected : 0
        
        if gap > 0 && gap < config.maxSequenceGap {
            // 检测到丢包
            IMLogger.shared.warning("📉 Packet loss detected: expected=\(expected), received=\(received), gap=\(gap)")
            
            // 更新统计
            stats.packetLossCount += Int(gap)
            
            // 通知上层（触发重传机制）
            onPacketLoss?(expected, received, gap)
            
        } else if gap >= config.maxSequenceGap {
            // 序列号异常跳跃（可能是攻击或严重错误）
            IMLogger.shared.error("⚠️ Abnormal sequence jump: expected=\(expected), received=\(received), gap=\(gap)")
            stats.sequenceAbnormalCount += 1
            
            // 通知上层（可能需要重连）
            onFatalError?(.sequenceAbnormal(expected, received))
        }
    }
    
    // MARK: - Buffer Management
    
    /// 清空缓冲区
    public func clearBuffer() {
        lock.lock()
        defer { lock.unlock() }
        
        receiveBuffer.removeAll()
        stats.currentBufferSize = 0
        IMLogger.shared.info("Packet codec buffer cleared")
    }
    
    /// 获取缓冲区快照（用于调试）
    public func bufferSnapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return receiveBuffer
    }
    
    /// 重置序列号（重连后调用）
    public func resetSequence() {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        lastValidSequence = 0
        IMLogger.shared.info("Packet codec sequence reset")
    }
    
    /// 重置统计信息
    public func resetStats() {
        lock.lock()
        defer { lock.unlock() }
        stats = Stats()
        IMLogger.shared.info("Packet codec stats reset")
    }
    
    /// 重置所有状态（重连后调用）
    public func reset() {
        clearBuffer()
        resetSequence()
        resetStats()
    }
}

//
//  IMTransportProtocol.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - 传输层协议（统一 WebSocket 和 TCP 的抽象）

/// 传输层状态
public enum IMTransportState {
    case disconnected       // 未连接
    case connecting         // 连接中
    case connected          // 已连接
    case reconnecting       // 重连中
    case disconnecting      // 断开中
}

/// 传输层错误
public enum IMTransportError: Error {
    case notConnected
    case connectionFailed(Error)
    case sendFailed(Error)
    case receiveFailed(Error)
    case protocolError(String)
    case timeout
    
    /// 检测到丢包（序列号跳跃）
    case packetLoss(expected: UInt32, received: UInt32, gap: UInt32)
    
    /// 达到最大重连次数
    case maxReconnectAttemptsReached
}

/// 传输层类型
public enum IMTransportType {
    case webSocket      // WebSocket 传输
    case tcp            // TCP Socket 传输
}

/// 传输层协议（业务层统一接口）
public protocol IMTransportProtocol: AnyObject {
    
    /// 传输层类型
    var transportType: IMTransportType { get }
    
    /// 当前连接状态
    var state: IMTransportState { get }
    
    /// 是否已连接
    var isConnected: Bool { get }
    
    /// 状态变化回调
    var onStateChange: ((IMTransportState) -> Void)? { get set }
    
    /// 接收数据回调
    var onReceive: ((Data) -> Void)? { get set }
    
    /// 错误回调
    var onError: ((IMTransportError) -> Void)? { get set }
    
    /// 连接
    /// - Parameters:
    ///   - url: 服务器地址
    ///   - token: 认证 Token
    ///   - completion: 连接结果回调
    func connect(url: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void)
    
    /// 断开连接
    func disconnect()
    
    /// 发送数据（原始方法，用于已封装好的完整包）
    /// - Parameters:
    ///   - data: 要发送的数据
    ///   - completion: 发送结果回调
    func send(data: Data, completion: ((Result<Void, IMTransportError>) -> Void)?)
    
    /// 发送 Protobuf 消息体（推荐使用，由 transport 负责封装）
    /// - Parameters:
    ///   - body: Protobuf 消息体
    ///   - command: 命令类型（TCP 需要，WebSocket 忽略）
    ///   - completion: 发送结果回调
    func sendMessage(body: Data, command: IMCommandType, completion: ((Result<Void, IMTransportError>) -> Void)?)
    
    /// 发送文本（可选，某些传输层不支持）
    /// - Parameters:
    ///   - text: 要发送的文本
    ///   - completion: 发送结果回调
    func send(text: String, completion: ((Result<Void, IMTransportError>) -> Void)?)
}

// MARK: - 传输层配置

/// 传输层配置
public struct IMTransportConfig {
    /// 传输层类型
    public let type: IMTransportType
    
    /// 服务器地址
    public let url: String
    
    /// 连接超时（秒）
    public var connectionTimeout: TimeInterval
    
    /// 心跳间隔（秒）
    public var heartbeatInterval: TimeInterval
    
    /// 心跳超时（秒）
    public var heartbeatTimeout: TimeInterval
    
    /// 自动重连
    public var autoReconnect: Bool
    
    /// 最大重连次数（0表示无限）
    public var maxReconnectAttempts: Int
    
    /// 重连间隔（秒）
    public var reconnectInterval: TimeInterval
    
    /// TCP 专用配置
    public var tcpConfig: IMTCPConfig?
    
    /// WebSocket 专用配置
    public var webSocketConfig: IMWebSocketConfig?
    
    public init(
        type: IMTransportType,
        url: String,
        connectionTimeout: TimeInterval = 30.0,
        heartbeatInterval: TimeInterval = 30.0,
        heartbeatTimeout: TimeInterval = 10.0,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 0,
        reconnectInterval: TimeInterval = 5.0
    ) {
        self.type = type
        self.url = url
        self.connectionTimeout = connectionTimeout
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectInterval = reconnectInterval
    }
}

// MARK: - TCP 配置

/// TCP 传输层配置
public struct IMTCPConfig {
    /// 是否启用 Nagle 算法（默认禁用以降低延迟）
    public var enableNagle: Bool
    
    /// 是否启用 Keep-Alive
    public var enableKeepAlive: Bool
    
    /// Keep-Alive 间隔（秒）
    public var keepAliveInterval: TimeInterval
    
    /// 接收缓冲区大小（字节）
    public var receiveBufferSize: Int
    
    /// 发送缓冲区大小（字节）
    public var sendBufferSize: Int
    
    /// 是否使用 TLS 加密
    public var useTLS: Bool
    
    public init(
        enableNagle: Bool = false,
        enableKeepAlive: Bool = true,
        keepAliveInterval: TimeInterval = 60.0,
        receiveBufferSize: Int = 65536,
        sendBufferSize: Int = 65536,
        useTLS: Bool = true
    ) {
        self.enableNagle = enableNagle
        self.enableKeepAlive = enableKeepAlive
        self.keepAliveInterval = keepAliveInterval
        self.receiveBufferSize = receiveBufferSize
        self.sendBufferSize = sendBufferSize
        self.useTLS = useTLS
    }
}

// MARK: - WebSocket 配置

/// WebSocket 传输层配置
public struct IMWebSocketConfig {
    /// 自定义请求头
    public var headers: [String: String]
    
    /// 是否启用压缩
    public var enableCompression: Bool
    
    /// 最大帧大小（字节）
    public var maxFrameSize: Int
    
    public init(
        headers: [String: String] = [:],
        enableCompression: Bool = true,
        maxFrameSize: Int = 1_048_576  // 1MB
    ) {
        self.headers = headers
        self.enableCompression = enableCompression
        self.maxFrameSize = maxFrameSize
    }
}

// MARK: - 传输层统计信息

/// 传输层统计信息
public struct IMTransportStats {
    /// 已发送字节数
    public var bytesSent: Int64 = 0
    
    /// 已接收字节数
    public var bytesReceived: Int64 = 0
    
    /// 已发送消息数
    public var messagesSent: Int64 = 0
    
    /// 已接收消息数
    public var messagesReceived: Int64 = 0
    
    /// 连接时间（毫秒）
    public var connectionTime: Int64 = 0
    
    /// 平均往返延迟（毫秒）
    public var averageRTT: Double = 0.0
    
    /// 重连次数
    public var reconnectCount: Int = 0
    
    /// 最后一次心跳时间
    public var lastHeartbeatTime: Int64 = 0
    
    /// 丢包次数（序列号跳跃检测）
    public var packetLossCount: Int = 0
    
    /// 编解码器错误次数
    public var codecErrors: Int = 0
}


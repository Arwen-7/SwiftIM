//
//  IMTCPSocketManager.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation
import Network

// MARK: - TCP Socket 连接管理器

/// TCP Socket 连接管理器（基于 Network.framework）
///
/// Network.framework 是 Apple 推荐的现代网络 API（iOS 12+）
/// 优势：
/// - 原生支持 TLS
/// - 自动处理网络切换（WiFi ↔ 4G）
/// - 支持 IPv4/IPv6 双栈
/// - 更好的性能和电量管理
public final class IMTCPSocketManager {
    
    // MARK: - Properties
    
    /// 网络连接
    private var connection: NWConnection?
    
    /// 配置
    private let config: IMTCPConfig
    
    /// 当前状态
    private(set) var state: IMTransportState = .disconnected
    
    /// 接收缓冲区大小
    private let receiveBufferSize: Int
    
    /// 锁
    private let lock = NSLock()
    
    /// 工作队列
    private let queue = DispatchQueue(label: "com.imsdk.tcp", qos: .userInitiated)
    
    // MARK: - Callbacks
    
    /// 状态变化回调
    public var onStateChange: ((IMTransportState) -> Void)?
    
    /// 接收数据回调
    public var onReceive: ((Data) -> Void)?
    
    /// 错误回调
    public var onError: ((Error) -> Void)?
    
    // MARK: - Statistics
    
    public struct Stats {
        public var bytesSent: Int64 = 0
        public var bytesReceived: Int64 = 0
        public var connectionTime: Int64 = 0
        public var lastActivityTime: Int64 = 0
    }
    
    private(set) var stats = Stats()
    
    // MARK: - Initialization
    
    public init(config: IMTCPConfig = IMTCPConfig()) {
        self.config = config
        self.receiveBufferSize = config.receiveBufferSize
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection Management
    
    /// 连接到服务器
    /// - Parameters:
    ///   - host: 服务器地址（域名或 IP）
    ///   - port: 端口号
    ///   - useTLS: 是否使用 TLS 加密
    ///   - completion: 连接结果回调
    public func connect(host: String, port: UInt16, useTLS: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        
        // 如果已经连接，先断开
        if connection != nil {
            lock.unlock()
            disconnect()
            lock.lock()
        }
        
        // 更新状态
        updateState(.connecting)
        lock.unlock()
        
        // 创建 NWEndpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        
        // 创建 TCP 参数
        let tcpOptions = NWProtocolTCP.Options()
        
        // 禁用 Nagle 算法（降低延迟）
        if !config.enableNagle {
            tcpOptions.noDelay = true
        }
        
        // 启用 Keep-Alive
        if config.enableKeepAlive {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveInterval = Int(config.keepAliveInterval)
        }
        
        // 创建 TLS 参数
        let parameters: NWParameters
        if useTLS {
            parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcpOptions)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
        }
        
        
        // 设置网络服务质量（低延迟、交互式数据）
//        parameters.serviceClass = .responsiveData
        
        // 创建连接
        let newConnection = NWConnection(to: endpoint, using: parameters)
        
        lock.lock()
        connection = newConnection
        lock.unlock()
        
        // 设置状态变化处理
        newConnection.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state, completion: completion)
        }
        
        // 启动连接
        newConnection.start(queue: queue)
        
        // 开始接收数据
        startReceiving()
        
        // 记录连接时间
        stats.connectionTime = IMUtils.currentTimeMillis()
    }
    
    /// 断开连接
    public func disconnect() {
        lock.lock()
        let conn = connection
        connection = nil
        updateState(.disconnecting)
        lock.unlock()
        
        // 取消连接
        conn?.cancel()
        
        lock.lock()
        updateState(.disconnected)
        lock.unlock()
    }
    
    /// 是否已连接
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .connected
    }
    
    // MARK: - Send Data
    
    /// 发送数据
    /// - Parameters:
    ///   - data: 要发送的数据
    ///   - completion: 发送结果回调
    public func send(data: Data, completion: ((Result<Void, Error>) -> Void)?) {
        lock.lock()
        guard let conn = connection, state == .connected else {
            lock.unlock()
            completion?(.failure(IMTCPSocketError.notConnected))
            return
        }
        lock.unlock()
        
        // 发送数据
        conn.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.onError?(error)
                    completion?(.failure(error))
                } else {
                    // 更新统计
                    self?.lock.lock()
                    self?.stats.bytesSent += Int64(data.count)
                    self?.stats.lastActivityTime = IMUtils.currentTimeMillis()
                    self?.lock.unlock()
                    
                    completion?(.success(()))
                }
            }
        )
    }
    
    // MARK: - Receive Data
    
    /// 开始接收数据（递归循环接收）
    private func startReceiving() {
        lock.lock()
        guard let conn = connection else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        // 接收数据（最小 1 字节，最大 receiveBufferSize 字节）
        conn.receive(minimumIncompleteLength: 1, maximumLength: receiveBufferSize) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            // 处理错误
            if let error = error {
                self.onError?(error)
                return
            }
            
            // 处理接收到的数据
            if let data = data, !data.isEmpty {
                // 更新统计
                self.lock.lock()
                self.stats.bytesReceived += Int64(data.count)
                self.stats.lastActivityTime = IMUtils.currentTimeMillis()
                self.lock.unlock()
                
                // 回调
                self.onReceive?(data)
            }
            
            // 如果连接完成（关闭），更新状态
            if isComplete {
                self.lock.lock()
                self.updateState(.disconnected)
                self.lock.unlock()
                return
            }
            
            // 继续接收下一批数据
            self.startReceiving()
        }
    }
    
    // MARK: - State Handling
    
    /// 处理连接状态变化
    private func handleStateChange(_ nwState: NWConnection.State, completion: @escaping (Result<Void, Error>) -> Void) {
        switch nwState {
        case .ready:
            // 连接成功
            lock.lock()
            updateState(.connected)
            lock.unlock()
            completion(.success(()))
            
        case .waiting(let error):
            // 等待中（网络不可用等）
            onError?(error)
            
        case .failed(let error):
            // 连接失败
            lock.lock()
            updateState(.disconnected)
            lock.unlock()
            onError?(error)
            completion(.failure(error))
            
        case .cancelled:
            // 连接被取消
            lock.lock()
            updateState(.disconnected)
            lock.unlock()
            
        case .preparing, .setup:
            // 准备中，无需处理
            break
            
        @unknown default:
            break
        }
    }
    
    /// 更新状态（必须在 lock 内调用）
    private func updateState(_ newState: IMTransportState) {
        guard state != newState else { return }
        
        state = newState
        
        // 异步回调，避免死锁
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }
    
    // MARK: - Network Path Monitoring
    
    /// 获取当前网络路径信息
    public func currentPath() -> NWPath? {
        lock.lock()
        defer { lock.unlock() }
        return connection?.currentPath
    }
    
    /// 是否使用昂贵的网络（蜂窝网络）
    public var isExpensive: Bool {
        return currentPath()?.isExpensive ?? false
    }
    
    /// 是否使用受限的网络（低数据模式）
    public var isConstrained: Bool {
        return currentPath()?.isConstrained ?? false
    }
}

// MARK: - 错误定义

/// TCP Socket 错误
public enum IMTCPSocketError: Error {
    case notConnected
    case connectionFailed(Error)
    case sendFailed(Error)
    case receiveFailed(Error)
}

extension IMTCPSocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未连接到服务器"
        case .connectionFailed(let error):
            return "连接失败：\(error.localizedDescription)"
        case .sendFailed(let error):
            return "发送数据失败：\(error.localizedDescription)"
        case .receiveFailed(let error):
            return "接收数据失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Statistics Extension

extension IMTCPSocketManager.Stats: CustomStringConvertible {
    public var description: String {
        return """
        IMTCPSocketManager.Stats {
            bytesSent: \(bytesSent),
            bytesReceived: \(bytesReceived),
            connectionTime: \(connectionTime),
            lastActivityTime: \(lastActivityTime)
        }
        """
    }
}


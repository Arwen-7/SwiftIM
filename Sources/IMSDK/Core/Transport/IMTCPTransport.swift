//
//  IMTCPTransport.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - TCP 传输层实现

/// TCP 传输层（自研协议，类似微信 Mars）
///
/// 架构：
/// ```
/// IMTCPTransport
///     ├─ IMTCPSocketManager   （底层 Socket 连接）
///     ├─ IMPacketCodec        （粘包/拆包处理）
///     ├─ HeartbeatManager     （心跳保活）
///     └─ ReconnectManager     （重连机制）
/// ```
public final class IMTCPTransport: IMTransportProtocol {
    
    // MARK: - IMTransportProtocol Properties
    
    public let transportType: IMTransportType = .tcp
    
    public private(set) var state: IMTransportState = .disconnected {
        didSet {
            if state != oldValue {
                onStateChange?(state)
            }
        }
    }
    
    public var isConnected: Bool {
        return state == .connected && socketManager.isConnected
    }
    
    public var onStateChange: ((IMTransportState) -> Void)?
    public var onReceive: ((Data) -> Void)?
    public var onError: ((IMTransportError) -> Void)?
    
    // MARK: - Components
    
    /// Socket 管理器
    private let socketManager: IMTCPSocketManager
    
    /// 编解码器（处理粘包/拆包）
    private let codec: IMPacketCodec = {
        var config = IMPacketCodecConfig()
        config.enableSequenceCheck = false  // 禁用 sequence 连续性检查
        // 原因：
        // 1. Sequence 只用于请求-响应匹配，不用于丢包检测
        // 2. TCP 本身已保证字节流可靠传输
        // 3. 消息的顺序和去重由业务层的 message.seq 负责
        return IMPacketCodec(config: config)
    }()
    
    /// 序列号生成器（每个连接独立）
    private let sequenceGenerator = IMSequenceGenerator()
    
    /// 心跳管理器
    private var heartbeatManager: HeartbeatManager?
    
    /// 重连管理器
    private var reconnectManager: ReconnectManager?
    
    /// 配置
    private let config: IMTransportConfig
    
    /// 锁
    private let lock = NSRecursiveLock()
    
    /// 待确认的请求（seq → completion）
    private var pendingRequests: [UInt32: (Result<Data, IMTransportError>) -> Void] = [:]
    
    /// 统计信息
    private var stats = IMTransportStats()
    
    // MARK: - Connection Info
    
    private var serverURL: String?
    private var authToken: String?
    
    /// 是否允许自动重连（主动调用 disconnect() 时为 false）
    private var autoReconnectEnabled = true
    
    // MARK: - Packet Loss Management
    
    /// 最后一次丢包时间（用于防抖）
    private var lastPacketLossTime: Int64 = 0
    
    /// 丢包防抖间隔（10秒）
    private let packetLossDebounceInterval: Int64 = 10_000
    
    // MARK: - Initialization
    
    public init(config: IMTransportConfig) {
        self.config = config
        
        // 创建 Socket 管理器
        self.socketManager = IMTCPSocketManager(
            config: config.tcpConfig ?? IMTCPConfig()
        )
        
        // 设置 codec 致命错误回调（处理缓冲区溢出、包过大等）
        codec.onFatalError = { [weak self] error in
            guard let self = self else { return }
            
            IMLogger.shared.error("❌ TCP codec fatal error: \(error)")
            
            // 更新统计
            self.lock.lock()
            self.stats.codecErrors += 1
            self.lock.unlock()
            
            // 通知上层
            self.onError?(IMTransportError.protocolError(error.localizedDescription))
            
            // 触发重连
            self.handleFatalError(error)
        }
        
        // 设置 Socket 回调
        setupSocketCallbacks()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - IMTransportProtocol Methods
    
    public func connect(url: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void) {
        lock.lock()
        
        // 保存连接信息
        serverURL = url
        authToken = token
        
        // ✅ 启用自动重连
        autoReconnectEnabled = true
        
        // 更新状态
        state = .connecting
        lock.unlock()
        
        // ✅ 启动重连管理器（首次连接也支持自动重连）
        startReconnectMonitor()
        
        // 执行首次连接（带 completion）
        performConnect(completion: completion)
    }
    
    /// 执行实际的连接操作
    /// - Parameter completion: 连接结果回调（重连时传 nil）
    private func performConnect(completion: ((Result<Void, IMTransportError>) -> Void)? = nil) {
        guard let serverURL = serverURL, let authToken = authToken else {
            completion?(.failure(.protocolError("连接信息缺失")))
            return
        }
        
        // 解析 URL（tcp://host:port 或 tcps://host:port）
        guard let components = parseURL(serverURL) else {
            completion?(.failure(.protocolError("无效的 URL 格式")))
            return
        }
        
        // 连接 TCP Socket
        socketManager.connect(host: components.host, port: components.port, useTLS: components.useTLS) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // Socket 连接成功，发送认证请求
                self.authenticate(token: authToken, completion: completion)
                
            case .failure(let error):
                self.lock.lock()
                self.state = .disconnected
                self.lock.unlock()
                
                // TCP 连接失败
                if let completion = completion {
                    // ✅ 首次连接失败，立即通知调用方
                    IMLogger.shared.warning("TCP connection failed (first attempt): \(error)")
                    completion(.failure(.connectionFailed(error)))
                    // ⚠️ 但仍会触发自动重连（通过 onStateChange）
                } else {
                    // ✅ 重连失败，不调用 completion，由 onStateChange 通知
                    IMLogger.shared.warning("TCP connection failed (reconnect): \(error)")
                }
            }
        }
    }
    
    public func disconnect() {
        lock.lock()
        
        // ✅ 禁用自动重连（主动断开）
        autoReconnectEnabled = false
        
        // 停止心跳
        heartbeatManager?.stop()
        heartbeatManager = nil
        
        // 停止重连
        reconnectManager?.stop()
        reconnectManager = nil
        
        // 清空待确认的请求
        for (_, completion) in pendingRequests {
            completion(.failure(.notConnected))
        }
        pendingRequests.removeAll()
        
        // 更新状态
        state = .disconnecting
        lock.unlock()
        
        // 断开 Socket
        socketManager.disconnect()
        
        lock.lock()
        state = .disconnected
        codec.clearBuffer()
        lock.unlock()
    }
    
    public func send(data: Data, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        lock.lock()
        guard isConnected else {
            lock.unlock()
            completion?(.failure(.notConnected))
            return
        }
        lock.unlock()
        
        // 直接发送完整的协议包（包头+包体）
        // 注：业务层已经通过 IMPacketCodec 封装好了完整的包
        socketManager.send(data: data) { result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(.sendFailed(error)))
            }
        }
    }
    
    public func sendMessage(body: Data, command: IMCommandType, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        lock.lock()
        guard isConnected else {
            lock.unlock()
            completion?(.failure(.notConnected))
            return
        }
        
        // 生成序列号并封装包头
        let seq = sequenceGenerator.next()
        let packet = codec.encode(command: command, sequence: seq, body: body)
        lock.unlock()
        
        // 发送完整的协议包
        socketManager.send(data: packet) { result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(.sendFailed(error)))
            }
        }
    }
    
    public func send(text: String, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        // TCP 传输层只支持二进制数据
        guard let data = text.data(using: .utf8) else {
            completion?(.failure(.protocolError("文本编码失败")))
            return
        }
        send(data: data, completion: completion)
    }
    
    // MARK: - Authentication
    
    /// 发送认证请求
    /// - Parameter completion: 认证结果回调（重连时传 nil）
    private func authenticate(token: String, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        // TODO: 使用 Protobuf 序列化认证请求
        // 这里先用简化版本
        
        let authData = """
        {"type":"auth","token":"\(token)","platform":"iOS"}
        """.data(using: .utf8)!
        
        let seq = sequenceGenerator.next()
        let packet = codec.encode(command: .authReq, sequence: seq, body: authData)
        
        // 记录待确认的请求
        lock.lock()
        pendingRequests[seq] = { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // 认证成功，重置序列号（新会话从 1 开始）
                self.sequenceGenerator.reset()
                
                // 更新状态为已连接
                self.lock.lock()
                let previousState = self.state
                self.state = .connected
                self.lock.unlock()
                
                // 启动心跳
                self.startHeartbeat()
                
                // 判断是首次连接还是重连
                if let completion = completion {
                    // ✅ 首次连接成功，调用 completion
                    IMLogger.shared.info("✅ Connected successfully")
                    completion(.success(()))
                } else {
                    // ✅ 重连成功，重置重连计数，通过 onStateChange 通知
                    IMLogger.shared.info("✅ Reconnected successfully")
                    self.reconnectManager?.resetAttempts()
                }
                
            case .failure(let error):
                self.lock.lock()
                self.state = .disconnected
                self.lock.unlock()
                
                // 认证失败
                if let completion = completion {
                    // ✅ 首次连接认证失败，立即通知调用方
                    IMLogger.shared.warning("Authentication failed (first attempt): \(error)")
                    completion(.failure(error))
                    // ⚠️ 但仍会触发自动重连（通过 onStateChange）
                } else {
                    // ✅ 重连认证失败，不调用 completion，由 onStateChange 通知
                    IMLogger.shared.warning("Authentication failed (reconnect): \(error)")
                }
            }
        }
        lock.unlock()
        
        // 发送认证包
        socketManager.send(data: packet) { [weak self] result in
            switch result {
            case .success:
                // ✅ 认证包发送成功，等待服务器响应
                // 服务器响应会在 handlePacket() 中通过 pendingRequests[seq] 处理
                IMLogger.shared.debug("Auth packet sent successfully, waiting for response")
                
            case .failure(let error):
                // ❌ 认证包发送失败，立即回调失败
                self?.lock.lock()
                let callback = self?.pendingRequests.removeValue(forKey: seq)
                self?.lock.unlock()
                
                callback?(.failure(.sendFailed(error)))
            }
        }
        
        // 设置认证超时
        DispatchQueue.main.asyncAfter(deadline: .now() + config.connectionTimeout) { [weak self] in
            guard let self = self else { return }
            
            self.lock.lock()
            if let callback = self.pendingRequests.removeValue(forKey: seq) {
                self.lock.unlock()
                callback(.failure(.timeout))
            } else {
                self.lock.unlock()
            }
        }
    }
    
    // MARK: - Codec Callbacks
    
    /// 处理致命错误（使用 ReconnectManager 管理重连）
    private func handleFatalError(_ error: IMPacketCodecError) {
        lock.lock()
        let wasConnected = isConnected
        lock.unlock()
        
        guard wasConnected else {
            IMLogger.shared.debug("Not connected, no need to reconnect")
            return
        }
        
        IMLogger.shared.warning("⚠️ Fatal error detected: \(error), will reconnect...")
        
        // 快速失败：立即断开
        disconnect()
        
        // 使用 ReconnectManager 触发重连（内置指数退避 + 最大次数限制）
        reconnectManager?.triggerReconnect()
    }
    
    // MARK: - Socket Callbacks
    
    private func setupSocketCallbacks() {
        // 状态变化（✅ 关键改进：同步 Socket 层状态）
        socketManager.onStateChange = { [weak self] socketState in
            guard let self = self else { return }
            
            switch socketState {
            case .disconnected:
                // Socket 断开，立即同步到 Transport 层
                self.lock.lock()
                self.state = .disconnected
                
                // 停止心跳
                self.heartbeatManager?.stop()
                self.heartbeatManager = nil
                
                // ✅ 简化逻辑：只检查 autoReconnectEnabled 标志
                let shouldAutoReconnect = self.autoReconnectEnabled
                let reconnectManager = self.reconnectManager
                self.lock.unlock()
                
                // 判断是否需要自动重连
                if shouldAutoReconnect, let manager = reconnectManager {
                    IMLogger.shared.warning("Socket disconnected, triggering auto-reconnect")
                    let error = NSError(domain: "IMTCPTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Socket 连接断开"])
                    self.onError?(.connectionFailed(error))
                    manager.triggerReconnect()
                } else {
                    IMLogger.shared.debug("Socket disconnected, auto-reconnect disabled or manager not available")
                }
                
            case .connecting:
                // Socket 正在连接，Transport 层也应该是 connecting
                // （通常由 Transport.connect() 主动触发，这里做防御性同步）
                self.lock.lock()
                if self.state == .disconnected {
                    self.state = .connecting
                }
                self.lock.unlock()
                
            case .connected:
                // Socket 连接成功，但 Transport 层需要等待认证成功
                // 不在这里设置 .connected，由 authenticate() 完成后设置
                IMLogger.shared.debug("Socket connected, waiting for authentication")
                
            case .reconnecting:
                // Socket 正在重连
                self.lock.lock()
                if self.state != .reconnecting {
                    self.state = .reconnecting
                }
                self.lock.unlock()
                
            case .disconnecting:
                // Socket 正在断开
                self.lock.lock()
                if self.state != .disconnected {
                    self.state = .disconnecting
                }
                self.lock.unlock()
            }
        }
        
        // 接收数据
        socketManager.onReceive = { [weak self] data in
            self?.handleReceivedData(data)
        }
        
        // 错误
        socketManager.onError = { [weak self] error in
            self?.onError?(.receiveFailed(error))
        }
    }
    
    /// 处理接收到的数据
    private func handleReceivedData(_ data: Data) {
        do {
            // 解码数据包（处理粘包/拆包）
            let packets = try codec.decode(data: data)
            
            for packet in packets {
                handlePacket(packet)
            }
            
        } catch {
            onError?(.protocolError("数据包解码失败：\(error.localizedDescription)"))
        }
    }
    
    /// 处理单个数据包
    private func handlePacket(_ packet: IMPacket) {
        let command = packet.header.command
        let sequence = packet.header.sequence
        let body = packet.body
        
        // 检查是否是响应包（匹配待确认的请求）
        lock.lock()
        if let callback = pendingRequests.removeValue(forKey: sequence) {
            lock.unlock()
            
            // 这是响应包（服务器回显客户端的 sequence）
            callback(.success(body))
            return
        }
        lock.unlock()
        
        // 这是推送包（服务器主动推送的消息）
        // 注：不检查 sequence 连续性，因为：
        // 1. TCP 本身已保证字节流可靠传输
        // 2. 服务器推送可能来自不同实例（负载均衡），sequence 可能不连续
        // 3. 消息的顺序和去重由业务层的 message.seq 负责
        switch command {
        case .pushMsg, .batchMsg:
            // 消息推送
            onReceive?(body)
            
        case .heartbeatRsp:
            // 心跳响应
            heartbeatManager?.handleHeartbeatResponse()
            
        case .kickOut:
            // 踢出通知
            disconnect()
            onError?(.protocolError("被踢出：其他设备登录"))
            
        default:
            // 其他推送消息
            onReceive?(body)
        }
    }
    
    // MARK: - Heartbeat Management
    
    /// 启动心跳
    private func startHeartbeat() {
        guard config.heartbeatInterval > 0 else { return }
        
        heartbeatManager = HeartbeatManager(
            interval: config.heartbeatInterval,
            timeout: config.heartbeatTimeout
        )
        
        heartbeatManager?.onSendHeartbeat = { [weak self] in
            self?.sendHeartbeat()
        }
        
        heartbeatManager?.onTimeout = { [weak self] in
            // 心跳超时，尝试重连
            self?.handleHeartbeatTimeout()
        }
        
        heartbeatManager?.start()
    }
    
    /// 发送心跳包
    private func sendHeartbeat() {
        let heartbeatData = """
        {"type":"ping","time":\(IMUtils.currentTimeMillis())}
        """.data(using: .utf8)!
        
        let seq = sequenceGenerator.next()
        let packet = codec.encode(command: .heartbeatReq, sequence: seq, body: heartbeatData)
        
        socketManager.send(data: packet, completion: nil)
    }
    
    /// 心跳超时处理
    private func handleHeartbeatTimeout() {
        print("[IMTCPTransport] 心跳超时，尝试重连...")
        
        // 触发重连
        reconnectManager?.triggerReconnect()
    }
    
    // MARK: - Reconnect Management
    
    /// 启动重连监控
    private func startReconnectMonitor() {
        guard config.autoReconnect else { return }
        
        reconnectManager = ReconnectManager(
            maxAttempts: config.maxReconnectAttempts,
            baseInterval: config.reconnectInterval
        )
        
        // ✅ 重连回调
        reconnectManager?.onReconnect = { [weak self] in
            self?.performReconnect()
        }
        
        // ✅ 达到最大重连次数回调
        reconnectManager?.onMaxAttemptsReached = { [weak self] in
            guard let self = self else { return }
            IMLogger.shared.error("❌ Max reconnect attempts reached")
            self.onError?(IMTransportError.maxReconnectAttemptsReached)
        }
    }
    
    /// 执行重连
    private func performReconnect() {
        guard let url = serverURL, let token = authToken else { return }
        
        lock.lock()
        state = .reconnecting
        lock.unlock()
        
        IMLogger.shared.info("🔄 Attempting to reconnect...")
        
        // ✅ 重连时调用 performConnect()，不传 completion（通过 onStateChange 通知）
        performConnect(completion: nil)
    }
    
    // MARK: - Helper Methods
    
    /// 解析 URL（tcp://host:port 或 tcps://host:port）
    private func parseURL(_ urlString: String) -> (host: String, port: UInt16, useTLS: Bool)? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        let scheme = url.scheme?.lowercased()
        let useTLS = (scheme == "tcps" || scheme == "tls")
        
        guard let host = url.host else {
            return nil
        }
        
        let port = url.port ?? (useTLS ? 443 : 8080)
        
        return (host: host, port: UInt16(port), useTLS: useTLS)
    }
}

// MARK: - Heartbeat Manager

/// 心跳管理器
private final class HeartbeatManager {
    private let interval: TimeInterval
    private let timeout: TimeInterval
    private var timer: Timer?
    private var timeoutTimer: Timer?
    
    var onSendHeartbeat: (() -> Void)?
    var onTimeout: (() -> Void)?
    
    init(interval: TimeInterval, timeout: TimeInterval) {
        self.interval = interval
        self.timeout = timeout
    }
    
    func start() {
        stop()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        
        // 立即发送一次心跳
        sendHeartbeat()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    private func sendHeartbeat() {
        onSendHeartbeat?()
        
        // 启动超时定时器
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.onTimeout?()
        }
    }
    
    func handleHeartbeatResponse() {
        // 收到心跳响应，取消超时定时器
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}

// MARK: - Reconnect Manager

/// 重连管理器
private final class ReconnectManager {
    private let maxAttempts: Int
    private let baseInterval: TimeInterval
    private var currentAttempt = 0
    private var timer: Timer?
    
    var onReconnect: (() -> Void)?
    var onMaxAttemptsReached: (() -> Void)?  // ✅ 新增：达到最大重连次数回调
    
    init(maxAttempts: Int, baseInterval: TimeInterval) {
        self.maxAttempts = maxAttempts
        self.baseInterval = baseInterval
    }
    
    func triggerReconnect() {
        guard maxAttempts == 0 || currentAttempt < maxAttempts else {
            IMLogger.shared.error("[ReconnectManager] Max reconnect attempts reached (\(maxAttempts))")
            onMaxAttemptsReached?()  // ✅ 触发回调
            return
        }
        
        currentAttempt += 1
        
        // ✅ 指数退避算法：2^n * baseInterval，最大32秒
        let delay = min(pow(2.0, Double(min(currentAttempt - 1, 5))) * baseInterval, 32.0)
        
        // ✅ 添加随机抖动（避免雪崩效应）
        let jitter = Double.random(in: 0...0.3) * delay
        let finalDelay = delay + jitter
        
        IMLogger.shared.info("[ReconnectManager] Reconnect attempt \(currentAttempt)/\(maxAttempts), delay: \(String(format: "%.1f", finalDelay))s")
        
        timer = Timer.scheduledTimer(withTimeInterval: finalDelay, repeats: false) { [weak self] _ in
            self?.onReconnect?()
        }
    }
    
    func resetAttempts() {
        currentAttempt = 0
        timer?.invalidate()
        timer = nil
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        currentAttempt = 0
    }
}



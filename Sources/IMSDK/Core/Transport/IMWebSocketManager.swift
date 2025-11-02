/// IMWebSocketManager - WebSocket 连接管理器
/// 提供 WebSocket 长连接功能，使用 callback 模式（类似 NWConnection）

import Foundation
import Starscream

/// WebSocket 连接管理器
public final class IMWebSocketManager {
    
    // MARK: - Properties
    
    private var socket: WebSocket?
    private var currentURL: String?  // 当前连接的 URL
    private var currentToken: String?  // 当前连接的 Token
    private var _isConnected = false  // 内部维护连接状态
    private var isManualDisconnect = false
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 5
    private var reconnectDelay: TimeInterval = 2.0
    private var pingTimer: Timer?
    private var pongReceived = false
    
    private let queue = DispatchQueue(label: "com.imsdk.websocket", qos: .userInitiated)
    
    // 回调
    public var onConnected: (() -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onMessage: ((Data) -> Void)?
    public var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// 连接
    /// - Parameters:
    ///   - url: WebSocket 服务器地址
    ///   - token: 认证 Token（可选）
    ///   - completion: 连接结果回调
    public func connect(url: String, token: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        // 检查是否已连接
        if _isConnected {
            IMLogger.shared.warning("WebSocket already connected")
            completion(.success(()))
            return
        }
        
        isManualDisconnect = false
        self.currentURL = url
        self.currentToken = token
        
        var urlString = url
        if let token = token {
            // 如果 URL 已经包含参数，用 & 连接；否则用 ?
            let separator = url.contains("?") ? "&" : "?"
            urlString += "\(separator)token=\(token)"
        }
        
        guard let wsURL = URL(string: urlString) else {
            let error = NSError(domain: "IMWebSocketManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            IMLogger.shared.error("Invalid WebSocket URL: \(urlString)")
            onError?(error)
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 10
        
        let ws = WebSocket(request: request)
        self.socket = ws
        
        // 设置事件回调（callback 模式，类似 NWConnection.stateUpdateHandler）
        ws.onEvent = { [weak self] event in
            self?.handleWebSocketEvent(event, completion: completion)
        }
        
        IMLogger.shared.info("Connecting to WebSocket: \(url)")
        ws.connect()
    }
    
    /// 断开连接
    public func disconnect() {
        isManualDisconnect = true
        _isConnected = false  // 更新连接状态
        reconnectAttempts = 0
        stopPingTimer()
        
        socket?.disconnect()
        socket = nil
        
        IMLogger.shared.info("WebSocket disconnected")
    }
    
    /// 发送数据
    /// - Parameter data: 数据
    public func send(data: Data) {
        guard _isConnected, let socket = socket else {
            IMLogger.shared.error("WebSocket not connected, cannot send data")
            return
        }
        
        socket.write(data: data)
        IMLogger.shared.debug("WebSocket sent \(data.count) bytes")
    }
    
    /// 发送文本
    /// - Parameter text: 文本
    public func send(text: String) {
        guard _isConnected, let socket = socket else {
            IMLogger.shared.error("WebSocket not connected, cannot send text")
            return
        }
        
        socket.write(string: text)
        IMLogger.shared.debug("WebSocket sent text: \(text)")
    }
    
    /// 是否已连接
    public var isConnected: Bool {
        return _isConnected
    }
    
    /// 启动心跳（在认证成功后调用）
    public func startHeartbeat() {
        IMLogger.shared.info("Starting WebSocket heartbeat (Ping/Pong)")
        pongReceived = true  // 初始化为 true，假设连接是健康的
        startPingTimer()
    }
    
    // MARK: - Private Methods
    
    private func reconnect() {
        guard !isManualDisconnect else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            IMLogger.shared.error("Max reconnection attempts reached")
            onError?(IMError.networkError("Max reconnection attempts reached"))
            return
        }
        
        reconnectAttempts += 1
        let delay = reconnectDelay * Double(reconnectAttempts)
        
        IMLogger.shared.info("Reconnecting in \(delay) seconds (attempt \(reconnectAttempts))")
        
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let url = self.currentURL else { return }
            
            // 重连时使用之前保存的 URL 和 Token
            self.connect(url: url, token: self.currentToken) { result in
                switch result {
                case .success:
                    IMLogger.shared.info("Reconnection successful")
                case .failure(let error):
                    IMLogger.shared.error("Reconnection failed: \(error)")
                }
            }
        }
    }
    
    private func startPingTimer() {
        stopPingTimer()
        
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        guard _isConnected, let socket = socket else {
            IMLogger.shared.debug("Cannot send ping: not connected")
            return
        }
        
        // 检查上一次 Ping 是否收到 Pong
        if !pongReceived {
            IMLogger.shared.warning("❌ Pong not received for last Ping, connection may be dead")
            disconnect()
            reconnect()
            return
        }
        
        // 发送 Ping 并重置标志
        pongReceived = false
        socket.write(ping: Data())
        IMLogger.shared.debug("📤 Ping sent, waiting for Pong...")
    }
    
    // MARK: - Event Handling
    
    /// 处理 WebSocket 事件（类似 IMTCPSocketManager.handleStateChange）
    private func handleWebSocketEvent(_ event: WebSocketEvent, completion: @escaping (Result<Void, Error>) -> Void) {
        switch event {
        case .connected(let headers):
            IMLogger.shared.info("WebSocket connected (physical layer)")
            _isConnected = true
            reconnectAttempts = 0
            // 注意：不在这里启动 Ping 定时器
            // 等待上层认证成功后再启动（通过 startHeartbeat() 方法）
            
            // 连接成功，调用 completion（只调用一次）
            completion(.success(()))
            
            onConnected?()
            
        case .disconnected(let reason, let code):
            IMLogger.shared.warning("WebSocket disconnected: \(reason), code: \(code)")
            
            let wasConnected = _isConnected
            _isConnected = false
            stopPingTimer()
            
            // 如果之前未连接成功就断开了，说明连接失败
            if !wasConnected {
                let error = NSError(domain: "IMWebSocketManager", code: Int(code), userInfo: [NSLocalizedDescriptionKey: reason])
                completion(.failure(error))
            }
            
            onDisconnected?(nil)
            
            if !isManualDisconnect {
                reconnect()
            }
            
        case .text(let text):
            IMLogger.shared.debug("WebSocket received text: \(text)")
            if let data = text.data(using: .utf8) {
                onMessage?(data)
            }
            
        case .binary(let data):
            IMLogger.shared.debug("WebSocket received \(data.count) bytes")
            onMessage?(data)
            
        case .ping(_):
            IMLogger.shared.verbose("Ping received")
            
        case .pong(_):
            IMLogger.shared.debug("📥 Pong received - connection is alive")
            pongReceived = true
            
        case .viabilityChanged(let isViable):
            IMLogger.shared.debug("WebSocket viability changed: \(isViable)")
            
        case .reconnectSuggested(let shouldReconnect):
            if shouldReconnect && !isManualDisconnect {
                IMLogger.shared.info("Reconnect suggested")
                reconnect()
            }
            
        case .cancelled:
            IMLogger.shared.info("WebSocket cancelled")
            _isConnected = false
            stopPingTimer()
            onDisconnected?(nil)
            
        case .error(let error):
            IMLogger.shared.error("WebSocket error: \(error?.localizedDescription ?? "unknown")")
            
            let wasConnected = _isConnected
            _isConnected = false
            stopPingTimer()
            
            // 如果之前未连接成功就出错了，说明连接失败
            if !wasConnected {
                completion(.failure(error ?? IMError.networkError("Unknown error")))
            }
            
            onError?(error ?? IMError.networkError("Unknown error"))
            
            if !isManualDisconnect {
                reconnect()
            }
            
        case .peerClosed:
            IMLogger.shared.warning("WebSocket peer closed")
            stopPingTimer()
            onDisconnected?(nil)
            
            if !isManualDisconnect {
                reconnect()
            }
        }
    }
}


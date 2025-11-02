//
//  IMWebSocketTransport.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - WebSocket 传输层实现

/// WebSocket 传输层（包装现有的 IMWebSocketManager）
///
/// 这个适配器将现有的 WebSocket 实现包装成统一的 IMTransportProtocol 接口
public final class IMWebSocketTransport: IMTransportProtocol {
    
    // MARK: - IMTransportProtocol Properties
    
    public let transportType: IMTransportType = .webSocket
    
    public private(set) var state: IMTransportState = .disconnected {
        didSet {
            if state != oldValue {
                onStateChange?(state)
            }
        }
    }
    
    public var isConnected: Bool {
        return state == .connected && wsManager.isConnected
    }
    
    public var onStateChange: ((IMTransportState) -> Void)?
    public var onReceive: ((Data) -> Void)?
    public var onError: ((IMTransportError) -> Void)?
    
    // MARK: - Properties
    
    /// WebSocket 管理器
    private let wsManager: IMWebSocketManager
    
    /// 配置
    private let config: IMTransportConfig
    
    /// 认证 token
    private var authToken: String?
    
    /// 认证完成回调（等待服务器认证响应）
    private var authCompletion: ((Result<Void, IMTransportError>) -> Void)?
    
    /// 序列号生成器（每个连接独立）
    private let sequenceGenerator = IMSequenceGenerator()
    
    /// 锁
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(config: IMTransportConfig) {
        self.config = config
        self.wsManager = IMWebSocketManager()
        
        setupCallbacks()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - IMTransportProtocol Methods
    
    public func connect(url: String, userID: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void) {
        lock.lock()
        state = .connecting
        self.authToken = token  // 保存 token
        lock.unlock()
        
        // 连接 WebSocket（使用 completion 回调，类似 NWConnection）
        wsManager.connect(url: url, token: token) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // WebSocket 连接成功，发送认证消息
                IMLogger.shared.info("WebSocket connected, sending auth message...")
                self.sendAuthMessage(userID: userID, token: token, completion: completion)
                
            case .failure(let error):
                self.lock.lock()
                self.state = .disconnected
                self.lock.unlock()
                completion(.failure(.connectionFailed(error)))
            }
        }
    }
    
    // 处理认证响应
    private func handleAuthResponse(_ wsMessage: Im_Protocol_WebSocketMessage) {
        do {
            let authRsp = try Im_Protocol_AuthResponse(serializedData: wsMessage.body)
            
            lock.lock()
            guard let completion = authCompletion else {
                lock.unlock()
                IMLogger.shared.warning("Received auth response but no pending completion")
                return
            }
            authCompletion = nil
            lock.unlock()
            
            if authRsp.errorCode == .errSuccess {
                // 认证成功
                IMLogger.shared.info("✅ WebSocket authentication succeeded, maxSeq=\(authRsp.maxSeq)")
                
                lock.lock()
                state = .connected
                lock.unlock()
                
                // 认证成功后启动心跳（Ping/Pong）
                wsManager.startHeartbeat()
                
                completion(.success(()))
            } else {
                // 认证失败
                IMLogger.shared.error("❌ WebSocket authentication failed: \(authRsp.errorMsg)")
                
                lock.lock()
                state = .disconnected
                lock.unlock()
                
                completion(.failure(.protocolError("Authentication failed: \(authRsp.errorMsg)")))
            }
        } catch {
            IMLogger.shared.error("Failed to parse auth response: \(error)")
            
            lock.lock()
            if let completion = authCompletion {
                authCompletion = nil
                state = .disconnected
                lock.unlock()
                
                completion(.failure(.protocolError("Failed to parse auth response")))
            } else {
                lock.unlock()
            }
        }
    }
    
    // 发送认证消息
    private func sendAuthMessage(userID: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void) {
        // 创建认证请求
        var authReq = Im_Protocol_AuthRequest()
        authReq.token = token
        authReq.platform = "iOS"
        authReq.userID = userID  // 使用传入的 userID
        
        do {
            let data = try authReq.serializedData()
            
            // 生成序列号
            let sequence = sequenceGenerator.next()
            
            // 创建 WebSocket 消息包装
            var wsMessage = Im_Protocol_WebSocketMessage()
            wsMessage.command = .cmdAuthReq
            wsMessage.sequence = sequence
            wsMessage.body = data
            
            let wsData = try wsMessage.serializedData()
            
            // 保存认证完成回调，等待服务器响应
            lock.lock()
            authCompletion = completion
            lock.unlock()
            
            // 发送认证消息
            wsManager.send(data: wsData)
            
            IMLogger.shared.info("Auth message sent via WebSocket (sequence=\(sequence)), waiting for response...")
            
            // 设置认证超时（10秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }
                
                self.lock.lock()
                if let pendingCompletion = self.authCompletion {
                    self.authCompletion = nil
                    self.state = .disconnected
                    self.lock.unlock()
                    
                    IMLogger.shared.error("Auth timeout")
                    pendingCompletion(.failure(.timeout))
                } else {
                    self.lock.unlock()
                }
            }
            
        } catch {
            IMLogger.shared.error("Failed to serialize auth message: \(error)")
            lock.lock()
            state = .disconnected
            lock.unlock()
            completion(.failure(.protocolError("Failed to create auth message")))
        }
    }
    
    public func disconnect() {
        lock.lock()
        state = .disconnecting
        lock.unlock()
        
        wsManager.disconnect()
        
        lock.lock()
        state = .disconnected
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
        
        // WebSocket 的 send 是同步的，数据直接放入发送缓冲区
        wsManager.send(data: data)
        completion?(.success(()))
    }
    
    public func sendMessage(body: Data, command: IMCommandType, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        lock.lock()
        guard isConnected else {
            lock.unlock()
            completion?(.failure(.notConnected))
            return
        }
        
        // 生成递增的序列号
        let sequence = sequenceGenerator.next()
        lock.unlock()
        
        do {
            // 封装为 WebSocketMessage（与 sendAuthMessage 保持一致）
            var wsMessage = Im_Protocol_WebSocketMessage()
            
            // 将 IMCommandType 转换为 Protobuf CommandType（通过 rawValue 映射）
            if let protobufCommand = Im_Protocol_CommandType(rawValue: Int(command.rawValue)) {
                wsMessage.command = protobufCommand
            } else {
                wsMessage.command = .cmdUnknown
                IMLogger.shared.warning("Unknown command type: \(command), using CMD_UNKNOWN")
            }
            
            wsMessage.sequence = sequence
            wsMessage.body = body
            
            let wsData = try wsMessage.serializedData()
            
            // 发送 WebSocket 消息
            wsManager.send(data: wsData)
            completion?(.success(()))
            
            IMLogger.shared.verbose("WebSocket message sent: command=\(command), sequence=\(sequence)")
            
        } catch {
            IMLogger.shared.error("Failed to serialize WebSocketMessage: \(error)")
            completion?(.failure(.protocolError("Failed to serialize message")))
        }
    }
    
    public func send(text: String, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        lock.lock()
        guard isConnected else {
            lock.unlock()
            completion?(.failure(.notConnected))
            return
        }
        lock.unlock()
        
        // WebSocket 的 send 是同步的，数据直接放入发送缓冲区
        wsManager.send(text: text)
        completion?(.success(()))
    }
    
    // MARK: - Setup Callbacks
    
    private func setupCallbacks() {
        // 连接状态变化（注意：WebSocket 连接成功不等于认证成功）
        wsManager.onConnected = { [weak self] in
            guard let self = self else { return }
            // 不在这里设置 state 为 connected
            // 等待认证成功后再设置
            IMLogger.shared.debug("WebSocket layer connected (waiting for auth)")
        }
        
        wsManager.onDisconnected = { [weak self] error in
            guard let self = self else { return }
            self.lock.lock()
            self.state = .disconnected
            self.lock.unlock()
            
            if let error = error {
                self.onError?(.connectionFailed(error))
            }
        }
        
        // 接收数据（WebSocket 直接传递 Protobuf body，不使用 IMPacket 格式）
        wsManager.onMessage = { [weak self] data in
            guard let self = self else { return }
            
            IMLogger.shared.debug("WebSocket received \(data.count) bytes")
            
            // 尝试解析 WebSocket 消息，检查是否是认证响应
            do {
                let wsMessage = try Im_Protocol_WebSocketMessage(serializedData: data)
                
                IMLogger.shared.debug("Parsed WebSocket message: command=\(wsMessage.command), seq=\(wsMessage.sequence)")
                
                // 如果是认证响应，特殊处理
                if wsMessage.command == .cmdAuthRsp {
                    IMLogger.shared.info("Received auth response, handling...")
                    self.handleAuthResponse(wsMessage)
                    return
                }
            } catch {
                // 解析失败，仍然传递给上层
                IMLogger.shared.warning("Failed to parse WebSocket message: \(error)")
            }
            
            // ✅ WebSocket 直接传递原始 Protobuf 数据
            // 上层会根据 transportType 选择不同的解码方式
            self.onReceive?(data)
        }
        
        // 错误
        wsManager.onError = { [weak self] error in
            self?.onError?(.receiveFailed(error))
        }
    }
    
}


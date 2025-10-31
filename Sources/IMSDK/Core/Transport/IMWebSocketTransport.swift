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
    
    public func connect(url: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void) {
        lock.lock()
        state = .connecting
        lock.unlock()
        
        // 连接 WebSocket（使用 completion 回调，类似 NWConnection）
        wsManager.connect(url: url, token: token) { [weak self] result in
            guard let self = self else { return }
            
            self.lock.lock()
            switch result {
            case .success:
                self.state = .connected
                self.lock.unlock()
                completion(.success(()))
                
            case .failure(let error):
                self.state = .disconnected
                self.lock.unlock()
                completion(.failure(.connectionFailed(error)))
            }
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
        lock.unlock()
        
        // WebSocket 直接发送 Protobuf body（不需要包头）
        wsManager.send(data: body)
        completion?(.success(()))
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
        // 连接状态变化
        wsManager.onConnected = { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.state = .connected
            self.lock.unlock()
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
            // ✅ WebSocket 直接传递原始 Protobuf 数据
            // 上层会根据 transportType 选择不同的解码方式
            self?.onReceive?(data)
        }
        
        // 错误
        wsManager.onError = { [weak self] error in
            self?.onError?(.receiveFailed(error))
        }
    }
    
}


//
//  IMTransportFactory.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//  Copyright © 2025 IMSDK. All rights reserved.
//

import Foundation

// MARK: - 传输层工厂

/// 传输层工厂（根据配置创建不同的传输层实例）
public final class IMTransportFactory {
    
    /// 创建传输层实例
    /// - Parameter config: 传输层配置
    /// - Returns: 传输层实例
    public static func createTransport(with config: IMTransportConfig) -> IMTransportProtocol {
        switch config.type {
        case .webSocket:
            return IMWebSocketTransport(config: config)
            
        case .tcp:
            return IMTCPTransport(config: config)
        }
    }
    
    /// 创建默认的 WebSocket 传输层
    /// - Parameter url: 服务器地址
    /// - Returns: WebSocket 传输层实例
    public static func createWebSocketTransport(url: String) -> IMTransportProtocol {
        let config = IMTransportConfig(
            type: .webSocket,
            url: url,
            connectionTimeout: 30.0,
            heartbeatInterval: 30.0,
            autoReconnect: true
        )
        return IMWebSocketTransport(config: config)
    }
    
    /// 创建默认的 TCP 传输层
    /// - Parameter url: 服务器地址
    /// - Returns: TCP 传输层实例
    public static func createTCPTransport(url: String) -> IMTransportProtocol {
        var config = IMTransportConfig(
            type: .tcp,
            url: url,
            connectionTimeout: 30.0,
            heartbeatInterval: 30.0,
            autoReconnect: true
        )
        config.tcpConfig = IMTCPConfig(
            enableNagle: false,      // 禁用 Nagle（降低延迟）
            enableKeepAlive: true,
            useTLS: true
        )
        return IMTCPTransport(config: config)
    }
}

// MARK: - 协议切换器

/// 协议切换器（运行时动态切换传输层）
///
/// 使用场景：
/// - 弱网环境检测后自动切换协议
/// - 根据服务器推荐切换协议
/// - A/B 测试不同协议的性能
public final class IMTransportSwitcher {
    
    // MARK: - Properties
    
    /// 当前传输层
    public var currentTransport: IMTransportProtocol
    
    /// 传输层配置
    private var webSocketConfig: IMTransportConfig
    private var tcpConfig: IMTransportConfig
    
    /// 锁
    private let lock = NSRecursiveLock()
    
    /// 是否正在切换
    private var isSwitching = false
    
    /// 当前连接信息
    private var currentURL: String?
    private var currentToken: String?
    
    // MARK: - Callbacks
    
    /// 状态变化回调
    public var onStateChange: ((IMTransportState) -> Void)? {
        didSet {
            currentTransport.onStateChange = onStateChange
        }
    }
    
    /// 接收数据回调
    public var onReceive: ((Data) -> Void)? {
        didSet {
            currentTransport.onReceive = onReceive
        }
    }
    
    /// 错误回调
    public var onError: ((IMTransportError) -> Void)? {
        didSet {
            currentTransport.onError = onError
        }
    }
    
    /// 协议切换通知
    public var onTransportSwitch: ((IMTransportType, IMTransportType) -> Void)?
    
    // MARK: - Initialization
    
    public init(initialType: IMTransportType, url: String) {
        // 创建配置
        self.webSocketConfig = IMTransportConfig(type: .webSocket, url: url)
        
        var tcpConfig = IMTransportConfig(type: .tcp, url: url)
        tcpConfig.tcpConfig = IMTCPConfig()
        self.tcpConfig = tcpConfig
        
        // 创建初始传输层
        self.currentTransport = IMTransportFactory.createTransport(
            with: initialType == .webSocket ? webSocketConfig : tcpConfig
        )
    }
    
    // MARK: - Public Methods
    
    /// 连接
    public func connect(url: String, token: String, completion: @escaping (Result<Void, IMTransportError>) -> Void) {
        lock.lock()
        currentURL = url
        currentToken = token
        lock.unlock()
        
        currentTransport.connect(url: url, token: token, completion: completion)
    }
    
    /// 断开连接
    public func disconnect() {
        currentTransport.disconnect()
    }
    
    /// 发送数据
    public func send(data: Data, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        currentTransport.send(data: data, completion: completion)
    }
    
    /// 发送文本
    public func send(text: String, completion: ((Result<Void, IMTransportError>) -> Void)?) {
        currentTransport.send(text: text, completion: completion)
    }
    
    /// 当前传输层类型
    public var currentTransportType: IMTransportType {
        lock.lock()
        defer { lock.unlock() }
        return currentTransport.transportType
    }
    
    /// 是否已连接
    public var isConnected: Bool {
        return currentTransport.isConnected
    }
    
    // MARK: - Switch Transport
    
    /// 切换到指定的传输层
    /// - Parameters:
    ///   - type: 目标传输层类型
    ///   - completion: 切换结果回调
    public func switchTo(type: IMTransportType, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        
        // 检查是否需要切换
        guard currentTransport.transportType != type else {
            lock.unlock()
            completion(.success(()))
            return
        }
        
        // 检查是否正在切换
        guard !isSwitching else {
            lock.unlock()
            completion(.failure(IMTransportSwitchError.switchInProgress))
            return
        }
        
        isSwitching = true
        let oldType = currentTransport.transportType
        let oldTransport = currentTransport
        
        guard let url = currentURL, let token = currentToken else {
            isSwitching = false
            lock.unlock()
            completion(.failure(IMTransportSwitchError.noConnectionInfo))
            return
        }
        
        lock.unlock()
        
        print("[IMTransportSwitcher] 开始切换：\(oldType) → \(type)")
        
        // 1. 断开旧连接
        oldTransport.disconnect()
        
        lock.lock()
        
        // 2. 创建新传输层
        let newConfig = (type == .webSocket) ? webSocketConfig : tcpConfig
        let newTransport = IMTransportFactory.createTransport(with: newConfig)
        
        // 3. 设置回调
        newTransport.onStateChange = onStateChange
        newTransport.onReceive = onReceive
        newTransport.onError = onError
        
        // 4. 更新当前传输层
        currentTransport = newTransport
        
        lock.unlock()
        
        // 5. 连接新传输层
        newTransport.connect(url: url, token: token) { [weak self] result in
            guard let self = self else { return }
            
            self.lock.lock()
            self.isSwitching = false
            self.lock.unlock()
            
            switch result {
            case .success:
                print("[IMTransportSwitcher] 切换成功：\(oldType) → \(type)")
                self.onTransportSwitch?(oldType, type)
                completion(.success(()))
                
            case .failure(let error):
                print("[IMTransportSwitcher] 切换失败：\(error.localizedDescription)")
                
                // 切换失败，尝试恢复旧连接
                self.lock.lock()
                self.currentTransport = oldTransport
                self.lock.unlock()
                
                oldTransport.connect(url: url, token: token) { rollbackResult in
                    switch rollbackResult {
                    case .success:
                        print("[IMTransportSwitcher] 已回滚到旧协议：\(oldType)")
                    case .failure:
                        print("[IMTransportSwitcher] 回滚失败，连接已断开")
                    }
                }
                
                completion(.failure(error))
            }
        }
    }
    
    /// 智能切换（根据网络质量自动选择）
    /// - Parameters:
    ///   - quality: 当前网络质量
    ///   - completion: 切换结果回调
    public func smartSwitch(quality: NetworkQuality, completion: @escaping (Result<Void, Error>) -> Void) {
        let recommendedType = recommendTransport(for: quality)
        
        guard recommendedType != currentTransportType else {
            // 无需切换
            completion(.success(()))
            return
        }
        
        print("[IMTransportSwitcher] 智能切换建议：\(currentTransportType) → \(recommendedType)（网络质量：\(quality)）")
        
        switchTo(type: recommendedType, completion: completion)
    }
    
    // MARK: - Private Methods
    
    /// 根据网络质量推荐传输层
    private func recommendTransport(for quality: NetworkQuality) -> IMTransportType {
        switch quality {
        case .excellent, .good:
            // 网络好，使用 WebSocket（兼容性更好）
            return .webSocket
            
        case .poor, .veryPoor:
            // 弱网，使用 TCP（更可靠，协议开销更小）
            return .tcp
        }
    }
}

// MARK: - Network Quality

/// 网络质量
public enum NetworkQuality {
    case excellent  // 优秀（WiFi 强信号）
    case good       // 良好（WiFi 弱信号 / 4G）
    case poor       // 较差（3G / 弱 4G）
    case veryPoor   // 很差（2G / 极弱网）
}

// MARK: - Switch Error

/// 传输层切换错误
public enum IMTransportSwitchError: Error {
    case switchInProgress   // 正在切换中
    case noConnectionInfo   // 缺少连接信息
}

extension IMTransportSwitchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .switchInProgress:
            return "正在切换中，请稍后重试"
        case .noConnectionInfo:
            return "缺少连接信息（URL 或 Token）"
        }
    }
}


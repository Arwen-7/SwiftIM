/// IMClient - IM SDK 主入口
/// 提供统一的接口管理所有 IM 功能

import Foundation

/// SDK 配置
public struct IMConfig {
    /// API 服务器地址
    public var apiURL: String
    /// IM 服务器地址（WebSocket 或 TCP）
    public var imURL: String
    /// 日志配置
    public var logConfig: IMLoggerConfig
    /// 数据库配置
    public var databaseConfig: IMDatabaseConfig
    /// 网络超时时间
    public var timeout: TimeInterval
    
    /// 传输层类型（默认 WebSocket）
    public var transportType: IMTransportType
    
    /// 是否启用智能协议切换
    public var enableSmartSwitch: Bool
    
    /// 传输层配置（可选，不指定则使用默认配置）
    public var transportConfig: IMTransportConfig?
    
    public init(
        apiURL: String,
        imURL: String,
        logConfig: IMLoggerConfig = IMLoggerConfig(),
        databaseConfig: IMDatabaseConfig = IMDatabaseConfig(),
        timeout: TimeInterval = 30,
        transportType: IMTransportType = .webSocket,
        enableSmartSwitch: Bool = false,
        transportConfig: IMTransportConfig? = nil
    ) {
        self.apiURL = apiURL
        self.imURL = imURL
        self.logConfig = logConfig
        self.databaseConfig = databaseConfig
        self.timeout = timeout
        self.transportType = transportType
        self.enableSmartSwitch = enableSmartSwitch
        self.transportConfig = transportConfig
    }
}

/// 连接监听器
public protocol IMConnectionListener: AnyObject {
    /// 连接状态改变
    func onConnectionStateChanged(_ state: IMConnectionState)
    
    /// 连接成功
    func onConnected()
    
    /// 连接断开
    func onDisconnected(error: Error?)
    
    /// 正在重连
    func onReconnecting()
    
    /// Token 即将过期
    func onTokenWillExpire()
    
    /// Token 已过期
    func onTokenExpired()
    
    /// 网络状态改变
    func onNetworkStatusChanged(_ status: IMNetworkStatus)
    
    /// 网络已连接（从断开到连接）
    func onNetworkConnected()
    
    /// 网络已断开
    func onNetworkDisconnected()
}

public extension IMConnectionListener {
    func onConnectionStateChanged(_ state: IMConnectionState) {}
    func onConnected() {}
    func onDisconnected(error: Error?) {}
    func onReconnecting() {}
    func onTokenWillExpire() {}
    func onTokenExpired() {}
    func onNetworkStatusChanged(_ status: IMNetworkStatus) {}
    func onNetworkConnected() {}
    func onNetworkDisconnected() {}
}

/// IM Client - SDK 主管理器
public final class IMClient {
    
    // MARK: - Singleton
    
    public static let shared = IMClient()
    
    // MARK: - Properties
    
    private var config: IMConfig?
    private var currentUserID: String?
    private var currentToken: String?
    private var connectionState: IMConnectionState = .disconnected
    
    // 核心组件
    private var httpManager: IMHTTPManager?
    private var databaseManager: IMDatabaseProtocol?
    private var networkMonitor: IMNetworkMonitor
    
    // 传输层（新架构）
    private var transport: IMTransportProtocol?  // 单一传输层
    private var transportSwitcher: IMTransportSwitcher?  // 协议切换器（智能切换时使用）
    private var messageEncoder: IMMessageEncoder  // 消息编解码器
    private var messageRouter: IMMessageRouter  // 消息路由器
    
    // 业务管理器
    public private(set) var messageManager: IMMessageManager!
    public private(set) var messageSyncManager: IMMessageSyncManager!
    public private(set) var userManager: IMUserManager!
    public private(set) var conversationManager: IMConversationManager!
    public private(set) var groupManager: IMGroupManager!
    public private(set) var friendManager: IMFriendManager!
    public private(set) var typingManager: IMTypingManager!
    
    // 监听器
    private var connectionListeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 待处理的断开错误（用于传递断开原因）
    private var pendingDisconnectError: Error?
    private let disconnectErrorLock = NSLock()
    
    // 注意：心跳由 WebSocket 层的 Ping/Pong 机制处理，不需要应用层心跳
    
    // MARK: - Initialization
    
    private init() {
        self.networkMonitor = IMNetworkMonitor()
        self.messageEncoder = IMMessageEncoder()
        self.messageRouter = IMMessageRouter()
        
        IMLogger.shared.info("IM SDK Version: \(IMSDKVersion.version)")
        IMLogger.shared.info("Transport Layer: WebSocket + TCP dual protocol")
    }
    
    // MARK: - Initialize
    
    /// 初始化 SDK
    /// - Parameter config: SDK 配置
    /// - Throws: 初始化错误
    public func initialize(config: IMConfig) throws {
        guard self.config == nil else {
            IMLogger.shared.warning("SDK already initialized")
            return
        }
        
        self.config = config
        
        // 配置日志
        IMLogger.shared.configure(config.logConfig)
        
        // 初始化网络管理器
        self.httpManager = IMHTTPManager(baseURL: config.apiURL, timeout: config.timeout)
        
        // 初始化传输层
        try initializeTransport(config: config)
        
        // 设置网络监听
        networkMonitor.delegate = self
        networkMonitor.startMonitoring()
        
        IMLogger.shared.info("SDK initialized successfully")
    }
    
    /// 初始化传输层
    private func initializeTransport(config: IMConfig) throws {
        // 设置消息路由器
        setupMessageRouter()
        
        // 判断是否启用智能切换
        if config.enableSmartSwitch {
            // 使用协议切换器
            self.transportSwitcher = IMTransportSwitcher(
                initialType: config.transportType,
                url: config.imURL
            )
            setupTransportSwitcherCallbacks()
            self.transport = nil  // 使用 switcher，不直接使用 transport
            
            IMLogger.shared.info("✅ Smart transport switching enabled (initial: \(config.transportType))")
        } else {
            // 使用单一传输层
            let transportConfig = config.transportConfig ?? IMTransportConfig(
                type: config.transportType,
                url: config.imURL
            )
            let newTransport = IMTransportFactory.createTransport(with: transportConfig)
            self.transport = newTransport
            setupTransportCallbacks()
            self.transportSwitcher = nil
            
            IMLogger.shared.info("✅ Using \(config.transportType) transport")
        }
    }
    
    /// 设置传输层回调
    private func setupTransportCallbacks() {
        transport?.onStateChange = { [weak self] state in
            self?.handleTransportStateChange(state)
        }
        
        transport?.onReceive = { [weak self] data in
            self?.handleTransportReceive(data)
        }
        
        transport?.onError = { [weak self] error in
            self?.handleTransportError(error)
        }
    }
    
    /// 设置协议切换器回调
    private func setupTransportSwitcherCallbacks() {
        transportSwitcher?.onStateChange = { [weak self] state in
            self?.handleTransportStateChange(state)
        }
        
        transportSwitcher?.onReceive = { [weak self] data in
            self?.handleTransportReceive(data)
        }
        
        transportSwitcher?.onError = { [weak self] error in
            self?.handleTransportError(error)
        }
        
        transportSwitcher?.onTransportSwitch = { oldType, newType in
            IMLogger.shared.info("🔄 Transport switched: \(oldType) → \(newType)")
        }
    }
    
    /// 设置消息路由器（TCP Protobuf 版本）
    private func setupMessageRouter() {
        // 注册认证响应
        messageRouter.register(command: .authRsp, type: Im_Protocol_AuthResponse.self) { [weak self] response, seq in
            self?.handleTCPAuthResponse(response)
        }
        
        // 注册发送消息响应
        messageRouter.register(command: .sendMsgRsp, type: Im_Protocol_SendMessageResponse.self) { [weak self] response, seq in
            self?.handleTCPSendMessageResponse(response, sequence: seq)
        }
        
        // 注册推送消息
        messageRouter.register(command: .pushMsg, type: Im_Protocol_PushMessage.self) { [weak self] pushMsg, seq in
            self?.handleTCPPushMessage(pushMsg)
        }
        
        // 注册批量消息
        messageRouter.register(command: .batchMsg, type: Im_Protocol_BatchMessages.self) { [weak self] batchMsg, seq in
            self?.handleTCPBatchMessages(batchMsg)
        }
        
        // 注册心跳响应
        messageRouter.register(command: .heartbeatRsp, type: Im_Protocol_HeartbeatResponse.self) { response, seq in
            // 心跳响应由传输层自动处理，这里只记录日志
            IMLogger.shared.debug("Heartbeat received, server time: \(response.serverTime)")
        }
        
        // 注册撤回消息推送
        messageRouter.register(command: .revokeMsgPush, type: Im_Protocol_RevokeMessagePush.self) { [weak self] push, seq in
            self?.handleTCPRevokeMessagePush(push)
        }
        
        // 注册已读回执推送
        messageRouter.register(command: .readReceiptPush, type: Im_Protocol_ReadReceiptPush.self) { [weak self] push, seq in
            self?.handleTCPReadReceiptPush(push)
        }
        
        // 注册输入状态推送
        messageRouter.register(command: .typingStatusPush, type: Im_Protocol_TypingStatusPush.self) { [weak self] push, seq in
            self?.handleTCPTypingStatusPush(push)
        }
        
        // 注册踢出通知
        messageRouter.register(command: .kickOut, type: Im_Protocol_KickOutNotification.self) { [weak self] notification, seq in
            self?.handleTCPKickOut(notification)
        }
    }
    
    // MARK: - Login/Logout
    
    /// 登录
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - token: 认证 Token
    ///   - completion: 完成回调
    public func login(
        userID: String,
        token: String,
        completion: @escaping (Result<IMUser, IMError>) -> Void
    ) {
        guard config != nil else {
            completion(.failure(.notInitialized))
            return
        }
        
        guard connectionState == .disconnected else {
            IMLogger.shared.warning("Already logged in or connecting")
            completion(.failure(.invalidParameter("Already logged in")))
            return
        }
        
        IMLogger.shared.info("Logging in user: \(userID)")
        
        self.currentUserID = userID
        self.currentToken = token
        
        // 初始化数据库（SQLite + WAL）
        do {
            // 直接创建 SQLite 数据库实例
            let enableWAL = config!.databaseConfig.enableWAL
            self.databaseManager = try IMDatabaseManager(userID: userID, enableWAL: enableWAL)
            
            let walStatus = enableWAL ? "with WAL" : "without WAL"
            IMLogger.shared.info("SQLite database initialized successfully \(walStatus)")
        } catch {
            IMLogger.shared.error("Failed to initialize database: \(error)")
            completion(.failure(.databaseError(error.localizedDescription)))
            return
        }
        
        guard let database = databaseManager else {
            completion(.failure(.databaseError("Database not initialized")))
            return
        }
        
        // 初始化业务管理器
        guard let httpManager = httpManager else {
            completion(.failure(.notInitialized))
            return
        }
        
        self.messageManager = IMMessageManager(
            database: database,
            userID: userID
        )
        
        // 设置消息管理器的回调（使用传输层）
        messageManager.onSendData = { [weak self] body, command in
            guard let self = self else { return false }
            
            // 使用 transport 的 sendMessage 方法，由 transport 负责封装
            if let switcher = self.transportSwitcher {
                switcher.sendMessage(body: body, command: command, completion: nil)
                return true
            } else if let transport = self.transport {
                transport.sendMessage(body: body, command: command, completion: nil)
                return true
            } else {
                return false
            }
        }
        
        messageManager.isConnected = { [weak self] in
            guard let self = self else { return false }
            if let switcher = self.transportSwitcher {
                return switcher.isConnected
            } else if let transport = self.transport {
                return transport.isConnected
            } else {
                return false
            }
        }
        
        self.messageSyncManager = IMMessageSyncManager(
            database: database,
            httpManager: httpManager,
            messageManager: messageManager,
            userID: userID
        )
        
        self.userManager = IMUserManager(
            database: database,
            httpManager: httpManager
        )
        
        self.conversationManager = IMConversationManager(
            database: database,
            messageManager: messageManager
        )
        
        self.groupManager = IMGroupManager(
            database: database,
            httpManager: httpManager
        )
        
        self.friendManager = IMFriendManager(
            database: database,
            httpManager: httpManager
        )
        
        self.typingManager = IMTypingManager(
            userID: userID
        )        
        // 设置输入状态管理器的回调（使用传输层）
        typingManager.onSendData = { [weak self] body, command in
            guard let self = self else { return false }
            
            // 使用 transport 的 sendMessage 方法，由 transport 负责封装
            if let switcher = self.transportSwitcher {
                switcher.sendMessage(body: body, command: command, completion: nil)
                return true
            } else if let transport = self.transport {
                transport.sendMessage(body: body, command: command, completion: nil)
                return true
            } else {
                return false
            }
        }

        
        
        // 设置认证 Header
        httpManager.addHeader(name: "Authorization", value: "Bearer \(token)")
        
        // 获取用户信息
        userManager.getUserInfo(userID: userID, forceUpdate: true) { [weak self] result in
            switch result {
            case .success(let user):
                self?.userManager.setCurrentUser(user)
                
                // 连接 WebSocket
                self?.connectWebSocket()
                
                completion(.success(user))
                
            case .failure(let error):
                IMLogger.shared.error("Failed to get user info: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// 登出
    /// - Parameter completion: 完成回调
    public func logout(completion: ((Result<Void, IMError>) -> Void)? = nil) {
        IMLogger.shared.info("Logging out")
        
        // 断开传输层
        transportSwitcher?.disconnect()
        transport?.disconnect()
        
        // 清理数据
        databaseManager?.close()
        
        currentUserID = nil
        currentToken = nil
        connectionState = .disconnected
        
        notifyConnectionListeners { $0.onConnectionStateChanged(.disconnected) }
        
        completion?(.success(()))
    }
    
    // MARK: - Connection
    
    /// 连接传输层
    private func connectTransport() {
        guard let userID = currentUserID, let token = currentToken, let imURL = config?.imURL else { return }
        
        updateConnectionState(.connecting)
        
        // 使用协议切换器或单一传输层
        if let switcher = transportSwitcher {
            switcher.connect(url: imURL, userID: userID, token: token) { [weak self] result in
                switch result {
                case .success:
                    IMLogger.shared.info("✅ Transport connected")
                case .failure(let error):
                    IMLogger.shared.error("❌ Transport connection failed: \(error)")
                }
            }
        } else if let transport = transport {
            transport.connect(url: imURL, userID: userID, token: token) { [weak self] result in
                switch result {
                case .success:
                    IMLogger.shared.info("✅ Transport connected")
                case .failure(let error):
                    IMLogger.shared.error("❌ Transport connection failed: \(error)")
                }
            }
        }
    }
    
    /// 连接 WebSocket（兼容旧代码）
    private func connectWebSocket() {
        connectTransport()
    }
    
    /// 处理连接断开
    private func handleDisconnected(error: Error?) {
        IMLogger.shared.warning("WebSocket disconnected: \(error?.localizedDescription ?? "unknown")")
        
        updateConnectionState(.disconnected)
        
        notifyConnectionListeners { $0.onDisconnected(error: error) }
    }
    
    /// 处理错误
    private func handleError(_ error: Error) {
        IMLogger.shared.error("WebSocket error: \(error)")
    }
    
    /// 更新连接状态
    private func updateConnectionState(_ state: IMConnectionState) {
        guard connectionState != state else { return }
        
        connectionState = state
        notifyConnectionListeners { $0.onConnectionStateChanged(state) }
    }
    
    // MARK: - Sync
    
    // 注意：心跳机制由 WebSocket 层的 Ping/Pong 处理
    // WebSocketManager 每 30 秒自动发送 Ping，并检测 Pong 响应
    // 如果连接异常（未收到 Pong），会自动触发重连
    
    /// 同步离线消息
    private func syncOfflineMessages() {
        IMLogger.shared.info("Syncing offline messages...")
        
        // 使用消息同步管理器进行增量同步
        messageSyncManager?.startSync { result in
            switch result {
            case .success:
                IMLogger.shared.info("✅ Offline messages synced successfully")
            case .failure(let error):
                IMLogger.shared.error("❌ Failed to sync offline messages: \(error)")
            }
        }
    }
    
    /// 手动触发消息同步（供外部调用）
    /// - Parameter completion: 完成回调
    public func syncMessages(completion: IMSyncCompletionHandler? = nil) {
        guard messageSyncManager != nil else {
            completion?(.failure(IMError.notLoggedIn))
            return
        }
        
        messageSyncManager.startSync(completion: completion)
    }
    
    // MARK: - Connection Listener
    
    /// 添加连接监听器
    public func addConnectionListener(_ listener: IMConnectionListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        connectionListeners.add(listener)
    }
    
    /// 移除连接监听器
    public func removeConnectionListener(_ listener: IMConnectionListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        connectionListeners.remove(listener)
    }
    
    /// 通知所有连接监听器
    private func notifyConnectionListeners(_ block: @escaping (IMConnectionListener) -> Void) {
        listenerLock.lock()
        let allListeners = connectionListeners.allObjects.compactMap { $0 as? IMConnectionListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Message Listener Shortcuts
    
    /// 添加消息监听器
    public func addMessageListener(_ listener: IMMessageListener) {
        messageManager?.addListener(listener)
    }
    
    /// 移除消息监听器
    public func removeMessageListener(_ listener: IMMessageListener) {
        messageManager?.removeListener(listener)
    }
    
    // MARK: - Conversation Listener Shortcuts
    
    /// 添加会话监听器
    public func addConversationListener(_ listener: IMConversationListener) {
        conversationManager?.addListener(listener)
    }
    
    /// 移除会话监听器
    public func removeConversationListener(_ listener: IMConversationListener) {
        conversationManager?.removeListener(listener)
    }
    
    // MARK: - User Listener Shortcuts
    
    /// 添加用户监听器
    public func addUserListener(_ listener: IMUserListener) {
        userManager?.addListener(listener)
    }
    
    /// 移除用户监听器
    public func removeUserListener(_ listener: IMUserListener) {
        userManager?.removeListener(listener)
    }
    
    // MARK: - Group Listener Shortcuts
    
    /// 添加群组监听器
    public func addGroupListener(_ listener: IMGroupListener) {
        groupManager?.addListener(listener)
    }
    
    /// 移除群组监听器
    public func removeGroupListener(_ listener: IMGroupListener) {
        groupManager?.removeListener(listener)
    }
    
    // MARK: - Friend Listener Shortcuts
    
    /// 添加好友监听器
    public func addFriendListener(_ listener: IMFriendListener) {
        friendManager?.addListener(listener)
    }
    
    /// 移除好友监听器
    public func removeFriendListener(_ listener: IMFriendListener) {
        friendManager?.removeListener(listener)
    }
    
    // MARK: - Status
    
    /// 是否已初始化
    public var isInitialized: Bool {
        return config != nil
    }
    
    /// 是否已登录
    public var isLoggedIn: Bool {
        return currentUserID != nil
    }
    
    /// 是否已连接
    public var isConnected: Bool {
        return connectionState == .connected
    }
    
    /// 获取当前连接状态
    public func getConnectionState() -> IMConnectionState {
        return connectionState
    }
    
    /// 获取当前用户 ID
    public func getCurrentUserID() -> String? {
        return currentUserID
    }
    
    /// 获取 SDK 版本
    public func getSDKVersion() -> String {
        return IMSDKVersion.version
    }
    
    // MARK: - Network Status
    
    /// 获取当前网络状态
    public var networkStatus: IMNetworkStatus {
        return networkMonitor.currentStatus
    }
    
    /// 网络是否可用
    public var isNetworkAvailable: Bool {
        return networkMonitor.isNetworkAvailable
    }
    
    /// 是否是 WiFi
    public var isWiFi: Bool {
        return networkMonitor.isWiFi
    }
    
    /// 是否是蜂窝数据
    public var isCellular: Bool {
        return networkMonitor.isCellular
    }
    
    // MARK: - Transport Layer Handlers（新传输层处理方法）
    
    /// 处理传输层状态变化
    private func handleTransportStateChange(_ state: IMTransportState) {
        switch state {
        case .connected:
            handleTransportConnected()
        case .disconnected:
            handleTransportDisconnected()
        case .connecting:
            updateConnectionState(.connecting)
        case .reconnecting:
            updateConnectionState(.connecting)
            notifyConnectionListeners { $0.onReconnecting() }
        case .disconnecting:
            break
        }
    }
    
    /// 处理传输层连接成功
    private func handleTransportConnected() {
        IMLogger.shared.info("Transport connected")
        
        updateConnectionState(.connected)
        
        // 通知消息管理器传输层已重连（重新发送未确认的消息）
        // 注：无论首次连接还是重连，都调用此方法
        // 如果队列为空，此方法不会有任何副作用
        messageManager?.handleTransportReconnected()
        
        // 同步离线消息（startSync 会自动从本地最大 seq 开始增量同步）
        syncOfflineMessages()
        
        notifyConnectionListeners { $0.onConnected() }
    }
    
    /// 处理传输层断开连接
    private func handleTransportDisconnected() {
        IMLogger.shared.warning("Transport disconnected")
        updateConnectionState(.disconnected)
        
        // 检查是否有待处理的断开错误（比如认证失败）
        disconnectErrorLock.lock()
        let error = pendingDisconnectError
        pendingDisconnectError = nil  // 清空
        disconnectErrorLock.unlock()
        
        notifyConnectionListeners { $0.onDisconnected(error: error) }
    }
    
    /// 处理传输层接收数据
    private func handleTransportReceive(_ data: Data) {
        // 根据传输层类型选择不同的路由方式
        guard let currentTransport = transport ?? transportSwitcher?.currentTransport else {
            IMLogger.shared.error("No transport available")
            return
        }
        
        switch currentTransport.transportType {
        case .tcp:
            // TCP 传输：data 是 IMPacket 格式（header + protobuf body）
            // IMMessageRouter 会解码 IMPacket
        messageRouter.route(data: data)
            
        case .webSocket:
            // WebSocket 传输：data 是纯 Protobuf body
            // 需要先解析 Protobuf 获取 command 和 sequence
            routeWebSocketMessage(data)
        }
    }
    
    /// 路由 WebSocket 消息（使用 Protobuf WebSocketMessage）
    private func routeWebSocketMessage(_ data: Data) {
        do {
            // 1. 使用 Protobuf 解码 WebSocket 消息
            let wsMessage = try Im_Protocol_WebSocketMessage(serializedData: data)
            
            IMLogger.shared.debug("WebSocket message received: command=\(wsMessage.command), seq=\(wsMessage.sequence)")
            
            // 2. 根据 command 路由到不同的处理器
            switch wsMessage.command {
            case .cmdPushMsg:
                // 推送消息
                handleWebSocketPushMessage(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdAuthRsp:
                // 认证响应
                handleWebSocketAuthResponse(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdHeartbeatRsp:
                // 心跳响应
                handleWebSocketHeartbeatResponse(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdBatchMsg:
                // 批量消息
                handleWebSocketBatchMessages(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdRevokeMsgPush:
                // 撤回消息推送
                handleWebSocketRevokeMessage(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdReadReceiptPush:
                // 已读回执推送
                handleWebSocketReadReceipt(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdTypingStatusPush:
                // 输入状态推送
                handleWebSocketTypingStatus(wsMessage.body, sequence: wsMessage.sequence)
                
            case .cmdKickOut:
                // 踢出通知
                handleWebSocketKickOut(wsMessage.body)
                
            case .cmdSendMsgRsp:
                // 消息发送响应（ACK）
                handleWebSocketSendMessageResponse(wsMessage.body, sequence: wsMessage.sequence)
            
            default:
                IMLogger.shared.warning("Unhandled WebSocket command: \(wsMessage.command)")
            }
            
        } catch {
            IMLogger.shared.error("Failed to decode WebSocket message: \(error)")
            // 尝试兼容旧格式（如果有的话）
        }
    }
    
    // MARK: - WebSocket Message Handlers
    
    private func handleWebSocketPushMessage(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析推送消息
            let pushMsg = try Im_Protocol_PushMessage(serializedData: body)
            
            IMLogger.shared.debug("Received push message: id=\(pushMsg.messageID), seq=\(pushMsg.seq)")
            
            // 转换为 IMMessage
            let contentString = String(data: pushMsg.content, encoding: .utf8) ?? ""
            let message = IMMessage()
            message.messageID = pushMsg.messageID
            message.conversationID = pushMsg.conversationID
            message.messageType = IMMessageType(rawValue: Int(pushMsg.messageType)) ?? .text
            message.content = contentString
            message.senderID = pushMsg.senderID
            message.receiverID = pushMsg.receiverID.isEmpty ? "" : pushMsg.receiverID
            message.sendTime = pushMsg.sendTime
            message.status = .sent
            message.seq = pushMsg.seq
            message.direction = .receive
            
            // 传递给消息管理器处理（会自动通知监听器）
            messageManager?.handleReceivedMessage(message)
            
        } catch {
            IMLogger.shared.error("Failed to decode push message: \(error)")
        }
    }
    
    /// 处理消息发送响应（ACK）
    private func handleWebSocketSendMessageResponse(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析发送响应
            let sendRsp = try Im_Protocol_SendMessageResponse(serializedData: body)
            
            IMLogger.shared.debug("Received send message response: messageID=\(sendRsp.messageID), errorCode=\(sendRsp.errorCode), seq=\(sendRsp.seq)")
            
            if sendRsp.errorCode == .errSuccess {
                // 发送成功，通知消息管理器
                messageManager?.handleMessageAck(messageID: sendRsp.messageID, status: .sent)
                IMLogger.shared.info("✅ Message sent successfully: \(sendRsp.messageID)")
            } else {
                // 发送失败
                IMLogger.shared.error("❌ Message send failed: \(sendRsp.messageID), error: \(sendRsp.errorMsg)")
                messageManager?.handleMessageAck(messageID: sendRsp.messageID, status: .failed)
            }
            
        } catch {
            IMLogger.shared.error("Failed to decode send message response: \(error)")
        }
    }
    
    private func handleWebSocketAuthResponse(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析认证响应
            let authRsp = try Im_Protocol_AuthResponse(serializedData: body)
            
            if authRsp.errorCode == .errSuccess {
                IMLogger.shared.info("✅ WebSocket authentication succeeded, serverMaxSeq=\(authRsp.maxSeq)")
                
                // 注意：不需要在这里更新连接状态或触发同步
                // 因为 handleTransportConnected() 已经处理了这些逻辑
                
        } else {
                IMLogger.shared.error("❌ WebSocket authentication failed: \(authRsp.errorMsg)")
                
                // 认证失败，保存错误并主动断开连接
                // 断开回调会使用这个错误通知监听器
                disconnectErrorLock.lock()
                pendingDisconnectError = IMError.authenticationFailed(authRsp.errorMsg)
                disconnectErrorLock.unlock()
                
                // 主动断开传输层连接
                transportSwitcher?.disconnect()
                transport?.disconnect()
            }
            
        } catch {
            IMLogger.shared.error("Failed to decode auth response: \(error)")
        }
    }
    
    private func handleWebSocketHeartbeatResponse(_ body: Data, sequence: UInt32) {
        do {
            let heartbeatRsp = try Im_Protocol_HeartbeatResponse(serializedData: body)
            
            // 更新服务器时间差
            let serverTime = heartbeatRsp.serverTime
            let localTime = Int64(Date().timeIntervalSince1970 * 1000)
            let timeDiff = serverTime - localTime
            
            IMLogger.shared.verbose("Heartbeat response: server_time=\(serverTime), time_diff=\(timeDiff)ms")
            
        } catch {
            // 心跳响应解析失败不是致命错误，记录日志即可
            IMLogger.shared.debug("Failed to decode heartbeat response: \(error)")
        }
    }
    
    private func handleWebSocketBatchMessages(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析批量消息
            let batchMsg = try Im_Protocol_BatchMessages(serializedData: body)
            
            IMLogger.shared.info("Received batch messages: count=\(batchMsg.messages.count)")
            
            // 批量处理消息
            var imMessages: [IMMessage] = []
            for pbMsg in batchMsg.messages {
                let contentString = String(data: pbMsg.content, encoding: .utf8) ?? ""
                let message = IMMessage()
                message.messageID = pbMsg.messageID
                message.conversationID = pbMsg.conversationID
                message.messageType = IMMessageType(rawValue: Int(pbMsg.messageType)) ?? .text
                message.content = contentString
                message.senderID = pbMsg.senderID
                message.receiverID = pbMsg.receiverID.isEmpty ? "" : pbMsg.receiverID
                message.sendTime = pbMsg.sendTime
                message.status = .sent
                message.seq = pbMsg.seq
                message.direction = .receive
                imMessages.append(message)
            }
            
            // 批量处理消息（逐个调用 handleReceivedMessage，它会保存并通知监听器）
            if !imMessages.isEmpty {
                for message in imMessages {
                messageManager?.handleReceivedMessage(message)
                }
                IMLogger.shared.info("Batch messages processed: \(imMessages.count) messages")
            }
            
        } catch {
            IMLogger.shared.error("Failed to decode batch messages: \(error)")
        }
    }
    
    private func handleWebSocketRevokeMessage(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析撤回消息推送
            let revokeMsg = try Im_Protocol_RevokeMessagePush(serializedData: body)
            
            IMLogger.shared.info("Received revoke message: id=\(revokeMsg.messageID)")
            
            // 调用消息管理器处理撤回（会自动更新数据库、通知监听器）
            messageManager?.handleRevokeNotification(
                messageID: revokeMsg.messageID,
                revokerID: revokeMsg.revokedBy,
                revokeTime: revokeMsg.revokedTime
            )
            
        } catch {
            IMLogger.shared.error("Failed to decode revoke message: \(error)")
        }
    }
    
    private func handleWebSocketReadReceipt(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析已读回执推送
            let readReceipt = try Im_Protocol_ReadReceiptPush(serializedData: body)
            
            IMLogger.shared.info("Received read receipt: conversation=\(readReceipt.conversationID), count=\(readReceipt.messageIds.count)")
            
            // 调用消息管理器处理已读回执
            for messageID in readReceipt.messageIds {
                do {
                    try databaseManager?.updateMessageReadStatus(
                        messageID: messageID,
                        readerID: readReceipt.userID,
                        readTime: readReceipt.readTime
                    )
            } catch {
                IMLogger.shared.error("Failed to update read receipt: \(error)")
            }
            }
            
        } catch {
            IMLogger.shared.error("Failed to decode read receipt: \(error)")
        }
    }
    
    private func handleWebSocketTypingStatus(_ body: Data, sequence: UInt32) {
        do {
            // 使用 Protobuf 解析输入状态推送
            let typingStatus = try Im_Protocol_TypingStatusPush(serializedData: body)
            
            let status: IMTypingStatus = typingStatus.status == 1 ? .typing : .stop
            
            IMLogger.shared.debug("Received typing status: user=\(typingStatus.userID), status=\(status)")
            
            // 通知输入状态管理器
        typingManager?.handleTypingPacket(
                conversationID: typingStatus.conversationID,
                userID: typingStatus.userID,
            status: status
        )
            
        } catch {
            IMLogger.shared.error("Failed to decode typing status: \(error)")
        }
    }
    
    private func handleWebSocketKickOut(_ body: Data) {
        do {
            // 使用 Protobuf 解析踢出通知
            let kickOut = try Im_Protocol_KickOutNotification(serializedData: body)
            
            let reasonStr = kickOut.reason == 1 ? "其他设备登录" : "账号异常"
            IMLogger.shared.warning("⚠️ Kicked out by server: reason=\(reasonStr), message=\(kickOut.message)")
            
            // 保存错误并主动断开连接
            disconnectErrorLock.lock()
            pendingDisconnectError = IMError.kickedOut(kickOut.message)
            disconnectErrorLock.unlock()
            
            // 主动断开传输层连接
            transportSwitcher?.disconnect()
            transport?.disconnect()
            
        } catch {
            IMLogger.shared.error("Failed to decode kick out notification: \(error)")
            
            // 解析失败也断开连接
            transportSwitcher?.disconnect()
            transport?.disconnect()
        }
    }
    
    /// 处理传输层错误
    private func handleTransportError(_ error: IMTransportError) {
        IMLogger.shared.error("Transport error: \(error)")
        
        switch error {
        case .packetLoss(let expected, let received, let gap):
            // 检测到丢包
            handlePacketLoss(expected: expected, received: received, gap: gap)
            
        case .maxReconnectAttemptsReached:
            // 达到最大重连次数，通知用户
            IMLogger.shared.error("❌ Max reconnect attempts reached, please check network connection")
            notifyConnectionListeners { $0.onDisconnected(error: error) }
            
        default:
            // 其他错误
            break
        }
    }
    
    /// 处理丢包事件
    private func handlePacketLoss(expected: UInt32, received: UInt32, gap: UInt32) {
        IMLogger.shared.warning("📉 Packet loss detected in IMClient: expected=\(expected), received=\(received), gap=\(gap)")
        
        // 根据丢包严重程度采取不同策略
        if gap > 3 {
            // 中等或严重丢包：主动触发增量同步（不等待重连）
            IMLogger.shared.warning("⚠️ Moderate/severe packet loss (gap=\(gap)), triggering incremental sync")
            triggerIncrementalSync()
        } else {
            // 轻微丢包：只记录，依赖 ACK 超时重传
            IMLogger.shared.info("ℹ️ Minor packet loss (gap=\(gap)), relying on ACK retry mechanism")
        }
    }
    
    /// 主动触发增量同步（不等待重连）
    private func triggerIncrementalSync() {
        guard let database = databaseManager else {
            IMLogger.shared.error("Database not initialized, cannot trigger sync")
            return
        }
        
        // 获取本地最大序列号
        let localMaxSeq = database.getMaxSeq()
        
        IMLogger.shared.info("🔄 Triggering incremental sync from seq: \(localMaxSeq + 1)")
        
        // 触发增量同步
        messageSyncManager?.sync(fromSeq: localMaxSeq + 1) { result in
            switch result {
            case .success:
                IMLogger.shared.info("✅ Incremental sync completed (triggered by packet loss)")
            case .failure(let error):
                IMLogger.shared.error("❌ Incremental sync failed: \(error)")
            }
        }
    }
    
    /// 处理认证响应
    // MARK: - Public API for Transport Management（传输层管理公共 API）
    
    /// 切换传输层协议
    /// - Parameters:
    ///   - type: 目标传输层类型
    ///   - completion: 完成回调
    public func switchTransport(to type: IMTransportType, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let switcher = transportSwitcher else {
            completion(.failure(IMError.invalidParameter("Smart switch not enabled")))
            return
        }
        
        switcher.switchTo(type: type, completion: completion)
    }
    
    /// 智能切换传输层（根据网络质量）
    /// - Parameter completion: 完成回调
    public func smartSwitchTransport(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let switcher = transportSwitcher else {
            completion(.failure(IMError.invalidParameter("Smart switch not enabled")))
            return
        }
        
        // 判断当前网络质量
        let quality = detectNetworkQuality()
        switcher.smartSwitch(quality: quality, completion: completion)
    }
    
    /// 检测网络质量
    private func detectNetworkQuality() -> NetworkQuality {
        // 根据当前网络状态判断
        switch networkStatus {
        case .wifi:
            return .good
        case .cellular:
            // TODO: 可以根据信号强度进一步判断
            return .poor
        case .unavailable:
            return .veryPoor
        case .unknown:
            return .poor
        }
    }
    
    /// 获取当前传输层类型
    public func getCurrentTransportType() -> IMTransportType? {
        if let switcher = transportSwitcher {
            return switcher.currentTransportType
        } else if let transport = transport {
            return transport.transportType
        } else {
            return nil
        }
    }
    
    /// 获取传输层统计信息
    public func getTransportStats() -> IMPacketCodec.Stats {
        return messageEncoder.packetStats
    }
}

// MARK: - IMNetworkMonitorDelegate

extension IMClient: IMNetworkMonitorDelegate {
    
    public func networkStatusDidChange(_ status: IMNetworkStatus) {
        IMLogger.shared.info("📶 Network status changed: \(status)")
        
        // 通知所有监听器
        notifyConnectionListeners { listener in
            listener.onNetworkStatusChanged(status)
        }
    }
    
    public func networkDidConnect() {
        IMLogger.shared.info("📶 Network connected: \(networkMonitor.currentStatus)")
        
        // 通知监听器
        notifyConnectionListeners { listener in
            listener.onNetworkConnected()
        }
        
        // 如果 WebSocket 断开，自动重连
        if connectionState == .disconnected, isLoggedIn {
            IMLogger.shared.info("Auto reconnecting WebSocket due to network recovery...")
            connectWebSocket()
        }
    }
    
    public func networkDidDisconnect() {
        IMLogger.shared.warning("📶 Network disconnected")
        
        // 通知监听器
        notifyConnectionListeners { listener in
            listener.onNetworkDisconnected()
        }
        
        // 更新连接状态
        if connectionState != .disconnected {
            updateConnectionState(.disconnected)
        }
    }
    
    // MARK: - TCP Message Handlers (Protobuf)
    
    /// 处理 TCP 认证响应
    private func handleTCPAuthResponse(_ response: Im_Protocol_AuthResponse) {
        if response.errorCode == .errSuccess {
            IMLogger.shared.info("✅ TCP authentication succeeded")
        } else {
            IMLogger.shared.error("❌ TCP authentication failed: \(response.errorMsg)")
        }
    }
    
    /// 处理 TCP 发送消息响应
    private func handleTCPSendMessageResponse(_ response: Im_Protocol_SendMessageResponse, sequence: UInt32) {
        if response.errorCode == .errSuccess {
            IMLogger.shared.debug("Message sent successfully: \(response.messageID)")
            messageManager?.handleMessageAck(messageID: response.messageID, status: .sent)
        } else {
            IMLogger.shared.error("Message send failed: \(response.errorMsg)")
        }
    }
    
    /// 处理 TCP 推送消息
    private func handleTCPPushMessage(_ pushMsg: Im_Protocol_PushMessage) {
        let contentString = String(data: pushMsg.content, encoding: .utf8) ?? ""
        let message = IMMessage()
        message.messageID = pushMsg.messageID
        message.conversationID = pushMsg.conversationID
        message.messageType = IMMessageType(rawValue: Int(pushMsg.messageType)) ?? .text
        message.content = contentString
        message.senderID = pushMsg.senderID
        message.receiverID = pushMsg.receiverID.isEmpty ? "" : pushMsg.receiverID
        message.sendTime = pushMsg.sendTime
        message.status = .sent
        message.seq = pushMsg.seq
        message.direction = .receive
        
        // 传递给消息管理器处理（会自动通知监听器）
        messageManager?.handleReceivedMessage(message)
    }
    
    /// 处理 TCP 批量消息
    private func handleTCPBatchMessages(_ batchMsg: Im_Protocol_BatchMessages) {
        IMLogger.shared.info("TCP received batch messages: \(batchMsg.messages.count)")
        
        for pbMsg in batchMsg.messages {
            handleTCPPushMessage(pbMsg)
        }
    }
    
    /// 处理 TCP 撤回消息推送
    private func handleTCPRevokeMessagePush(_ push: Im_Protocol_RevokeMessagePush) {
        // 调用消息管理器处理撤回（会自动更新数据库、通知监听器）
        messageManager?.handleRevokeNotification(
            messageID: push.messageID,
            revokerID: push.revokedBy,
            revokeTime: push.revokedTime
        )
    }
    
    /// 处理 TCP 已读回执推送
    private func handleTCPReadReceiptPush(_ push: Im_Protocol_ReadReceiptPush) {
        for messageID in push.messageIds {
            do {
                try databaseManager?.updateMessageReadStatus(
                    messageID: messageID,
                    readerID: push.userID,
                    readTime: push.readTime
                )
            } catch {
                IMLogger.shared.error("Failed to update TCP read receipt: \(error)")
            }
        }
    }
    
    /// 处理 TCP 输入状态推送
    private func handleTCPTypingStatusPush(_ push: Im_Protocol_TypingStatusPush) {
        let status: IMTypingStatus = push.status == 1 ? .typing : .stop
        typingManager?.handleTypingPacket(
            conversationID: push.conversationID,
            userID: push.userID,
            status: status
        )
    }
    
    /// 处理 TCP 踢出通知
    private func handleTCPKickOut(_ notification: Im_Protocol_KickOutNotification) {
        let reasonStr = notification.reason == 1 ? "其他设备登录" : "账号异常"
        IMLogger.shared.warning("⚠️ TCP kicked out: reason=\(reasonStr), message=\(notification.message)")
        
        // 保存错误并主动断开连接
        disconnectErrorLock.lock()
        pendingDisconnectError = IMError.kickedOut(notification.message)
        disconnectErrorLock.unlock()
        
        // 主动断开传输层连接
        transportSwitcher?.disconnect()
        transport?.disconnect()
    }
}


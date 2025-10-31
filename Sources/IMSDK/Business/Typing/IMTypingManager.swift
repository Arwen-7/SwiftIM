/// IMTypingManager - 输入状态管理器
/// 管理"正在输入..."的状态同步

import Foundation

// MARK: - 输入状态枚举

/// 输入状态
public enum IMTypingStatus: Int {
    case stop = 0       // 停止输入
    case typing = 1     // 正在输入
}

// MARK: - 输入状态模型

/// 输入状态
public struct IMTypingState {
    public let conversationID: String
    public let userID: String
    public let status: IMTypingStatus
    public let timestamp: Int64
    
    public init(conversationID: String, userID: String, status: IMTypingStatus, timestamp: Int64) {
        self.conversationID = conversationID
        self.userID = userID
        self.status = status
        self.timestamp = timestamp
    }
}

// MARK: - 输入状态监听器

/// 输入状态监听器
public protocol IMTypingListener: AnyObject {
    /// 输入状态改变
    /// - Parameter state: 输入状态
    func onTypingStateChanged(_ state: IMTypingState)
}

// MARK: - 输入状态管理器

/// 输入状态管理器
/// 负责发送和接收"正在输入..."状态
public class IMTypingManager {
    
    // MARK: - Properties
    
    /// 当前用户 ID
    private let userID: String
    
    /// 监听器列表
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    /// 发送数据回调（由 IMClient 设置）
    /// - Parameters:
    ///   - body: Protobuf 消息体
    ///   - command: 命令类型（用于 TCP 包头）
    /// - Returns: 是否成功提交到传输层
    internal var onSendData: ((Data, IMCommandType) -> Bool)?
    
    /// 发送记录（conversationID -> 最后发送时间）
    private var sendingRecords: [String: TimeInterval] = [:]
    private let sendingLock = NSLock()
    
    /// 自动停止定时器（conversationID -> Timer）
    private var stopTimers: [String: Timer] = [:]
    private let timerLock = NSLock()
    
    /// 接收状态（conversationID -> userID -> 超时时间）
    private var receivingStates: [String: [String: TimeInterval]] = [:]
    private let receivingLock = NSLock()
    
    /// 超时检查定时器
    private var timeoutTimer: Timer?
    
    // MARK: - Configuration
    
    /// 发送间隔（秒）- 防抖动，避免频繁发送
    public var sendInterval: TimeInterval = 5.0
    
    /// 自动停止延迟（秒）- 停止输入多久后自动发送停止状态
    public var stopDelay: TimeInterval = 3.0
    
    /// 接收超时（秒）- 超过此时间未收到更新则自动清除状态
    public var receiveTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    /// 初始化
    /// - Parameter userID: 当前用户 ID
    public init(userID: String) {
        self.userID = userID
        startTimeoutTimer()
        
        IMLogger.shared.info("Typing manager initialized for user: \(userID)")
    }
    
    deinit {
        stopAllTimers()
        IMLogger.shared.info("Typing manager deinitialized")
    }
    
    // MARK: - Public Methods - 发送状态
    
    /// 发送"正在输入"状态
    /// - Parameter conversationID: 会话 ID
    public func sendTyping(conversationID: String) {
        sendingLock.lock()
        defer { sendingLock.unlock() }
        
        let now = Date().timeIntervalSince1970
        
        // 检查防抖动：5秒内不重复发送
        if let lastSendTime = sendingRecords[conversationID],
           now - lastSendTime < sendInterval {
            IMLogger.shared.verbose("Typing event ignored due to debounce (interval: \(sendInterval)s)")
            return
        }
        
        // 更新发送记录
        sendingRecords[conversationID] = now
        
        // 发送输入状态
        sendTypingStatus(.typing, conversationID: conversationID)
        
        // 启动自动停止定时器（3秒后自动发送停止）
        startStopTimer(for: conversationID)
        
        IMLogger.shared.verbose("Sent typing status for conversation: \(conversationID)")
    }
    
    /// 发送"停止输入"状态
    /// - Parameter conversationID: 会话 ID
    public func stopTyping(conversationID: String) {
        sendingLock.lock()
        defer { sendingLock.unlock() }
        
        // 取消自动停止定时器
        cancelStopTimer(for: conversationID)
        
        // 发送停止状态
        sendTypingStatus(.stop, conversationID: conversationID)
        
        // 清除发送记录
        sendingRecords.removeValue(forKey: conversationID)
        
        IMLogger.shared.verbose("Sent stop typing for conversation: \(conversationID)")
    }
    
    // MARK: - Public Methods - 查询状态
    
    /// 获取会话中正在输入的用户列表
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 正在输入的用户 ID 列表
    public func getTypingUsers(in conversationID: String) -> [String] {
        receivingLock.lock()
        defer { receivingLock.unlock() }
        
        let now = Date().timeIntervalSince1970
        
        guard let users = receivingStates[conversationID] else {
            return []
        }
        
        // 返回未超时的用户列表
        return users.filter { $0.value > now }.map { $0.key }
    }
    
    /// 检查指定用户是否正在输入
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - conversationID: 会话 ID
    /// - Returns: 是否正在输入
    public func isUserTyping(userID: String, in conversationID: String) -> Bool {
        let typingUsers = getTypingUsers(in: conversationID)
        return typingUsers.contains(userID)
    }
    
    // MARK: - Listener Management
    
    /// 添加监听器
    /// - Parameter listener: 监听器
    public func addListener(_ listener: IMTypingListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
        
        IMLogger.shared.verbose("Typing listener added")
    }
    
    /// 移除监听器
    /// - Parameter listener: 监听器
    public func removeListener(_ listener: IMTypingListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
        
        IMLogger.shared.verbose("Typing listener removed")
    }
    
    // MARK: - Internal Methods - 处理接收
    
    /// 处理接收到的输入状态包
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - status: 输入状态
    internal func handleTypingPacket(conversationID: String, userID: String, status: IMTypingStatus) {
        // 忽略自己的状态（不显示自己的"正在输入"）
        guard userID != self.userID else {
            IMLogger.shared.verbose("Ignored own typing status")
            return
        }
        
        receivingLock.lock()
        
        let now = Date().timeIntervalSince1970
        
        if status == .typing {
            // 正在输入：记录超时时间
            if receivingStates[conversationID] == nil {
                receivingStates[conversationID] = [:]
            }
            receivingStates[conversationID]?[userID] = now + receiveTimeout
            
            IMLogger.shared.info("User \(userID) is typing in \(conversationID)")
            
        } else {
            // 停止输入：移除记录
            receivingStates[conversationID]?.removeValue(forKey: userID)
            if receivingStates[conversationID]?.isEmpty == true {
                receivingStates.removeValue(forKey: conversationID)
            }
            
            IMLogger.shared.info("User \(userID) stopped typing in \(conversationID)")
        }
        
        receivingLock.unlock()
        
        // 构造状态并通知监听器
        let state = IMTypingState(
            conversationID: conversationID,
            userID: userID,
            status: status,
            timestamp: Int64(now * 1000)
        )
        
        notifyListeners(state)
    }
    
    // MARK: - Private Methods - 发送
    
    /// 发送输入状态到服务器
    /// - Parameters:
    ///   - status: 输入状态
    ///   - conversationID: 会话 ID
    private func sendTypingStatus(_ status: IMTypingStatus, conversationID: String) {
        guard let onSendData = onSendData else {
            IMLogger.shared.warning("onSendData callback not set, cannot send typing status")
            return
        }
        
        // 使用 Protobuf 编码输入状态请求
        do {
            var typingRequest = Im_Protocol_TypingStatusRequest()
            typingRequest.conversationID = conversationID
            typingRequest.status = Int32(status.rawValue)
            
            let data = try typingRequest.serializedData()
            _ = onSendData(data, .typingStatusReq)
            
            IMLogger.shared.verbose("Sent typing packet: \(status) for \(conversationID)")
        } catch {
            IMLogger.shared.error("Failed to encode typing packet: \(error)")
        }
    }
    
    // MARK: - Private Methods - 定时器管理
    
    /// 启动自动停止定时器
    /// - Parameter conversationID: 会话 ID
    private func startStopTimer(for conversationID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.timerLock.lock()
            defer { self.timerLock.unlock() }
            
            // 取消现有定时器
            self.stopTimers[conversationID]?.invalidate()
            
            // 创建新定时器：stopDelay 秒后自动发送停止状态
            let timer = Timer.scheduledTimer(withTimeInterval: self.stopDelay, repeats: false) { [weak self] _ in
                self?.autoStopTyping(conversationID: conversationID)
            }
            
            self.stopTimers[conversationID] = timer
            
            IMLogger.shared.verbose("Auto-stop timer started for \(conversationID) (\(self.stopDelay)s)")
        }
    }
    
    /// 取消自动停止定时器
    /// - Parameter conversationID: 会话 ID
    private func cancelStopTimer(for conversationID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.timerLock.lock()
            defer { self.timerLock.unlock() }
            
            self.stopTimers[conversationID]?.invalidate()
            self.stopTimers.removeValue(forKey: conversationID)
            
            IMLogger.shared.verbose("Auto-stop timer cancelled for \(conversationID)")
        }
    }
    
    /// 自动停止输入（由定时器触发）
    /// - Parameter conversationID: 会话 ID
    private func autoStopTyping(conversationID: String) {
        sendingLock.lock()
        
        // 发送停止状态
        sendTypingStatus(.stop, conversationID: conversationID)
        
        // 清除记录
        sendingRecords.removeValue(forKey: conversationID)
        
        sendingLock.unlock()
        
        // 清除定时器
        timerLock.lock()
        stopTimers.removeValue(forKey: conversationID)
        timerLock.unlock()
        
        IMLogger.shared.info("Auto-stopped typing for \(conversationID)")
    }
    
    /// 启动超时检查定时器
    private func startTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 每秒检查一次超时
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkTimeout()
            }
            
            IMLogger.shared.verbose("Timeout timer started")
        }
    }
    
    /// 检查并清理超时的状态
    private func checkTimeout() {
        receivingLock.lock()
        
        let now = Date().timeIntervalSince1970
        var expiredStates: [(String, String)] = []  // (conversationID, userID)
        
        // 找出超时的状态
        for (conversationID, users) in receivingStates {
            for (userID, expireTime) in users where expireTime <= now {
                expiredStates.append((conversationID, userID))
            }
        }
        
        // 移除超时的状态
        for (conversationID, userID) in expiredStates {
            receivingStates[conversationID]?.removeValue(forKey: userID)
            if receivingStates[conversationID]?.isEmpty == true {
                receivingStates.removeValue(forKey: conversationID)
            }
        }
        
        receivingLock.unlock()
        
        // 通知超时（状态变为停止）
        for (conversationID, userID) in expiredStates {
            let state = IMTypingState(
                conversationID: conversationID,
                userID: userID,
                status: .stop,
                timestamp: Int64(now * 1000)
            )
            notifyListeners(state)
            
            IMLogger.shared.verbose("Typing timeout: \(userID) in \(conversationID)")
        }
    }
    
    /// 停止所有定时器
    private func stopAllTimers() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.timerLock.lock()
            for timer in self.stopTimers.values {
                timer.invalidate()
            }
            self.stopTimers.removeAll()
            self.timerLock.unlock()
            
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
            
            IMLogger.shared.verbose("All timers stopped")
        }
    }
    
    // MARK: - Private Methods - 通知
    
    /// 通知所有监听器
    /// - Parameter state: 输入状态
    private func notifyListeners(_ state: IMTypingState) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMTypingListener }
        listenerLock.unlock()
        
        // 在主线程通知
        DispatchQueue.main.async {
            for listener in allListeners {
                listener.onTypingStateChanged(state)
            }
        }
    }
}

// MARK: - CustomStringConvertible

extension IMTypingStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stop:
            return "Stop"
        case .typing:
            return "Typing"
        }
    }
}


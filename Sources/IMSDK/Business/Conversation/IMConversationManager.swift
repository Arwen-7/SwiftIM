/// IMConversationManager - 会话管理器
/// 负责会话列表的管理和未读数统计

import Foundation

/// 会话监听器
public protocol IMConversationListener: AnyObject {
    /// 新会话创建
    func onConversationCreated(_ conversation: IMConversation)
    
    /// 会话更新
    func onConversationUpdated(_ conversation: IMConversation)
    
    /// 会话删除
    func onConversationDeleted(_ conversationID: String)
    
    /// 会话未读数改变
    func onUnreadCountChanged(_ conversationID: String, count: Int)
    
    /// 总未读数改变
    func onTotalUnreadCountChanged(_ count: Int)
}

public extension IMConversationListener {
    func onConversationCreated(_ conversation: IMConversation) {}
    func onConversationUpdated(_ conversation: IMConversation) {}
    func onConversationDeleted(_ conversationID: String) {}
    func onUnreadCountChanged(_ conversationID: String, count: Int) {}
    func onTotalUnreadCountChanged(_ count: Int) {}
}

/// 会话管理器
public final class IMConversationManager {
    
    // MARK: - Properties
    
    private let database: IMDatabaseProtocol
    private let messageManager: IMMessageManager
    
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 会话缓存
    private let conversationCache = IMMemoryCache<IMConversation>(countLimit: 200)
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, messageManager: IMMessageManager) {
        self.database = database
        self.messageManager = messageManager
        
        setupMessageListener()
    }
    
    // MARK: - Setup
    
    private func setupMessageListener() {
        // 监听新消息，更新会话
        messageManager.addListener(self)
    }
    
    // MARK: - Listener Management
    
    /// 添加会话监听器
    public func addListener(_ listener: IMConversationListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除会话监听器
    public func removeListener(_ listener: IMConversationListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    /// 通知所有监听器
    private func notifyListeners(_ block: (IMConversationListener) -> Void) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMConversationListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Get Conversations
    
    /// 获取所有会话
    public func getAllConversations() -> [IMConversation] {
        return database.getAllConversations()
    }
    
    /// 获取会话
    public func getConversation(conversationID: String) -> IMConversation? {
        // 先从缓存获取
        if let conversation = conversationCache.get(forKey: conversationID) {
            return conversation
        }
        
        // 从数据库获取
        if let conversation = database.getConversation(conversationID: conversationID) {
            conversationCache.set(conversation, forKey: conversationID)
            return conversation
        }
        
        return nil
    }
    
    /// 根据用户 ID 获取单聊会话
    public func getSingleConversation(userID: String) -> IMConversation? {
        let currentUserID = getCurrentUserID()
        let conversationID = currentUserID < userID ? "single_\(currentUserID)_\(userID)" : "single_\(userID)_\(currentUserID)"
        return getConversation(conversationID: conversationID)
    }
    
    /// 根据群组 ID 获取群聊会话
    public func getGroupConversation(groupID: String) -> IMConversation? {
        let conversationID = "group_\(groupID)"
        return getConversation(conversationID: conversationID)
    }
    
    // MARK: - Create/Update Conversation
    
    /// 创建或更新会话
    public func createOrUpdateConversation(
        conversationID: String,
        conversationType: IMConversationType,
        targetID: String,
        showName: String,
        faceURL: String,
        lastMessage: IMMessage? = nil
    ) -> IMConversation {
        var conversation = getConversation(conversationID: conversationID)
        
        if conversation == nil {
            // 创建新会话
            conversation = IMConversation()
            conversation?.conversationID = conversationID
            conversation?.conversationType = conversationType
            
            if conversationType == .single {
                conversation?.userID = targetID
            } else if conversationType == .group {
                conversation?.groupID = targetID
            }
            
            IMLogger.shared.info("Creating conversation: \(conversationID)")
        }
        
        guard let conv = conversation else {
            fatalError("Failed to create conversation")
        }
        
        // 更新会话信息
        conv.showName = showName
        conv.faceURL = faceURL
        
        if let message = lastMessage {
            conv.lastMessage = message
            conv.latestMsgSendTime = message.sendTime
        }
        
        conv.updateTime = IMUtils.currentTimeMillis()
        
        // 保存到数据库
        try? database.saveConversation(conv)
        
        // 更新缓存
        conversationCache.set(conv, forKey: conversationID)
        
        // 通知监听器
        if conversation == nil {
            notifyListeners { $0.onConversationCreated(conv) }
        } else {
            notifyListeners { $0.onConversationUpdated(conv) }
        }
        
        return conv
    }
    
    /// 更新会话最后一条消息
    private func updateConversationLastMessage(_ message: IMMessage) {
        let conversationID = message.conversationID
        
        guard let conversation = getConversation(conversationID: conversationID) else {
            // 会话不存在，创建新会话
            let targetID = message.conversationType == .single ? message.receiverID : message.groupID
            _ = createOrUpdateConversation(
                conversationID: conversationID,
                conversationType: message.conversationType,
                targetID: targetID,
                showName: "",
                faceURL: "",
                lastMessage: message
            )
            return
        }
        
        // 更新最后一条消息
        conversation.lastMessage = message
        conversation.latestMsgSendTime = message.sendTime
        conversation.updateTime = IMUtils.currentTimeMillis()
        
        // 如果是收到的消息，增加未读数
        if message.direction == .receive && !message.isRead {
            conversation.unreadCount += 1
        }
        
        // 保存到数据库
        try? database.saveConversation(conversation)
        
        // 更新缓存
        conversationCache.set(conversation, forKey: conversationID)
        
        // 通知监听器
        notifyListeners { $0.onConversationUpdated(conversation) }
        notifyListeners { $0.onUnreadCountChanged(conversationID, count: conversation.unreadCount) }
        
        // 更新总未读数
        updateTotalUnreadCount()
    }
    
    // MARK: - Delete Conversation
    
    /// 删除会话
    public func deleteConversation(
        conversationID: String,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        do {
            try database.deleteConversation(conversationID: conversationID)
            conversationCache.remove(forKey: conversationID)
            
            notifyListeners { $0.onConversationDeleted(conversationID) }
            updateTotalUnreadCount()
            
            completion?(.success(()))
        } catch {
            IMLogger.shared.error("Failed to delete conversation: \(error)")
            completion?(.failure(.databaseError(error.localizedDescription)))
        }
    }
    
    // MARK: - Unread Count
    
    /// 获取会话未读数
    public func getUnreadCount(conversationID: String) -> Int {
        guard let conversation = getConversation(conversationID: conversationID) else {
            return 0
        }
        return conversation.unreadCount
    }
    
    /// 获取总未读数
    public func getTotalUnreadCount() -> Int {
        let conversations = getAllConversations()
        return conversations.reduce(0) { $0 + $1.unreadCount }
    }
    
    /// 清除会话未读数
    public func clearUnreadCount(
        conversationID: String,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        do {
            try database.updateConversationUnreadCount(conversationID: conversationID, count: 0)
            
            // 更新缓存
            if let conversation = conversationCache.get(forKey: conversationID) {
                conversation.unreadCount = 0
                try? database.saveConversation(conversation)
            }
            
            notifyListeners { $0.onUnreadCountChanged(conversationID, count: 0) }
            updateTotalUnreadCount()
            
            completion?(.success(()))
        } catch {
            IMLogger.shared.error("Failed to clear unread count: \(error)")
            completion?(.failure(.databaseError(error.localizedDescription)))
        }
    }
    
    /// 更新总未读数
    private func updateTotalUnreadCount() {
        let totalCount = getTotalUnreadCount()
        notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
    }
    
    // MARK: - Draft
    
    /// 设置会话草稿
    public func setDraft(
        conversationID: String,
        draftText: String,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        guard let conversation = getConversation(conversationID: conversationID) else {
            completion?(.failure(.invalidParameter("Conversation not found")))
            return
        }
        
        do {
            conversation.draftText = draftText
            conversation.draftTime = IMUtils.currentTimeMillis()
            try database.saveConversation(conversation)
            
            notifyListeners { $0.onConversationUpdated(conversation) }
            completion?(.success(()))
        } catch {
            IMLogger.shared.error("Failed to set draft: \(error)")
            completion?(.failure(.databaseError(error.localizedDescription)))
        }
    }
    
    // MARK: - Pin
    
    /// 置顶会话
    public func pinConversation(
        conversationID: String,
        isPinned: Bool,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        guard let conversation = getConversation(conversationID: conversationID) else {
            completion?(.failure(.invalidParameter("Conversation not found")))
            return
        }
        
        do {
            conversation.isPinned = isPinned
            try database.saveConversation(conversation)
            
            notifyListeners { $0.onConversationUpdated(conversation) }
            completion?(.success(()))
        } catch {
            IMLogger.shared.error("Failed to pin conversation: \(error)")
            completion?(.failure(.databaseError(error.localizedDescription)))
        }
    }
    
    // MARK: - Unread Count Management
    
    /// 获取会话未读数
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 未读消息数量
    public func getUnreadCount(conversationID: String) -> Int {
        return database.getUnreadCount(conversationID: conversationID)
    }
    
    /// 标记会话为已读
    /// - Parameter conversationID: 会话 ID
    public func markAsRead(conversationID: String) throws {
        try database.clearUnreadCount(conversationID: conversationID)
        
        // 通知监听器
        let newCount = 0
        notifyListeners { $0.onUnreadCountChanged(conversationID, count: newCount) }
        
        // 通知总未读数变化
        let totalCount = database.getTotalUnreadCount()
        notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
        
        IMLogger.shared.info("Marked conversation as read: \(conversationID)")
    }
    
    /// 获取总未读数（排除免打扰会话）
    /// - Returns: 总未读消息数量
    public func getTotalUnreadCount() -> Int {
        return database.getTotalUnreadCount()
    }
    
    /// 设置免打扰
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - muted: 是否免打扰
    public func setMuted(conversationID: String, muted: Bool) throws {
        try database.setConversationMuted(conversationID: conversationID, muted: muted)
        
        // 通知监听器
        if let conversation = getConversation(conversationID: conversationID) {
            notifyListeners { $0.onConversationUpdated(conversation) }
        }
        
        // 通知总未读数变化（免打扰影响总数）
        let totalCount = database.getTotalUnreadCount()
        notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
        
        IMLogger.shared.info("Set conversation muted: \(conversationID) -> \(muted)")
    }
    
    /// 增加未读数（内部方法，由消息管理器调用）
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - count: 增加的数量
    internal func incrementUnreadCount(conversationID: String, by count: Int = 1) {
        do {
            try database.incrementUnreadCount(conversationID: conversationID, by: count)
            
            // 通知监听器
            let newCount = database.getUnreadCount(conversationID: conversationID)
            notifyListeners { $0.onUnreadCountChanged(conversationID, count: newCount) }
            
            // 通知总未读数变化
            let totalCount = database.getTotalUnreadCount()
            notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
            
        } catch {
            IMLogger.shared.error("Failed to increment unread count: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentUserID() -> String {
        // 从上下文获取当前用户 ID
        return ""
    }
}

// MARK: - Message Listener

extension IMConversationManager: IMMessageListener {
    public func onMessageReceived(_ message: IMMessage) {
        // 更新会话最后一条消息
        updateConversationLastMessage(message)
    }
    
    public func onMessageStatusChanged(_ message: IMMessage) {
        // 如果消息状态改变，可能需要更新会话
        if let conversation = getConversation(conversationID: message.conversationID) {
            if conversation.lastMessage?.messageID == message.messageID {
                notifyListeners { $0.onConversationUpdated(conversation) }
            }
        }
    }
}


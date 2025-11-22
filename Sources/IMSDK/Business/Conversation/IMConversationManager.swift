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
    private let userID: String
    
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 会话缓存
    private let conversationCache = IMMemoryCache<IMConversation>(countLimit: 200)
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, messageManager: IMMessageManager, userID: String) {
        self.database = database
        self.messageManager = messageManager
        self.userID = userID
        
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
    private func notifyListeners(_ block: @escaping (IMConversationListener) -> Void) {
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
        return database.getAllConversations(sortByTime: true)
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
        // 排序保证唯一性（参考 OpenIM 实现）
        let userIDs = [currentUserID, userID].sorted()
        let conversationID = "single_\(userIDs[0])_\(userIDs[1])"
        return getConversation(conversationID: conversationID)
    }
    
    /// 根据群组 ID 获取群聊会话
    public func getGroupConversation(groupID: String) -> IMConversation? {
        let conversationID = "group_\(groupID)"
        return getConversation(conversationID: conversationID)
    }
    
    // MARK: - Create/Update Conversation

    /// 更新会话最后一条消息
    private func updateConversationLastMessage(_ message: IMMessage) {
        let conversationID = message.conversationID
        
        // 确保会话存在，如果不存在则创建
        var conversation = getConversation(conversationID: conversationID)
        let isNewConversation = (conversation == nil)
        
        if conversation == nil {
            // 会话不存在，创建新会话
            // 对于单聊：targetID 是对话的另一方
            // - 如果是收到的消息：对方是 senderID
            // - 如果是发送的消息：对方是 receiverID
            let targetID: String
            if message.conversationType == .single {
                targetID = message.direction == .receive ? message.senderID : message.receiverID
            } else {
                targetID = message.groupID
            }
            
            // 创建新会话
            conversation = IMConversation()
            conversation?.conversationID = conversationID
            conversation?.conversationType = message.conversationType
            
            if message.conversationType == .single {
                conversation?.userID = targetID
            } else if message.conversationType == .group {
                conversation?.groupID = targetID
            }
            
            IMLogger.shared.info("Creating conversation: \(conversationID)")
        }
        
        guard let conv = conversation else {
            IMLogger.shared.error("Failed to get or create conversation: \(conversationID)")
            return
        }
        
        // 更新最后一条消息
        conv.lastMessage = message
        conv.latestMsgSendTime = message.sendTime
        conv.updateTime = IMUtils.currentTimeMillis()
        
        // 如果是收到的消息，增加未读数
        if message.direction == .receive && !message.isRead {
            conv.unreadCount += 1
        }
        
        // 保存到数据库
        try? database.saveConversation(conv)
        
        // 更新缓存
        conversationCache.set(conv, forKey: conversationID)
        
        // 通知监听器
        if (isNewConversation) {
            notifyListeners { $0.onConversationCreated(conv) }
        } else {
            notifyListeners { $0.onConversationUpdated(conv) }
        }
        
        notifyListeners { $0.onUnreadCountChanged(conversationID, count: conv.unreadCount) }
        
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
            try database.updateConversationUnreadCount(conversationID: conversationID, unreadCount: 0)
            
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
    
    /// 标记会话为已读
    /// - Parameter conversationID: 会话 ID
    public func markAsRead(conversationID: String) throws {
        // 1. 更新数据库
        try database.clearUnreadCount(conversationID: conversationID)
        
        // 2. 更新内存缓存
        if let conversation = getConversation(conversationID: conversationID) {
            conversation.unreadCount = 0
            conversationCache.set(conversation, forKey: conversationID)
            
            // 通知会话更新（让 UI 能刷新显示未读数）
            notifyListeners { $0.onConversationUpdated(conversation) }
        }
        
        // 3. 通知未读数变化
        notifyListeners { $0.onUnreadCountChanged(conversationID, count: 0) }
        
        // 4. 通知总未读数变化
        let totalCount = database.getTotalUnreadCount()
        notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
        
        IMLogger.shared.info("Marked conversation as read: \(conversationID)")
    }
    
    /// 设置免打扰
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - muted: 是否免打扰
    public func setMuted(conversationID: String, muted: Bool) throws {
        try database.setConversationMuted(conversationID: conversationID, isMuted: muted)
        
        // 通知监听器
        if let conversation = getConversation(conversationID: conversationID) {
            notifyListeners { $0.onConversationUpdated(conversation) }
        }
        
        // 通知总未读数变化（免打扰影响总数）
        let totalCount = database.getTotalUnreadCount()
        notifyListeners { $0.onTotalUnreadCountChanged(totalCount) }
        
        IMLogger.shared.info("Set conversation muted: \(conversationID) -> \(muted)")
    }
    // MARK: - Helper Methods
    
    private func getCurrentUserID() -> String {
        return userID
    }
}

// MARK: - Message Listener

extension IMConversationManager: IMMessageListener {
    public func onMessageReceived(_ message: IMMessage) {
        // 更新会话最后一条消息（包含未读数管理）
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


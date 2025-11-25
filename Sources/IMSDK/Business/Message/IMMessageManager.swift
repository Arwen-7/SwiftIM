/// IMMessageManager - 消息管理器
/// 负责消息的发送、接收、存储和查询

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 消息监听器
public protocol IMMessageListener: AnyObject {
    /// 收到新消息
    func onMessageReceived(_ message: IMMessage)
    
    /// 消息状态改变
    func onMessageStatusChanged(_ message: IMMessage)
    
    /// 消息被撤回
    /// - Parameter message: 被撤回的消息（已更新为撤回状态）
    func onMessageRevoked(message: IMMessage)
    
    /// 消息已读回执
    func onMessageReadReceiptReceived(conversationID: String, messageIDs: [String])
}

// 提供默认实现，使所有方法可选
public extension IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {}
    func onMessageStatusChanged(_ message: IMMessage) {}
    func onMessageRevoked(message: IMMessage) {}
    func onMessageReadReceiptReceived(conversationID: String, messageIDs: [String]) {}
}

/// 消息管理器
public final class IMMessageManager {
    
    // MARK: - Properties
    
    internal let database: IMDatabaseProtocol
    internal let messageQueue: IMMessageQueue
    internal let userID: String
    
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    /// 当前活跃的会话ID（用于判断是否增加未读数）
    internal var currentConversationID: String?
    internal let currentConvLock = NSLock()
    
    // 消息缓存
    internal let messageCache = IMMemoryCache<IMMessage>(countLimit: 500)
    
    /// 发送数据回调（由 IMClient 设置，用于发送数据到传输层）
    /// - Parameters:
    ///   - body: Protobuf 消息体
    ///   - command: 命令类型（用于 TCP 包头）
    /// - Returns: 是否成功提交到传输层
    internal var onSendData: ((Data, IMCommandType) -> Bool)?
    
    /// 连接状态检查回调（由 IMClient 设置，用于检查是否已连接）
    internal var isConnected: (() -> Bool)?
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, userID: String) {
        self.database = database
        self.userID = userID
        self.messageQueue = IMMessageQueue()
        
        setupHandlers()
    }
    
    // MARK: - Setup
    
    private func setupHandlers() {
        // 消息队列发送回调（同步）
        messageQueue.onSendMessage = { [weak self] message in
            guard let self = self else { return false }
            return self.sendMessageToServer(message)
        }
        
        // 消息发送失败回调（重试次数耗尽）
        messageQueue.onMessageFailed = { [weak self] message in
            self?.handleMessageSendFailed(message)
        }
    }
    
    /// 处理传输层重连事件（由 IMClient 调用）
    internal func handleTransportReconnected() {
        // 通知消息队列重新发送未确认的消息
        messageQueue.onSocketReconnected()
    }
    
    // MARK: - Listener Management
    
    /// 添加消息监听器
    public func addListener(_ listener: IMMessageListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除消息监听器
    public func removeListener(_ listener: IMMessageListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    /// 获取所有监听器（用于迁移）
    internal func getAllListeners() -> [IMMessageListener] {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        return listeners.allObjects.compactMap { $0 as? IMMessageListener }
    }
    
    /// 通知所有监听器
    internal func notifyListeners(_ block: @escaping (IMMessageListener) -> Void) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMMessageListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Send Message
    
    /// 创建文本消息
    public func createTextMessage(
        content: String,
        to receiverID: String,
        conversationType: IMConversationType
    ) -> IMMessage {
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()  // ✅ 客户端生成唯一 ID
        message.conversationType = conversationType
        message.senderID = userID
        message.receiverID = conversationType == .single ? receiverID : ""
        message.groupID = conversationType == .group ? receiverID : ""
        message.conversationID = generateConversationID(type: conversationType, targetID: receiverID)
        message.messageType = .text
        message.content = content
        message.status = .sending
        message.direction = .send
        message.sendTime = IMUtils.currentTimeMillis()
        
        return message
    }
    
    /// 创建图片消息
    public func createImageMessage(
        imageURL: String,
        to receiverID: String,
        conversationType: IMConversationType
    ) -> IMMessage {
        let message = createTextMessage(content: "", to: receiverID, conversationType: conversationType)
        message.messageType = .image
        message.content = imageURL
        return message
    }
    
    /// 创建语音消息
    public func createAudioMessage(
        audioURL: String,
        duration: Int,
        to receiverID: String,
        conversationType: IMConversationType
    ) -> IMMessage {
        let message = createTextMessage(content: "", to: receiverID, conversationType: conversationType)
        message.messageType = .audio
        message.content = audioURL
        let extra = ["duration": duration]
        message.extra = IMUtils.dictToJSON(extra) ?? ""
        return message
    }
    
    /// 发送消息
    ///
    /// **重要说明：**
    /// - 返回值表示消息已成功**提交到发送队列**，而非已送达服务器
    /// - 消息会异步发送，状态变化通过 `IMMessageListener.onMessageStatusChanged` 通知
    /// - 消息状态流转：sending → sent → delivered → read
    ///
    /// **使用示例：**
    /// ```swift
    /// // 发送消息
    /// do {
    ///     let message = try messageManager.sendMessage(message)
    ///     print("消息已提交到发送队列 ✓")  // 注意：不是已送达！
    /// } catch {
    ///     print("提交失败（本地错误）: \(error)")
    /// }
    ///
    /// // 监听实际发送状态
    /// extension MyClass: IMMessageListener {
    ///     func onMessageStatusChanged(_ message: IMMessage) {
    ///         switch message.status {
    ///         case .sent:      print("已发送到服务器 ✓")
    ///         case .delivered: print("对方已收到 ✓✓")
    ///         case .failed:    print("发送失败 ❌")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter message: 要发送的消息
    /// - Returns: 已提交到队列的消息
    /// - Throws: 如果保存到数据库失败
    @discardableResult
    public func sendMessage(_ message: IMMessage) throws -> IMMessage {
        IMLogger.shared.info("Sending message: clientMsgID=\(message.clientMsgID)")
        
        // ✅ messageID 保持为空，等待服务端返回
        // 数据库保存逻辑会处理 messageID 为空的情况（使用 clientMsgID 作为主键）
        
        // 保存到数据库（可能抛出异常）
        try database.saveMessage(message)
        
        // 添加到缓存（使用 clientMsgID 作为 key，便于后续通过 clientMsgID 查找）
        messageCache.set(message, forKey: message.clientMsgID)
        
        // 通知界面更新
        notifyListeners { $0.onMessageReceived(message) }
        
        // 添加到发送队列（异步发送）
        messageQueue.enqueue(message)
        
        // ✅ 成功：消息已提交到发送队列
        // ⚠️ 注意：这不代表已送达服务器！
        // 实际发送状态通过 onMessageStatusChanged 通知
        return message
    }
    
    /// 发送消息到服务器
    ///
    /// **重要：** 这个方法只负责把消息提交到 WebSocket，不等待 ACK
    /// 消息是否真正送达服务器，由 `handleMessageAck` 处理
    ///
    /// - Parameter message: 要发送的消息
    /// - Returns: true=成功提交到传输层，false=提交失败（网络断开等）
    private func sendMessageToServer(_ message: IMMessage) -> Bool {
        // 检查是否已连接
        guard let isConnected = isConnected, isConnected() else {
            IMLogger.shared.error("Transport not connected")
            return false
        }
        
        // 检查是否有发送回调
        guard let onSendData = onSendData else {
            IMLogger.shared.error("onSendData callback not set")
            return false
        }
        
        do {
            // 使用 Protobuf 编码消息
            let data = try encodeMessageToProtobuf(message)
            let success = onSendData(data, .sendMsgReq)
            
            if success {
                // ⚠️ 注意：这里不要立即更新为 .sent
                // 只是把数据提交到传输层，不代表已发送到服务器
                // 应该等收到服务器的 ACK 后再更新状态
                // 消息状态保持为 .sending，等待 ACK
                
                IMLogger.shared.debug("Message sent to transport layer: clientMsgID=\(message.clientMsgID)")
                
                // ✅ 返回 true：成功提交到传输层发送缓冲区
                // ⚠️ 这不代表服务器收到！消息仍保留在队列中，等待 ACK
                return true
            } else {
                IMLogger.shared.error("Failed to send data to transport layer")
                return false
            }
        } catch {
            IMLogger.shared.error("Failed to encode message: \(error)")
            return false
        }
    }
    
    // MARK: - Message Encoding
    
    /// 将 IMMessage 编码为 Protobuf 格式（✅ 使用 MessageInfo 结构）
    private func encodeMessageToProtobuf(_ message: IMMessage) throws -> Data {
        var sendRequest = Im_Protocol_SendMessageRequest()
        
        // ✅ 通过 .message 访问 MessageInfo 字段
        sendRequest.message.clientMsgID = message.clientMsgID
        sendRequest.message.conversationID = message.conversationID
        sendRequest.message.senderID = message.senderID
        sendRequest.message.receiverID = message.receiverID
        sendRequest.message.messageType = Int32(message.messageType.rawValue)
        sendRequest.message.sendTime = message.sendTime
        
        // 将消息内容编码为 JSON Data
        if let contentData = message.content.data(using: .utf8) {
            sendRequest.message.content = contentData
        }
        
        // 编码为 Protobuf 数据
        return try sendRequest.serializedData()
    }
    
    // MARK: - Receive Message
    
    /// 处理收到的消息
    public func handleReceivedMessage(_ message: IMMessage) {
        IMLogger.shared.info("Message received: serverMsgID=\(message.serverMsgID.isEmpty ? "(empty)" : message.serverMsgID), clientMsgID=\(message.clientMsgID)")
        
        // 设置消息方向
        message.direction = .receive
        
        // ✅ 步骤 1：消息丢失检测（在保存前检测）
        checkMessageLoss(for: message) { [weak self] lossInfo in
            if let lossInfo = lossInfo {
                // 检测到丢失，补拉逻辑已在 checkMessageLoss 内部触发
                IMLogger.shared.warning("检测到消息丢失，已触发补拉：\(lossInfo)")
            }
        }
        
        // 步骤 2：保存到数据库
        do {
            try database.saveMessage(message)
        } catch {
            IMLogger.shared.error("Failed to save received message: \(error)")
        }
        
        // 步骤 3：添加到缓存（使用 clientMsgID 作为 key，因为它是主键）
        messageCache.set(message, forKey: message.clientMsgID)
        
        // 步骤 4：通知监听器（包括 IMConversationManager）
        // IMConversationManager 会负责更新未读数
        notifyListeners { $0.onMessageReceived(message) }
        
        // 步骤 5：发送已送达确认（使用 serverMsgID）
        if !message.serverMsgID.isEmpty {
            sendMessageAck(messageID: message.serverMsgID, status: .delivered)
        }
    }
    
    /// 处理同步的历史消息（批量）
    /// 注意：此方法假设消息已经保存到数据库，只负责更新缓存和通知 UI
    internal func handleSyncedMessages(_ messages: [IMMessage]) {
        guard !messages.isEmpty else { return }
        
        IMLogger.shared.info("📥 Processing \(messages.count) synced messages")
        
        // 批量添加到缓存（使用 clientMsgID 作为 key，因为它是主键）
        for message in messages {
            messageCache.set(message, forKey: message.clientMsgID)
        }
        
        // 通知监听器（会触发会话列表更新）
        for message in messages {
            notifyListeners { $0.onMessageReceived(message) }
        }
        
        IMLogger.shared.debug("✅ Synced messages processed, UI should update now")
    }
    
    /// 处理消息确认
    /// - Parameters:
    ///   - clientMsgID: 客户端消息 ID（用于匹配本地消息）
    ///   - serverMessageID: 服务端消息 ID（用于更新本地 messageID）
    ///   - status: 消息状态
    public func handleMessageAck(clientMsgID: String, serverMessageID: String, status: IMMessageStatus) {
        IMLogger.shared.debug("Message ACK: clientMsgID=\(clientMsgID), serverMessageID=\(serverMessageID.isEmpty ? "(empty)" : serverMessageID), status: \(status)")
        
        // ✅ 关键：收到服务器 ACK 后，才从队列移除（通过 clientMsgID 匹配）
        // 这保证了消息可靠送达：只有服务器确认收到，才认为发送成功
        messageQueue.dequeue(clientMsgID: clientMsgID)
        
        // 从缓存中查找消息（使用 clientMsgID 作为 key）
        if let message = messageCache.get(forKey: clientMsgID) {
            // 更新消息状态和 serverMsgID
            message.status = status
            if !serverMessageID.isEmpty {
                message.serverMsgID = serverMessageID  // ✅ 更新为服务端 ID
            }
            
            // ✅ 简化：直接保存消息（主键是 clientMsgID，不会改变）
            do {
                try database.saveMessage(message)
            } catch {
                IMLogger.shared.error("Failed to update message in database: \(error)")
            }
            
            // 通知界面更新
            notifyListeners { $0.onMessageStatusChanged(message) }
        } else {
            // 如果缓存中没有，从数据库读取（使用 clientMsgID 作为主键）
            if let message = database.getMessage(clientMsgID: clientMsgID) {
                
                message.status = status
                if !serverMessageID.isEmpty {
                    message.serverMsgID = serverMessageID
                }
                
                // ✅ 简化：直接保存消息
                do {
                    try database.saveMessage(message)
                } catch {
                    IMLogger.shared.error("Failed to update message in database: \(error)")
                }
                
                // 更新缓存
                messageCache.set(message, forKey: clientMsgID)
                
                // 通知界面更新
                notifyListeners { $0.onMessageStatusChanged(message) }
            } else {
                IMLogger.shared.warning("Message not found for ACK: clientMsgID=\(clientMsgID)")
            }
        }
    }
    
    /// 处理消息发送失败（重试次数耗尽）
    private func handleMessageSendFailed(_ message: IMMessage) {
        IMLogger.shared.error("Message send failed permanently: \(message.clientMsgID)")
        
        // 更新数据库状态为失败
        do {
            try database.updateMessageStatus(clientMsgID: message.clientMsgID, status: .failed)
        } catch {
            IMLogger.shared.error("Failed to update message status to failed: \(error)")
        }
        
        // 更新缓存
        message.status = .failed
        messageCache.set(message, forKey: message.clientMsgID)
        
        // 通知界面
        notifyListeners { $0.onMessageStatusChanged(message) }
    }
    
    /// 发送消息确认
    internal func sendMessageAck(messageID: String, status: IMMessageStatus) {
        guard let isConnected = isConnected, isConnected() else {
            IMLogger.shared.warning("Not connected, skip sending message ACK")
            return
        }
        
        guard let onSendData = onSendData else {
            IMLogger.shared.error("onSendData callback not set")
            return
        }
        
        do {
            // 使用 Protobuf 编码消息 ACK
            var ack = Im_Protocol_MessageAck()
            ack.serverMsgID = messageID  // ✅ 使用 serverMsgID
            ack.seq = 0 // 序列号由传输层管理
            
            let data = try ack.serializedData()
            _ = onSendData(data, .msgAck)
        } catch {
            IMLogger.shared.error("Failed to send message ACK: \(error)")
        }
    }
    
    // MARK: - Message Read
    
    
    /// 处理消息已读
    private func handleMessageRead(messageIDs: [String]) {
        IMLogger.shared.info("Messages read: \(messageIDs.count)")
        
        // 更新数据库
        do {
            try database.markMessagesAsRead(messageIDs: messageIDs)
        } catch {
            IMLogger.shared.error("Failed to mark messages as read: \(error)")
        }
        
        // 获取会话 ID（从第一条消息）
        if let firstMessage = messageIDs.first,
           let message = getMessage(messageID: firstMessage) {
            notifyListeners { $0.onMessageReadReceiptReceived(conversationID: message.conversationID, messageIDs: messageIDs) }
        }
    }
    
    /// 通知已读回执（用于处理服务端推送的已读回执）
    internal func notifyReadReceiptReceived(conversationID: String, messageIDs: [String], readerID: String, readTime: Int64) {
        IMLogger.shared.info("📖 Read receipt received: conversation=\(conversationID), reader=\(readerID), count=\(messageIDs.count)")
        
        // 更新数据库中的消息已读状态
        do {
            try database.markMessagesAsRead(messageIDs: messageIDs)
        } catch {
            IMLogger.shared.error("Failed to mark messages as read: \(error)")
        }
        
        // 通知监听器
        notifyListeners { $0.onMessageReadReceiptReceived(conversationID: conversationID, messageIDs: messageIDs) }
    }
    
    // MARK: - Query Messages
    
    /// 获取消息
    public func getMessage(messageID: String) -> IMMessage? {
        // 先从缓存获取
        if let message = messageCache.get(forKey: messageID) {
            return message
        }
        
        // 从数据库获取
        return database.getMessage(messageID: messageID)
    }
    
    /// 获取会话消息列表
    public func getMessages(
        conversationID: String,
        limit: Int = 20,
        offset: Int = 0
    ) -> [IMMessage] {
        return database.getMessages(conversationID: conversationID, limit: limit)
    }
    
    /// 获取指定时间之前的消息
    public func getMessagesBefore(
        conversationID: String,
        timestamp: Int64,
        limit: Int = 20
    ) -> [IMMessage] {
        return database.getMessagesBefore(conversationID: conversationID, beforeTime: timestamp, limit: limit)
    }
    
    // MARK: - Delete & Revoke
    
    /// 删除消息
    public func deleteMessage(
        messageID: String,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        do {
            try database.deleteMessage(messageID: messageID)
            messageCache.remove(forKey: messageID)
            completion?(.success(()))
        } catch {
            IMLogger.shared.error("Failed to delete message: \(error)")
            completion?(.failure(.databaseError(error.localizedDescription)))
        }
    }
    
    /// 撤回消息
    public func revokeMessage(
        messageID: String,
        completion: ((Result<Void, IMError>) -> Void)? = nil
    ) {
        // TODO: 发送撤回请求到服务器
        // 这里需要实现撤回逻辑
        IMLogger.shared.info("Revoking message: \(messageID)")
        completion?(.success(()))
    }
    
    // MARK: - Helper Methods
    
    private func generateConversationID(type: IMConversationType, targetID: String) -> String {
        switch type {
        case .single:
            // 单聊：排序两个用户 ID（参考 OpenIM: SingleChatType）
            let userIDs = [userID, targetID].sorted()
            return "single_\(userIDs[0])_\(userIDs[1])"
        case .group:
            return "group_\(targetID)"
        case .chatRoom:
            return "chatroom_\(targetID)"
        case .system:
            return "system_\(targetID)"
        }
    }
}

// MARK: - 消息分页加载扩展

extension IMMessageManager {
    
    /// 分页获取历史消息（基于时间）
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - startTime: 起始时间（往前查，0 表示从最新开始）
    ///   - count: 拉取数量（默认 20）
    /// - Returns: 消息列表（按时间倒序，最新的在前）
    public func getHistoryMessages(
        conversationID: String,
        startTime: Int64 = 0,
        count: Int = 20
    ) throws -> [IMMessage] {
        let beforeTime = startTime > 0 ? startTime : Int64.max
        
        let messages = database.getHistoryMessages(
            conversationID: conversationID,
            startTime: beforeTime,
            count: count
        )
        
        IMLogger.shared.debug("Loaded \(messages.count) history messages for conversation: \(conversationID)")
        
        return messages
    }
    
    /// 分页获取历史消息（基于 seq）
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - startSeq: 起始 seq（往前查，0 表示从最新开始）
    ///   - count: 拉取数量（默认 20）
    /// - Returns: 消息列表（按 seq 倒序，最新的在前）
    public func getHistoryMessagesBySeq(
        conversationID: String,
        startSeq: Int64 = 0,
        count: Int = 20
    ) throws -> [IMMessage] {
        let beforeSeq = startSeq > 0 ? startSeq : Int64.max
        
        let messages = database.getHistoryMessagesBySeq(
            conversationID: conversationID,
            startSeq: beforeSeq,
            count: count
        )
        
        IMLogger.shared.debug("Loaded \(messages.count) history messages by seq for conversation: \(conversationID)")
        
        return messages
    }
    
    /// 获取会话的消息总数
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 消息总数
    public func getMessageCount(conversationID: String) -> Int {
        return database.getHistoryMessageCount(conversationID: conversationID)
    }
    
    /// 检查是否还有更多历史消息
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - currentCount: 当前已加载数量
    /// - Returns: 是否还有更多
    public func hasMoreMessages(conversationID: String, currentCount: Int) -> Bool {
        let totalCount = getMessageCount(conversationID: conversationID)
        return currentCount < totalCount
    }
    
    /// 获取会话中最早的消息时间
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 最早消息时间
    public func getOldestMessageTime(conversationID: String) -> Int64 {
        return database.getOldestMessageTime(conversationID: conversationID)
    }
    
    /// 获取会话中最新的消息时间
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 最新消息时间
    public func getLatestMessageTime(conversationID: String) -> Int64 {
        return database.getLatestMessageTime(conversationID: conversationID)
    }
    
    /// 获取指定时间范围内的消息
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - startTime: 开始时间
    ///   - endTime: 结束时间
    /// - Returns: 消息列表
    public func getMessagesInTimeRange(
        conversationID: String,
        startTime: Int64,
        endTime: Int64
    ) throws -> [IMMessage] {
        return try database.getMessagesInTimeRange(
            conversationID: conversationID,
            startTime: startTime,
            endTime: endTime
        )
    }
}

// MARK: - 消息搜索扩展

extension IMMessageManager {
    
    /// 搜索消息
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选，nil 表示全局搜索）
    ///   - messageTypes: 消息类型筛选（可选）
    ///   - startTime: 开始时间（可选）
    ///   - endTime: 结束时间（可选）
    ///   - limit: 返回数量限制
    /// - Returns: 消息列表（按时间倒序）
    public func searchMessages(
        keyword: String,
        conversationID: String? = nil,
        messageTypes: [IMMessageType]? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 50
    ) throws -> [IMMessage] {
        // 去除首尾空格
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKeyword.isEmpty else {
            IMLogger.shared.warning("Search keyword is empty")
            return []
        }
        
        let messages = database.searchMessages(
            keyword: trimmedKeyword,
            conversationID: conversationID,
            limit: limit
        )
        
        IMLogger.shared.info("Search found \(messages.count) messages for keyword: '\(trimmedKeyword)'")
        
        return messages
    }
    
    /// 搜索消息数量
    /// - Parameters:
    ///   - keyword: 搜索关键词
    ///   - conversationID: 会话 ID（可选，nil 表示全局搜索）
    ///   - messageTypes: 消息类型筛选（可选）
    ///   - startTime: 开始时间（可选）
    ///   - endTime: 结束时间（可选）
    /// - Returns: 匹配的消息数量
    public func searchMessageCount(
        keyword: String,
        conversationID: String? = nil,
        messageTypes: [IMMessageType]? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) -> Int {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKeyword.isEmpty else {
            return 0
        }
        
        // 构造时间范围
        let timeRange: (start: Int64, end: Int64)? = {
            if let start = startTime, let end = endTime {
                return (start: start, end: end)
            }
            return nil
        }()
        
        return database.searchMessageCount(
            keyword: trimmedKeyword,
            conversationID: conversationID,
            timeRange: timeRange
        )
    }
    
    /// 按发送者搜索消息
    /// - Parameters:
    ///   - senderID: 发送者 ID
    ///   - conversationID: 会话 ID（可选，nil 表示全局搜索）
    ///   - limit: 返回数量限制
    /// - Returns: 消息列表
    public func searchMessagesBySender(
        senderID: String,
        conversationID: String? = nil,
        limit: Int = 50
    ) throws -> [IMMessage] {
        return try database.searchMessagesBySender(
            senderID: senderID,
            conversationID: conversationID,
            limit: limit
        )
    }
}

// MARK: - 当前会话管理（未读数）

extension IMMessageManager {
    
    /// 设置当前活跃的会话
    /// - Parameter conversationID: 会话 ID，nil 表示没有活跃会话
    /// - Note: 当打开一个会话时调用此方法，关闭时传 nil
    public func setCurrentConversation(_ conversationID: String?) {
        currentConvLock.lock()
        currentConversationID = conversationID
        currentConvLock.unlock()
        
        IMLogger.shared.verbose("Set current conversation: \(conversationID ?? "nil")")
    }
    
    /// 获取当前活跃的会话ID
    /// - Returns: 当前会话 ID，nil 表示没有活跃会话
    public func getCurrentConversation() -> String? {
        currentConvLock.lock()
        defer { currentConvLock.unlock() }
        return currentConversationID
    }
}

// MARK: - 富媒体消息扩展

extension IMMessageManager {
    
    // MARK: - 图片消息
    
    /// 发送图片消息
    /// - Parameters:
    ///   - imageURL: 图片本地 URL
    ///   - conversationID: 会话 ID
    ///   - progressHandler: 上传进度回调
    ///   - completion: 完成回调
    public func sendImageMessage(
        imageURL: URL,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        // 获取图片信息
        #if os(iOS) || os(tvOS) || os(watchOS)
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            completion(.failure(IMError.fileNotFound))
            return
        }
        let imageSize = image.size
        #elseif os(macOS)
        guard let image = NSImage(contentsOfFile: imageURL.path) else {
            completion(.failure(IMError.fileNotFound))
            return
        }
        let imageSize = image.size
        #else
        // 对于其他平台，使用文件大小作为替代
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            completion(.failure(IMError.fileNotFound))
            return
        }
        let imageSize = CGSize(width: 0, height: 0)
        #endif
        let fileSize = IMFileManager.shared.getFileSize(at: imageURL)
        
        // 生成缩略图
        let thumbnailURL = IMFileManager.shared.generateThumbnail(for: imageURL)
        
        // 创建消息对象
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()
        message.conversationID = conversationID
        message.messageType = .image
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 先保存到本地数据库（仅本地保存，不发送到服务器）
        _ = try? database.saveMessage(message)
        notifyListeners { $0.onMessageStatusChanged(message) }
        
        // 上传原图
        IMFileManager.shared.uploadFile(imageURL, fileType: .image, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let uploadResult):
                // 上传成功，构建消息内容
                var imageContent = IMImageMessageContent()
                imageContent.url = uploadResult.url
                imageContent.width = Int(imageSize.width)
                imageContent.height = Int(imageSize.height)
                imageContent.size = fileSize
                imageContent.format = uploadResult.format
                imageContent.localPath = imageURL.path
                
                // 如果有缩略图，也上传
                if let thumbURL = thumbnailURL {
                    IMFileManager.shared.uploadFile(thumbURL, fileType: .image) { thumbResult in
                        if case .success(let thumbUploadResult) = thumbResult {
                            imageContent.thumbnailUrl = thumbUploadResult.url
                            imageContent.thumbnailPath = thumbURL.path
                        }
                        
                        // 更新消息内容
                        if let jsonData = try? JSONEncoder().encode(imageContent),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            message.content = jsonString
                            _ = try? self.database.saveMessage(message)
                            
                            // 上传成功后，发送到服务器
                            _ = try? self.sendMessage(message)
                            
                            completion(.success(message))
                        }
                    }
                } else {
                    // 没有缩略图，直接更新
                    if let jsonData = try? JSONEncoder().encode(imageContent),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        message.content = jsonString
                        _ = try? self.database.saveMessage(message)
                        
                        // 上传成功后，发送到服务器
                        _ = try? self.sendMessage(message)
                        
                        completion(.success(message))
                    }
                }
                
            case .failure(let error):
                // 上传失败
                message.status = .failed
                _ = try? self.database.saveMessage(message)
                
                self.notifyListeners { $0.onMessageStatusChanged(message) }
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 语音消息
    
    /// 发送语音消息
    /// - Parameters:
    ///   - audioURL: 语音文件本地 URL
    ///   - duration: 语音时长（秒）
    ///   - conversationID: 会话 ID
    ///   - progressHandler: 上传进度回调
    ///   - completion: 完成回调
    public func sendAudioMessage(
        audioURL: URL,
        duration: Int,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        let fileSize = IMFileManager.shared.getFileSize(at: audioURL)
        
        // 创建消息对象
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()
        message.conversationID = conversationID
        message.messageType = .audio
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 先保存到本地数据库（仅本地保存，不发送到服务器）
        _ = try? database.saveMessage(message)
        notifyListeners { $0.onMessageStatusChanged(message) }
        
        // 上传语音文件
        IMFileManager.shared.uploadFile(audioURL, fileType: .audio, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let uploadResult):
                // 构建语音消息内容
                var audioContent = IMAudioMessageContent()
                audioContent.url = uploadResult.url
                audioContent.duration = duration
                audioContent.size = fileSize
                audioContent.format = uploadResult.format
                audioContent.localPath = audioURL.path
                
                if let jsonData = try? JSONEncoder().encode(audioContent),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    message.content = jsonString
                    _ = try? self.database.saveMessage(message)
                    
                    // 上传成功后，发送到服务器
                    _ = try? self.sendMessage(message)
                    
                    completion(.success(message))
                }
                
            case .failure(let error):
                message.status = .failed
                _ = try? self.database.saveMessage(message)
                
                self.notifyListeners { $0.onMessageStatusChanged(message) }
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 视频消息
    
    /// 发送视频消息
    /// - Parameters:
    ///   - videoURL: 视频文件本地 URL
    ///   - duration: 视频时长（秒）
    ///   - conversationID: 会话 ID
    ///   - progressHandler: 上传进度回调
    ///   - completion: 完成回调
    public func sendVideoMessage(
        videoURL: URL,
        duration: Int,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        let fileSize = IMFileManager.shared.getFileSize(at: videoURL)
        
        // 创建消息对象
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()
        message.conversationID = conversationID
        message.messageType = .video
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 先保存到本地数据库（仅本地保存，不发送到服务器）
        _ = try? database.saveMessage(message)
        notifyListeners { $0.onMessageStatusChanged(message) }
        
        // 上传视频文件
        IMFileManager.shared.uploadFile(videoURL, fileType: .video, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let uploadResult):
                // 构建视频消息内容
                var videoContent = IMVideoMessageContent()
                videoContent.url = uploadResult.url
                videoContent.duration = duration
                videoContent.size = fileSize
                videoContent.format = uploadResult.format
                videoContent.localPath = videoURL.path
                
                if let jsonData = try? JSONEncoder().encode(videoContent),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    message.content = jsonString
                    _ = try? self.database.saveMessage(message)
                    
                    // 上传成功后，发送到服务器
                    _ = try? self.sendMessage(message)
                    
                    completion(.success(message))
                }
                
            case .failure(let error):
                message.status = .failed
                _ = try? self.database.saveMessage(message)
                
                self.notifyListeners { $0.onMessageStatusChanged(message) }
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 文件消息
    
    /// 发送文件消息
    /// - Parameters:
    ///   - fileURL: 文件本地 URL
    ///   - conversationID: 会话 ID
    ///   - progressHandler: 上传进度回调
    ///   - completion: 完成回调
    public func sendFileMessage(
        fileURL: URL,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        let fileSize = IMFileManager.shared.getFileSize(at: fileURL)
        let fileName = fileURL.lastPathComponent
        
        // 创建消息对象
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()
        message.conversationID = conversationID
        message.messageType = .file
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 先保存到本地数据库（仅本地保存，不发送到服务器）
        _ = try? database.saveMessage(message)
        notifyListeners { $0.onMessageStatusChanged(message) }
        
        // 上传文件
        IMFileManager.shared.uploadFile(fileURL, fileType: .file, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let uploadResult):
                // 构建文件消息内容
                var fileContent = IMFileMessageContent()
                fileContent.url = uploadResult.url
                fileContent.fileName = fileName
                fileContent.size = fileSize
                fileContent.format = uploadResult.format
                fileContent.localPath = fileURL.path
                
                if let jsonData = try? JSONEncoder().encode(fileContent),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    message.content = jsonString
                    _ = try? self.database.saveMessage(message)
                    
                    // 上传成功后，发送到服务器
                    _ = try? self.sendMessage(message)
                    
                    completion(.success(message))
                }
                
            case .failure(let error):
                message.status = .failed
                _ = try? self.database.saveMessage(message)
                
                self.notifyListeners { $0.onMessageStatusChanged(message) }
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 下载富媒体文件
    
    /// 下载富媒体文件
    /// - Parameters:
    ///   - message: 消息对象
    ///   - progressHandler: 下载进度回调
    ///   - completion: 完成回调
    public func downloadMediaFile(
        from message: IMMessage,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let jsonData = message.content.data(using: .utf8) else {
            completion(.failure(IMError.invalidContent))
            return
        }
        
        var url: String?
        
        switch message.messageType {
        case .image:
            if let content = try? JSONDecoder().decode(IMImageMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .audio:
            if let content = try? JSONDecoder().decode(IMAudioMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .video:
            if let content = try? JSONDecoder().decode(IMVideoMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .file:
            if let content = try? JSONDecoder().decode(IMFileMessageContent.self, from: jsonData) {
                url = content.url
            }
        default:
            completion(.failure(IMError.unsupportedMessageType))
            return
        }
        
        guard let downloadURL = url else {
            completion(.failure(IMError.invalidURL))
            return
        }
        
        // 下载文件
        IMFileManager.shared.downloadFile(
            from: downloadURL,
            fileType: message.messageType,
            progressHandler: progressHandler
        ) { result in
            switch result {
            case .success(let downloadResult):
                completion(.success(downloadResult.localPath))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Additional Errors

extension IMError {
    static let invalidContent = IMError.custom("无效的消息内容")
    static let unsupportedMessageType = IMError.custom("不支持的消息类型")
}

// MARK: - 高级富媒体消息扩展（支持压缩和优化）

extension IMMessageManager {
    
    /// 发送图片消息（带压缩）
    public func sendImageMessageWithCompression(
        imageURL: URL,
        conversationID: String,
        compressionConfig: IMImageCompressionConfig = .default,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        // 1. 压缩图片
        guard let compressedURL = IMFileManager.shared.compressImage(at: imageURL, config: compressionConfig) else {
            completion(.failure(IMError.custom("图片压缩失败")))
            return
        }
        
        // 2. 使用压缩后的图片发送
        sendImageMessage(
            imageURL: compressedURL,
            conversationID: conversationID,
            progressHandler: progressHandler,
            completion: completion
        )
    }
    
    /// 发送视频消息（自动提取封面）
    public func sendVideoMessageWithThumbnail(
        videoURL: URL,
        duration: Int,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        // 1. 提取视频封面
        let thumbnailURL = IMFileManager.shared.extractVideoThumbnail(from: videoURL)
        
        // 2. 获取视频信息
        guard let videoInfo = IMFileManager.shared.getVideoInfo(from: videoURL) else {
            completion(.failure(IMError.custom("无法获取视频信息")))
            return
        }
        
        let fileSize = IMFileManager.shared.getFileSize(at: videoURL)
        
        // 3. 创建消息
        let message = IMMessage()
        message.clientMsgID = IMUtils.generateUUID()
        message.conversationID = conversationID
        message.messageType = .video
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 4. 先保存到本地数据库（仅本地保存，不发送到服务器）
        _ = try? database.saveMessage(message)
        notifyListeners { $0.onMessageStatusChanged(message) }
        
        // 5. 上传视频
        IMFileManager.shared.uploadFile(videoURL, fileType: .video, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let uploadResult):
                // 6. 构建消息内容
                var videoContent = IMVideoMessageContent()
                videoContent.url = uploadResult.url
                videoContent.duration = duration
                videoContent.size = fileSize
                videoContent.format = uploadResult.format
                videoContent.localPath = videoURL.path
                videoContent.width = Int(videoInfo.size.width)
                videoContent.height = Int(videoInfo.size.height)
                
                // 7. 上传封面（如果有）
                if let thumbURL = thumbnailURL {
                    IMFileManager.shared.uploadFile(thumbURL, fileType: .image) { thumbResult in
                        if case .success(let thumbUploadResult) = thumbResult {
                            videoContent.snapshotUrl = thumbUploadResult.url
                            videoContent.snapshotPath = thumbURL.path
                        }
                        
                        // 8. 更新消息并发送到服务器
                        if let jsonData = try? JSONEncoder().encode(videoContent),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            message.content = jsonString
                            _ = try? self.database.saveMessage(message)
                            
                            // 上传成功后，发送到服务器
                            _ = try? self.sendMessage(message)
                            
                            completion(.success(message))
                        }
                    }
                } else {
                    // 没有封面，直接更新消息并发送到服务器
                    if let jsonData = try? JSONEncoder().encode(videoContent),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        message.content = jsonString
                        _ = try? self.database.saveMessage(message)
                        
                        // 上传成功后，发送到服务器
                        _ = try? self.sendMessage(message)
                        
                        completion(.success(message))
                    }
                }
                
            case .failure(let error):
                message.status = .failed
                _ = try? self.database.saveMessage(message)
                self.notifyListeners { $0.onMessageStatusChanged(message) }
                completion(.failure(error))
            }
        }
    }
    
    /// 发送视频消息（带压缩和封面）
    public func sendVideoMessageWithCompression(
        videoURL: URL,
        duration: Int,
        conversationID: String,
        compressionConfig: IMVideoCompressionConfig = .default,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    ) {
        // 1. 压缩视频
        IMFileManager.shared.compressVideo(at: videoURL, config: compressionConfig, progressHandler: { progress in
            // 压缩进度占 50%
            let overallProgress = IMFileTransferProgress(
                taskID: UUID().uuidString,
                totalBytes: 100,
                completedBytes: Int64(progress * 50),
                speed: 0,
                startTime: Date()
            )
            progressHandler?(overallProgress)
        }) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let compressedURL):
                // 2. 使用压缩后的视频发送（带封面）
                self.sendVideoMessageWithThumbnail(
                    videoURL: compressedURL,
                    duration: duration,
                    conversationID: conversationID,
                    progressHandler: { progress in
                        // 上传进度占 50%
                        let overallProgress = IMFileTransferProgress(
                            taskID: progress.taskID,
                            totalBytes: progress.totalBytes,
                            completedBytes: progress.completedBytes / 2 + 50,
                            speed: progress.speed,
                            startTime: progress.startTime
                        )
                        progressHandler?(overallProgress)
                    },
                    completion: completion
                )
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 可断点续传的文件下载
    public func downloadMediaFileResumable(
        from message: IMMessage,
        taskID: String? = nil,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> String {
        guard let jsonData = message.content.data(using: .utf8) else {
            completion(.failure(IMError.invalidContent))
            return ""
        }
        
        var url: String?
        
        switch message.messageType {
        case .image:
            if let content = try? JSONDecoder().decode(IMImageMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .audio:
            if let content = try? JSONDecoder().decode(IMAudioMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .video:
            if let content = try? JSONDecoder().decode(IMVideoMessageContent.self, from: jsonData) {
                url = content.url
            }
        case .file:
            if let content = try? JSONDecoder().decode(IMFileMessageContent.self, from: jsonData) {
                url = content.url
            }
        default:
            completion(.failure(IMError.unsupportedMessageType))
            return ""
        }
        
        guard let downloadURL = url else {
            completion(.failure(IMError.invalidURL))
            return ""
        }
        
        // 将 IMMessageType 转换为 IMFileType
        let fileType: IMFileType = {
            switch message.messageType {
            case .image:
                return .image
            case .audio:
                return .audio
            case .video:
                return .video
            case .file:
                return .file
            default:
                return .file
            }
        }()
        
        // 使用断点续传下载
        return IMFileManager.shared.downloadFileResumable(
            from: downloadURL,
            fileType: fileType,
            taskID: taskID,
            progressHandler: progressHandler
        ) { result in
            switch result {
            case .success(let downloadResult):
                completion(.success(downloadResult.localPath))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}


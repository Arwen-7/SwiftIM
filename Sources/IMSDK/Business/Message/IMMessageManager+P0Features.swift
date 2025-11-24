/// IMMessageManager+P0Features - P0 功能扩展（消息撤回 + 已读回执）
/// 实现日期：2025-10-25

import Foundation

// MARK: - 消息撤回

extension IMMessageManager {
    
    /// 撤回消息（同步方法）
    /// - Parameter messageID: 消息 ID
    /// - Returns: 请求是否发送成功（.success 表示请求已发送，但消息还未真正撤回）
    /// - Important: 此方法只负责发送撤回请求，实际的撤回结果会通过 WebSocket 推送通知。
    ///              所有用户（包括发送者）都会收到推送，并通过 `handleRevokeNotification` 更新本地状态。
    /// - Note: UI 层应监听 `onMessageRevoked` 回调来更新界面，而不是依赖此方法的返回值
    @discardableResult
    public func revokeMessage(messageID: String) -> Result<Void, IMError> {
        // 1. 从数据库获取消息
        guard let message = database.getMessage(messageID: messageID) else {
            return .failure(.databaseError("Message not found"))
        }
        
        // 2. 检查是否是发送者
        guard message.senderID == userID else {
            return .failure(.permissionDenied)
        }
        
        // 3. 检查时间限制（2 分钟内）
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsed = currentTime - message.sendTime
        let revokeTimeLimit: Int64 = 2 * 60 * 1000  // 2 分钟
        
        guard elapsed <= revokeTimeLimit else {
            return .failure(.invalidParameter("Revoke time expired (must within 2 minutes)"))
        }
        
        // 4. 发送撤回请求到服务器（立即返回）
        let result = sendRevokeRequest(
            messageID: messageID,
            conversationID: message.conversationID
        )
        
        // ⚠️ 重要提示：
        // 返回 .success 只表示请求已发送，消息还未真正撤回！
        // 真正的撤回会在以下流程中完成：
        // 1. 服务器收到请求并处理
        // 2. 服务器验证权限和时间
        // 3. 服务器通过 WebSocket 推送撤回通知给所有相关用户
        // 4. 客户端收到推送后调用 handleRevokeNotification() 更新本地状态
        
        return result
    }
    
    /// 处理撤回消息通知（来自 WebSocket/TCP 推送）
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - revokerID: 撤回者 ID
    ///   - revokeTime: 撤回时间（毫秒时间戳）
    internal func handleRevokeNotification(messageID: String, revokerID: String, revokeTime: Int64) {
        // 1. 更新本地数据库
        updateMessageAsRevoked(
            messageID: messageID,
            revokerID: revokerID,
            revokeTime: revokeTime
        )
        
        // 2. 获取更新后的消息
        guard let message = database.getMessage(messageID: messageID) else {
            return
        }
        
        // 3. 通知监听者
        notifyListeners { listener in
            listener.onMessageRevoked(message: message)
        }
        
        // 4. 更新会话最后一条消息（如果是最后一条）
        updateConversationIfNeeded(message: message)
        
        IMLogger.shared.info("Message revoked: \(messageID) by \(revokerID)")
    }
    
    /// 更新消息为已撤回状态
    private func updateMessageAsRevoked(messageID: String, revokerID: String, revokeTime: Int64) {
        do {
            try database.revokeMessage(messageID: messageID, revokerID: revokerID, revokeTime: revokeTime)
        } catch {
            IMLogger.shared.error("Failed to update message as revoked: \(error)")
        }
    }
    
    /// 发送撤回请求到服务器（同步方法）
    private func sendRevokeRequest(
        messageID: String,
        conversationID: String
    ) -> Result<Void, IMError> {
        // 使用 Protobuf 构建撤回请求
        var protoRequest = Im_Protocol_RevokeMessageRequest()
        protoRequest.serverMsgID = messageID  // ✅ 使用 serverMsgID
        protoRequest.conversationID = conversationID
        
        // 序列化为二进制数据
        guard let requestData = try? protoRequest.serializedData() else {
            return .failure(.invalidData)
        }
        
        // 通过 onSendData 回调发送（由 IMClient 注入）
        guard let onSendData = onSendData else {
            return .failure(.notConnected)
        }
        
        // 发送数据
        let success = onSendData(requestData, .revokeMsgReq)
        if success {
            // ✅ 数据已提交到发送队列
            return .success(())
        } else {
            // ❌ 发送失败（连接断开或队列满）
            return .failure(.sendFailed)
        }
        
        // ⚠️ 注意：
        // 返回 .success 只表示请求已成功提交到发送队列
        // 真正的撤回结果会通过 WebSocket 推送返回（handleRevokeNotification）
    }
}

// MARK: - 消息已读回执

extension IMMessageManager {
    
    /// 标记消息为已读
    /// - Parameters:
    ///   - messageIDs: 消息 ID 列表
    ///   - conversationID: 会话 ID
    public func markMessagesAsRead(
        messageIDs: [String],
        conversationID: String
    ) {
        // 1. 更新本地数据库
        do {
            try database.markMessagesAsRead(messageIDs: messageIDs)
        } catch {
            IMLogger.shared.error("Failed to mark messages as read: \(error)")
            return
        }
        
        // 2. 发送已读回执到服务器
        sendReadReceipt(messageIDs: messageIDs, conversationID: conversationID)
        
        // 3. 清除会话未读数
        clearConversationUnreadCount(conversationID: conversationID)
    }
    
    /// 处理收到的已读回执通知
    /// - Parameter notification: 已读回执通知
    internal func handleReadReceiptNotification(_ notification: IMReadReceiptNotification) {
        // 更新消息已读状态
        for messageID in notification.messageIDs {
            do {
                if notification.conversationType == .single {
                    // 单聊：标记为已读
                    try database.markMessagesAsRead(messageIDs: [messageID])
                } else {
                    // 群聊：更新已读列表
                    try database.updateMessageReadStatus(
                        messageID: messageID,
                        readerID: notification.readerID,
                        readTime: notification.readTime
                    )
                }
            } catch {
                IMLogger.shared.error("Failed to update message read status: \(error)")
            }
        }
        
        // 通知监听者
        notifyListeners { listener in
            listener.onMessageReadReceiptReceived(conversationID: notification.conversationID, messageIDs: notification.messageIDs)
        }
        
        IMLogger.shared.info("Read receipt processed: \(notification.messageIDs.count) messages by \(notification.readerID)")
    }
    
    /// 发送已读回执到服务器
    private func sendReadReceipt(messageIDs: [String], conversationID: String) {
        // 使用 Protobuf 构建已读回执请求
        var protoRequest = Im_Protocol_ReadReceiptRequest()
        protoRequest.serverMsgIds = messageIDs  // ✅ 使用 serverMsgIds
        protoRequest.conversationID = conversationID
        
        // 序列化为二进制数据
        guard let requestData = try? protoRequest.serializedData() else {
            IMLogger.shared.error("Failed to serialize read receipt request")
            return
        }
        
        // 通过 onSendData 回调发送（由 IMClient 注入）
        guard let onSendData = onSendData else {
            IMLogger.shared.warning("onSendData not set, cannot send read receipt")
            return
        }
        
        // 发送数据
        let success = onSendData(requestData, .readReceiptReq)
        if !success {
            IMLogger.shared.warning("Failed to send read receipt")
        }
    }
    
    /// 清除会话未读数
    private func clearConversationUnreadCount(conversationID: String) {
        do {
            try database.clearUnreadCount(conversationID: conversationID)
        } catch {
            IMLogger.shared.error("Failed to clear unread count: \(error)")
        }
    }
    
    /// 更新会话（如果需要）
    private func updateConversationIfNeeded(message: IMMessage) {
        // 如果是会话的最后一条消息，需要更新会话
        guard let conversation = database.getConversation(conversationID: message.conversationID) else {
            return
        }
        // ✅ 只比较 clientMsgID（因为 clientMsgID 肯定会有）
        guard conversation.lastMessage?.clientMsgID == message.clientMsgID else {
            return
        }
        
        // 更新会话的最后一条消息（OpenIM 方案）
        do {
            try database.updateConversationLastMessage(
                conversationID: conversation.conversationID,
                message: message
            )
        } catch {
            IMLogger.shared.error("Failed to update conversation: \(error)")
        }
    }
}

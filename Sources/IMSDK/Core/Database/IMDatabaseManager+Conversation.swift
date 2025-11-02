/// IMDatabaseManager+Conversation - 会话相关数据库操作
/// 实现会话的 CRUD 操作

import Foundation
import SQLite3

// MARK: - Conversation Operations

extension IMDatabaseManager {
    
    // MARK: - Save Conversation
    
    /// 保存会话
    /// - Parameter conversation: 会话对象
    public func saveConversation(_ conversation: IMConversation) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let exists = try conversationExists(conversationID: conversation.conversationID)
        
        if exists {
            try updateConversation(conversation)
        } else {
            try insertConversation(conversation)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save conversation", elapsed: elapsed)
    }
    
    /// 批量保存会话
    /// - Parameter conversations: 会话数组
    @discardableResult
    public func saveConversations(_ conversations: [IMConversation]) throws -> Int {
        guard !conversations.isEmpty else { return 0 }
        
        let startTime = Date()
        var count = 0
        
        try transaction {
            for conversation in conversations {
                try saveConversation(conversation)
                count += 1
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save \(count) conversations", elapsed: elapsed)
        
        return count
    }
    
    // MARK: - Insert/Update
    
    /// 插入会话
    private func insertConversation(_ conversation: IMConversation) throws {
        let sql = """
            INSERT INTO conversations (
                conversation_id, conversation_type, target_id, show_name, face_url,
                latest_msg, latest_msg_send_time,
                unread_count, last_read_time,
                is_pinned, is_muted, is_private, draft, draft_time, extra,
                create_time, update_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare insert: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 根据会话类型决定 target_id (单聊用 userID，群聊用 groupID)
        let targetID = conversation.conversationType == .single ? conversation.userID : conversation.groupID
        
        sqlite3_bind_text(statement, 1, (conversation.conversationID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(conversation.conversationType.rawValue))
        sqlite3_bind_text(statement, 3, (targetID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (conversation.showName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (conversation.faceURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (conversation.latestMsg as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 7, conversation.latestMsgSendTime)
        sqlite3_bind_int(statement, 8, Int32(conversation.unreadCount))
        sqlite3_bind_int64(statement, 9, conversation.lastReadTime)
        sqlite3_bind_int(statement, 10, conversation.isPinned ? 1 : 0)
        sqlite3_bind_int(statement, 11, conversation.isMuted ? 1 : 0)
        sqlite3_bind_int(statement, 12, conversation.isPrivate ? 1 : 0)
        sqlite3_bind_text(statement, 13, (conversation.draftText as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 14, conversation.draftTime)
        sqlite3_bind_text(statement, 15, (conversation.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 16, currentTime)
        sqlite3_bind_int64(statement, 17, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to insert conversation: \(getErrorMessage())")
        }
    }
    
    /// 更新会话
    private func updateConversation(_ conversation: IMConversation) throws {
        let sql = """
            UPDATE conversations SET
                conversation_type = ?, target_id = ?, show_name = ?, face_url = ?,
                latest_msg = ?, latest_msg_send_time = ?,
                unread_count = ?, last_read_time = ?,
                is_pinned = ?, is_muted = ?, is_private = ?,
                draft = ?, draft_time = ?, extra = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 根据会话类型决定 target_id (单聊用 userID，群聊用 groupID)
        let targetID = conversation.conversationType == .single ? conversation.userID : conversation.groupID
        
        sqlite3_bind_int(statement, 1, Int32(conversation.conversationType.rawValue))
        sqlite3_bind_text(statement, 2, (targetID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (conversation.showName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (conversation.faceURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (conversation.latestMsg as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 6, conversation.latestMsgSendTime)
        sqlite3_bind_int(statement, 7, Int32(conversation.unreadCount))
        sqlite3_bind_int64(statement, 8, conversation.lastReadTime)
        sqlite3_bind_int(statement, 9, conversation.isPinned ? 1 : 0)
        sqlite3_bind_int(statement, 10, conversation.isMuted ? 1 : 0)
        sqlite3_bind_int(statement, 11, conversation.isPrivate ? 1 : 0)
        sqlite3_bind_text(statement, 12, (conversation.draftText as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 13, conversation.draftTime)
        sqlite3_bind_text(statement, 14, (conversation.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 15, currentTime)
        sqlite3_bind_text(statement, 16, (conversation.conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update conversation: \(getErrorMessage())")
        }
    }
    
    // MARK: - Query
    
    /// 获取会话
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 会话对象
    public func getConversation(conversationID: String) -> IMConversation? {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM conversations WHERE conversation_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let conversation = parseConversation(from: statement)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get conversation", elapsed: elapsed)
        
        return conversation
    }
    
    /// 获取所有会话
    /// - Parameter sortByTime: 是否按时间排序
    /// - Returns: 会话数组
    public func getAllConversations(sortByTime: Bool = true) -> [IMConversation] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let orderBy = sortByTime ? "ORDER BY is_pinned DESC, last_message_time DESC" : ""
        let sql = "SELECT * FROM conversations \(orderBy);"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var conversations: [IMConversation] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let conversation = parseConversation(from: statement)
            conversations.append(conversation)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(conversations.count) conversations", elapsed: elapsed)
        
        return conversations
    }
    
    /// 获取总未读数
    /// - Returns: 总未读数
    public func getTotalUnreadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT SUM(unread_count) FROM conversations WHERE is_muted = 0;"
        
        if let result = try? queryScalar(sql: sql) as? Int64 {
            return Int(result)
        }
        
        return 0
    }
    
    // MARK: - Update Specific Fields
    
    /// 更新未读数
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - unreadCount: 未读数
    public func updateConversationUnreadCount(conversationID: String, unreadCount: Int) throws {
        let sql = """
            UPDATE conversations SET
                unread_count = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_int(statement, 1, Int32(unreadCount))
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update unread count: \(getErrorMessage())")
        }
    }
    
    /// 清空未读数
    /// - Parameter conversationID: 会话 ID
    public func clearUnreadCount(conversationID: String) throws {
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        let sql = """
            UPDATE conversations SET
                unread_count = 0,
                last_read_time = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int64(statement, 1, currentTime)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to clear unread count: \(getErrorMessage())")
        }
    }
    
    /// 设置置顶
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isPinned: 是否置顶
    public func setConversationPinned(conversationID: String, isPinned: Bool) throws {
        let sql = """
            UPDATE conversations SET
                is_pinned = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_int(statement, 1, isPinned ? 1 : 0)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to set pinned: \(getErrorMessage())")
        }
    }
    
    /// 设置免打扰
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isMuted: 是否免打扰
    public func setConversationMuted(conversationID: String, isMuted: Bool) throws {
        let sql = """
            UPDATE conversations SET
                is_muted = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_int(statement, 1, isMuted ? 1 : 0)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to set muted: \(getErrorMessage())")
        }
    }
    
    /// 更新草稿
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - draft: 草稿内容
    public func updateDraft(conversationID: String, draft: String) throws {
        let sql = """
            UPDATE conversations SET
                draft = ?,
                update_time = ?
            WHERE conversation_id = ?;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (draft as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update draft: \(getErrorMessage())")
        }
    }
    
    // MARK: - Delete
    
    /// 删除会话
    /// - Parameter conversationID: 会话 ID
    public func deleteConversation(conversationID: String) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "DELETE FROM conversations WHERE conversation_id = ?;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare delete: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to delete conversation: \(getErrorMessage())")
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete conversation", elapsed: elapsed)
    }
    
    // MARK: - Helper Methods
    
    /// 检查会话是否存在
    private func conversationExists(conversationID: String) throws -> Bool {
        let sql = "SELECT 1 FROM conversations WHERE conversation_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    /// 解析会话
    private func parseConversation(from statement: OpaquePointer?) -> IMConversation {
        let conversation = IMConversation()
        
        conversation.conversationID = String(cString: sqlite3_column_text(statement, 0))
        conversation.conversationType = IMConversationType(rawValue: Int(sqlite3_column_int(statement, 1))) ?? .single
        
        // 根据会话类型设置 targetID 到 userID 或 groupID
        let targetID = String(cString: sqlite3_column_text(statement, 2))
        if conversation.conversationType == .single {
            conversation.userID = targetID
        } else {
            conversation.groupID = targetID
        }
        
        // show_name
        if let showNamePtr = sqlite3_column_text(statement, 3) {
            conversation.showName = String(cString: showNamePtr)
        }
        
        // face_url
        if let faceURLPtr = sqlite3_column_text(statement, 4) {
            conversation.faceURL = String(cString: faceURLPtr)
        }
        
        // 完整消息 JSON（OpenIM 方案）
        if let latestMsgPtr = sqlite3_column_text(statement, 5) {
            conversation.latestMsg = String(cString: latestMsgPtr)
        }
        
        conversation.latestMsgSendTime = sqlite3_column_int64(statement, 6)
        conversation.unreadCount = Int(sqlite3_column_int(statement, 7))
        conversation.lastReadTime = sqlite3_column_int64(statement, 8)
        conversation.isPinned = sqlite3_column_int(statement, 9) != 0
        conversation.isMuted = sqlite3_column_int(statement, 10) != 0
        conversation.isPrivate = sqlite3_column_int(statement, 11) != 0
        
        if let draftPtr = sqlite3_column_text(statement, 12) {
            conversation.draftText = String(cString: draftPtr)
        }
        
        conversation.draftTime = sqlite3_column_int64(statement, 13)
        
        if let extraPtr = sqlite3_column_text(statement, 14) {
            conversation.extra = String(cString: extraPtr)
        }
        
        return conversation
    }
    
    // MARK: - 协议补充方法
    
    /// 更新会话最后一条消息（OpenIM 方案）
    public func updateConversationLastMessage(conversationID: String, message: IMMessage) throws {
        // 序列化消息为 JSON
        let encoder = JSONEncoder()
        guard let messageData = try? encoder.encode(message),
              let messageJSON = String(data: messageData, encoding: .utf8) else {
            throw IMError.databaseError("Failed to serialize message to JSON")
        }
        
        let sql = """
        UPDATE conversations 
        SET latest_msg = ?,
            latest_msg_send_time = ?,
            update_time = ?
        WHERE conversation_id = ?;
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (messageJSON as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, message.sendTime)
        sqlite3_bind_int64(statement, 3, IMUtils.currentTimeMillis())
        sqlite3_bind_text(statement, 4, (conversationID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update conversation last message: \(getErrorMessage())")
        }
    }
    
    /// 增加未读数
    public func incrementUnreadCount(conversationID: String, by count: Int) throws {
        let sql = """
        UPDATE conversations 
        SET unread_count = unread_count + ?,
            update_time = ?
        WHERE conversation_id = ?;
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(count))
        sqlite3_bind_int64(statement, 2, IMUtils.currentTimeMillis())
        sqlite3_bind_text(statement, 3, conversationID, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update: \(getErrorMessage())")
        }
    }
    
    /// 获取会话未读数
    public func getUnreadCount(conversationID: String) -> Int {
        let sql = "SELECT unread_count FROM conversations WHERE conversation_id = ?;"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
}


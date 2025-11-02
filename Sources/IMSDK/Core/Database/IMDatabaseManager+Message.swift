/// IMDatabaseManager+Message - 消息相关数据库操作
/// 实现消息的 CRUD 操作

import Foundation
import SQLite3

// MARK: - Message Operations

extension IMDatabaseManager {
    
    // MARK: - Save Message
    
    /// 保存单条消息（WAL 模式，~5ms）
    /// - Parameter message: 消息对象
    /// - Returns: 保存结果
    @discardableResult
    public func saveMessage(_ message: IMMessage) throws -> IMMessageSaveResult {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        // 检查消息是否已存在
        let exists = try messageExists(messageID: message.messageID)
        
        let result: IMMessageSaveResult
        
        if exists {
            // 更新现有消息
            let shouldUpdate = try shouldUpdateMessage(messageID: message.messageID, newMessage: message)
            if shouldUpdate {
                try updateMessage(message)
                result = .updated
            } else {
                result = .skipped
            }
        } else {
            // 插入新消息
            try insertMessage(message)
            result = .inserted
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save message (\(result))", elapsed: elapsed)
        
        return result
    }
    
    /// 批量保存消息（WAL 模式，~1.5ms/条）
    /// - Parameter messages: 消息数组
    /// - Returns: 批量保存统计
    @discardableResult
    public func saveMessages(_ messages: [IMMessage]) throws -> IMMessageBatchSaveStats {
        guard !messages.isEmpty else {
            return IMMessageBatchSaveStats(
                insertedCount: 0,
                updatedCount: 0,
                skippedCount: 0
            )
        }
        
        let startTime = Date()
        
        var insertedCount = 0
        var updatedCount = 0
        var skippedCount = 0
        
        try transaction {
            for message in messages {
                let result = try saveMessage(message)
                
                switch result {
                case .inserted:
                    insertedCount += 1
                case .updated:
                    updatedCount += 1
                case .skipped:
                    skippedCount += 1
                }
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let avgTime = elapsed / Double(messages.count) * 1000
        
        IMLogger.shared.info("""
            Batch save messages:
              - total: \(messages.count)
              - inserted: \(insertedCount)
              - updated: \(updatedCount)
              - skipped: \(skippedCount)
              - time: \(String(format: "%.2f", elapsed * 1000))ms
              - avg: \(String(format: "%.2f", avgTime))ms/msg
            """)
        
        return IMMessageBatchSaveStats(
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )
    }
    
    // MARK: - Insert/Update
    
    /// 插入消息
    private func insertMessage(_ message: IMMessage) throws {
        let sql = """
            INSERT INTO messages (
                message_id, client_msg_id,
                conversation_id, sender_id, receiver_id, group_id,
                message_type, content, extra,
                status, direction, send_time, server_time, seq,
                is_read, is_deleted, is_revoked,
                create_time, update_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare insert: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // 绑定参数
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (message.messageID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (message.clientMsgID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (message.conversationID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (message.senderID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (message.receiverID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (message.groupID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 7, Int32(message.messageType.rawValue))
        sqlite3_bind_text(statement, 8, (message.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 9, (message.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 10, Int32(message.status.rawValue))
        sqlite3_bind_int(statement, 11, Int32(message.direction.rawValue))
        sqlite3_bind_int64(statement, 12, message.sendTime)
        sqlite3_bind_int64(statement, 13, message.serverTime)
        sqlite3_bind_int64(statement, 14, message.seq)
        sqlite3_bind_int(statement, 15, message.isRead ? 1 : 0)
        sqlite3_bind_int(statement, 16, message.isDeleted ? 1 : 0)
        sqlite3_bind_int(statement, 17, message.isRevoked ? 1 : 0)
        sqlite3_bind_int64(statement, 18, currentTime)
        sqlite3_bind_int64(statement, 19, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to insert message: \(getErrorMessage())")
        }
    }
    
    /// 更新消息
    private func updateMessage(_ message: IMMessage) throws {
        let sql = """
            UPDATE messages SET
                client_msg_id = ?,
                content = ?, extra = ?,
                status = ?, server_time = ?, seq = ?,
                is_read = ?, is_deleted = ?, is_revoked = ?,
                update_time = ?
            WHERE message_id = ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (message.clientMsgID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (message.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (message.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 4, Int32(message.status.rawValue))
        sqlite3_bind_int64(statement, 5, message.serverTime)
        sqlite3_bind_int64(statement, 6, message.seq)
        sqlite3_bind_int(statement, 7, message.isRead ? 1 : 0)
        sqlite3_bind_int(statement, 8, message.isDeleted ? 1 : 0)
        sqlite3_bind_int(statement, 9, message.isRevoked ? 1 : 0)
        sqlite3_bind_int64(statement, 10, currentTime)
        sqlite3_bind_text(statement, 11, (message.messageID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update message: \(getErrorMessage())")
        }
    }
    
    // MARK: - Query
    
    /// 获取单条消息
    /// - Parameter messageID: 消息 ID
    /// - Returns: 消息对象
    public func getMessage(messageID: String) -> IMMessage? {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM messages WHERE message_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (messageID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let message = parseMessage(from: statement)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get message", elapsed: elapsed)
        
        return message
    }
    
    /// 获取会话消息列表
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - limit: 数量限制
    ///   - offset: 偏移量
    /// - Returns: 消息数组
    public func getMessages(
        conversationID: String,
        limit: Int = 20,
        offset: Int = 0
    ) -> [IMMessage] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            SELECT * FROM messages
            WHERE conversation_id = ?
            ORDER BY send_time DESC
            LIMIT ? OFFSET ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(limit))
        sqlite3_bind_int(statement, 3, Int32(offset))
        
        var messages: [IMMessage] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let message = parseMessage(from: statement)
            messages.append(message)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(messages.count) messages", elapsed: elapsed)
        
        return messages
    }
    
    /// 获取历史消息（时间分页）
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - beforeTime: 时间戳之前
    ///   - limit: 数量限制
    /// - Returns: 消息数组
    public func getHistoryMessages(
        conversationID: String,
        beforeTime: Int64,
        limit: Int
    ) throws -> [IMMessage] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            SELECT * FROM messages
            WHERE conversation_id = ? AND send_time < ?
            ORDER BY send_time DESC
            LIMIT ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, beforeTime)
        sqlite3_bind_int(statement, 3, Int32(limit))
        
        var messages: [IMMessage] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let message = parseMessage(from: statement)
            messages.append(message)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(messages.count) history messages", elapsed: elapsed)
        
        return messages
    }
    
    // MARK: - Helper Methods
    
    /// 检查消息是否存在
    private func messageExists(messageID: String) throws -> Bool {
        let sql = "SELECT 1 FROM messages WHERE message_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (messageID as NSString).utf8String, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    /// 判断是否应该更新消息
    private func shouldUpdateMessage(messageID: String, newMessage: IMMessage) throws -> Bool {
        guard let existing = getMessage(messageID: messageID) else {
            return false
        }
        
        // 状态变化
        if existing.status != newMessage.status {
            return true
        }
        
        // 服务器时间更新
        if existing.serverTime != newMessage.serverTime && newMessage.serverTime > 0 {
            return true
        }
        
        // 序列号更新
        if existing.seq != newMessage.seq && newMessage.seq > 0 {
            return true
        }
        
        // 内容变化
        if existing.content != newMessage.content {
            return true
        }
        
        // 已读状态变化
        if existing.isRead != newMessage.isRead {
            return true
        }
        
        // 删除状态变化
        if existing.isDeleted != newMessage.isDeleted {
            return true
        }
        
        // 撤回状态变化
        if existing.isRevoked != newMessage.isRevoked {
            return true
        }
        
        return false
    }
    
    /// 解析消息
    private func parseMessage(from statement: OpaquePointer?) -> IMMessage {
        let message = IMMessage()
        
        message.messageID = String(cString: sqlite3_column_text(statement, 0))
        
        if let clientMsgID = sqlite3_column_text(statement, 1) {
            message.clientMsgID = String(cString: clientMsgID)
        }
        
        message.conversationID = String(cString: sqlite3_column_text(statement, 2))
        message.senderID = String(cString: sqlite3_column_text(statement, 3))
        
        if let receiverID = sqlite3_column_text(statement, 4) {
            message.receiverID = String(cString: receiverID)
        }
        
        if let groupID = sqlite3_column_text(statement, 5) {
            message.groupID = String(cString: groupID)
        }
        
        message.messageType = IMMessageType(rawValue: Int(sqlite3_column_int(statement, 6))) ?? .text
        message.content = String(cString: sqlite3_column_text(statement, 7))
        
        if let extra = sqlite3_column_text(statement, 8) {
            message.extra = String(cString: extra)
        }
        
        message.status = IMMessageStatus(rawValue: Int(sqlite3_column_int(statement, 9))) ?? .sending
        message.direction = IMMessageDirection(rawValue: Int(sqlite3_column_int(statement, 10))) ?? .send
        message.sendTime = sqlite3_column_int64(statement, 11)
        message.serverTime = sqlite3_column_int64(statement, 12)
        message.seq = sqlite3_column_int64(statement, 13)
        message.isRead = sqlite3_column_int(statement, 14) != 0
        message.isDeleted = sqlite3_column_int(statement, 15) != 0
        message.isRevoked = sqlite3_column_int(statement, 16) != 0
        
        return message
    }
    
    // MARK: - Delete
    
    /// 删除消息
    /// - Parameter messageID: 消息 ID
    public func deleteMessage(messageID: String) throws {
        let startTime = Date()
        
        try execute(sql: "DELETE FROM messages WHERE message_id = '\(messageID)';")
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete message", elapsed: elapsed)
    }
    
    /// 清空所有消息
    public func clearAllMessages() throws {
        let startTime = Date()
        
        try execute(sql: "DELETE FROM messages;")
        try execute(sql: "VACUUM;")  // 释放空间
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Clear all messages", elapsed: elapsed)
    }
    
    // MARK: - P0 Features
    
    /// 标记消息为已读
    /// - Parameter messageIDs: 消息 ID 列表
    public func markMessagesAsRead(messageIDs: [String]) throws {
        guard !messageIDs.isEmpty else { return }
        
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        // 开启事务
        try execute(sql: "BEGIN TRANSACTION;")
        
        do {
            for messageID in messageIDs {
                let sql = """
                UPDATE messages 
                SET is_read = 1, status = \(IMMessageStatus.read.rawValue), update_time = \(IMUtils.currentTimeMillis())
                WHERE message_id = '\(messageID)';
                """
                try execute(sql: sql)
            }
            
            // 提交事务
            try execute(sql: "COMMIT;")
            
            let elapsed = Date().timeIntervalSince(startTime)
            IMLogger.shared.database("Marked \(messageIDs.count) messages as read", elapsed: elapsed)
        } catch {
            // 回滚事务
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }
    
    /// 撤回消息
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - revokerID: 撤回者 ID
    ///   - revokeTime: 撤回时间
    public func revokeMessage(messageID: String, revokerID: String, revokeTime: Int64) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
        UPDATE messages 
        SET is_revoked = 1, 
            revoked_by = '\(revokerID)', 
            revoked_time = \(revokeTime),
            update_time = \(IMUtils.currentTimeMillis())
        WHERE message_id = '\(messageID)';
        """
        
        try execute(sql: sql)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Revoked message: \(messageID)", elapsed: elapsed)
    }
    
    /// 更新消息已读状态（群聊）
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - readerID: 读取者 ID
    ///   - readTime: 读取时间
    public func updateMessageReadStatus(messageID: String, readerID: String, readTime: Int64) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        // 获取当前消息
        guard let message = getMessage(messageID: messageID) else {
            throw IMError.databaseError("Message not found: \(messageID)")
        }
        
        // 解析 read_by JSON 数组
        var readByList: [String] = []
        if !message.content.isEmpty {
            if let data = message.content.data(using: .utf8),
               let array = try? JSONDecoder().decode([String].self, from: data) {
                readByList = array
            }
        }
        
        // 添加新的读者（如果不存在）
        if !readByList.contains(readerID) {
            readByList.append(readerID)
        }
        
        // 编码为 JSON
        guard let jsonData = try? JSONEncoder().encode(readByList),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw IMError.databaseError("Failed to encode read_by list")
        }
        
        // 更新数据库
        let sql = """
        UPDATE messages 
        SET read_by = '\(jsonString.replacingOccurrences(of: "'", with: "''"))',
            read_time = \(readTime),
            update_time = \(IMUtils.currentTimeMillis())
        WHERE message_id = '\(messageID)';
        """
        
        try execute(sql: sql)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Updated read status for message: \(messageID)", elapsed: elapsed)
    }
    
    // MARK: - 协议补充方法
    
    /// 获取会话消息列表
    public func getMessages(conversationID: String, limit: Int) -> [IMMessage] {
        // 使用当前时间作为 beforeTime，获取最新消息
        let currentTime = IMUtils.currentTimeMillis()
        return (try? getHistoryMessages(conversationID: conversationID, beforeTime: currentTime, limit: limit)) ?? []
    }
    
    /// 获取指定时间之前的消息
    public func getMessagesBefore(conversationID: String, beforeTime: Int64, limit: Int) -> [IMMessage] {
        return (try? getHistoryMessages(conversationID: conversationID, beforeTime: beforeTime, limit: limit)) ?? []
    }
    
    /// 获取历史消息（分页） - 协议要求的方法签名
    public func getHistoryMessages(conversationID: String, startTime: Int64, count: Int) -> [IMMessage] {
        return (try? getHistoryMessages(conversationID: conversationID, beforeTime: startTime, limit: count)) ?? []
    }
    
    /// 更新消息状态
    public func updateMessageStatus(messageID: String, status: IMMessageStatus) throws {
        let sql = """
        UPDATE messages 
        SET status = \(status.rawValue),
            update_time = \(IMUtils.currentTimeMillis())
        WHERE message_id = '\(messageID)';
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        try execute(sql: sql)
    }
    
    /// 基于 seq 的历史消息查询
    public func getHistoryMessagesBySeq(conversationID: String, startSeq: Int64, count: Int) -> [IMMessage] {
        let sql = """
        SELECT * FROM messages
        WHERE conversation_id = '\(conversationID)' AND seq < \(startSeq)
        ORDER BY seq DESC
        LIMIT \(count);
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        
        var messages: [IMMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let message = parseMessage(from: statement)
            messages.append(message)
        }
        
        return messages.reversed()
    }
    
    /// 搜索消息
    public func searchMessages(keyword: String, conversationID: String?, limit: Int) -> [IMMessage] {
        var sql = """
        SELECT * FROM messages
        WHERE content LIKE '%\(keyword)%'
        """
        
        if let convID = conversationID {
            sql += " AND conversation_id = '\(convID)'"
        }
        
        sql += " ORDER BY send_time DESC LIMIT \(limit);"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        
        var messages: [IMMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let message = parseMessage(from: statement)
            messages.append(message)
        }
        
        return messages
    }
    
    /// 获取消息数量
    public func getHistoryMessageCount(conversationID: String) -> Int {
        let sql = "SELECT COUNT(*) FROM messages WHERE conversation_id = '\(conversationID)';"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
    
    /// 获取最大 seq
    public func getMaxSeq() -> Int64 {
        let sql = "SELECT MAX(seq) FROM messages;"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        
        return 0
    }
    
    /// 获取指定会话的最新消息（用于消息丢失检测）
    /// - Parameter conversationID: 会话 ID
    /// - Returns: 最新的消息，如果不存在则返回 nil
    /// - Throws: 数据库错误
    public func getLatestMessage(conversationID: String) throws -> IMMessage? {
        let sql = """
            SELECT message_id, conversation_id, sender_id, receiver_id, group_id,
                   type, content, status, direction, seq, create_time, send_time,
                   is_revoked, revoked_by, revoked_time
            FROM messages
            WHERE conversation_id = ?
              AND seq > 0
            ORDER BY seq DESC
            LIMIT 1;
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw IMError.databaseError("Failed to prepare query for latest message: \(errorMsg)")
        }
        defer { sqlite3_finalize(statement) }
        
        // 绑定参数
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        // 执行查询
        if sqlite3_step(statement) == SQLITE_ROW {
            return parseMessage(from: statement)
        }
        
        return nil
    }
}


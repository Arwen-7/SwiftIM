/// IMDatabaseManager+Extensions - 数据库管理器扩展
/// 实现 IMDatabaseProtocol 中缺失的方法

import Foundation
import SQLite3

extension IMDatabaseManager {
    
    // MARK: - 同步配置操作
    
    /// 设置同步状态
    public func setSyncingState(userID: String, isSyncing: Bool) throws {
        guard let db = db else {
            throw IMError.databaseError("Database not initialized")
        }
        
        // ✅ 使用 INSERT OR REPLACE 确保记录一定会被保存
        let sql = """
        INSERT OR REPLACE INTO sync_config (user_id, is_syncing, last_sync_time, last_sync_seq)
        VALUES (?, ?, ?, COALESCE((SELECT last_sync_seq FROM sync_config WHERE user_id = ?), 0))
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare statement")
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, isSyncing ? 1 : 0)
        sqlite3_bind_int64(statement, 3, IMUtils.currentTimeMillis())
        sqlite3_bind_text(statement, 4, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to execute statement")
        }
    }
    
    /// 重置同步配置
    public func resetSyncConfig(userID: String) throws {
        guard let db = db else {
            throw IMError.databaseError("Database not initialized")
        }
        
        let sql = """
        DELETE FROM sync_config WHERE user_id = ?
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare statement")
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to execute statement")
        }
    }
    
    // MARK: - 消息时间查询
    
    /// 获取最旧消息时间
    public func getOldestMessageTime(conversationID: String) -> Int64 {
        guard let db = db else { return 0 }
        
        let sql = """
        SELECT MIN(send_time) FROM messages WHERE conversation_id = ? AND is_deleted = 0
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        
        return 0
    }
    
    /// 获取最新消息时间
    public func getLatestMessageTime(conversationID: String) -> Int64 {
        guard let db = db else { return 0 }
        
        let sql = """
        SELECT MAX(send_time) FROM messages WHERE conversation_id = ? AND is_deleted = 0
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        sqlite3_bind_text(statement, 1, (conversationID as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        
        return 0
    }
    
    // MARK: - 消息范围查询
    
    /// 获取指定时间范围内的消息
    public func getMessagesInTimeRange(
        conversationID: String,
        startTime: Int64,
        endTime: Int64
    ) throws -> [IMMessage] {
        // TODO: 实现完整的查询逻辑
        // 暂时返回空数组以通过编译
        return []
    }
    
    /// 按发送者搜索消息
    public func searchMessagesBySender(
        senderID: String,
        conversationID: String?,
        limit: Int
    ) throws -> [IMMessage] {
        // TODO: 实现完整的查询逻辑
        // 暂时返回空数组以通过编译
        return []
    }
    
    /// 搜索消息数量
    public func searchMessageCount(
        keyword: String,
        conversationID: String?,
        timeRange: (start: Int64, end: Int64)?
    ) -> Int {
        // TODO: 实现完整的查询逻辑
        // 暂时返回0以通过编译
        return 0
    }
}


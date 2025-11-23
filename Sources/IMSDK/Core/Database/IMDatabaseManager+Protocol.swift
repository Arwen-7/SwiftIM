/// IMDatabaseManager+Protocol - 实现数据库协议
///
/// 让 SQLite 数据库管理器遵循统一的数据库协议

import Foundation
import SQLite3

extension IMDatabaseManager {
    
    // MARK: - 同步配置操作（补充实现）
    
    public func saveSyncConfig(_ config: IMSyncConfig) throws {
        let sql = """
        INSERT OR REPLACE INTO sync_config (
            user_id, last_sync_seq, last_sync_time, is_syncing
        ) VALUES (?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare sync config insert")
        }
        
        sqlite3_bind_text(statement, 1, config.userID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, config.lastSyncSeq)
        sqlite3_bind_int64(statement, 3, config.lastSyncTime)
        sqlite3_bind_int(statement, 4, config.isSyncing ? 1 : 0)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to save sync config")
        }
    }
    
    public func getSyncConfig(userID: String) -> IMSyncConfig? {
        let sql = "SELECT user_id, last_sync_seq, last_sync_time, is_syncing FROM sync_config WHERE user_id = ?"
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(statement, 1, userID, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let config = IMSyncConfig()
        config.userID = String(cString: sqlite3_column_text(statement, 0))
        config.lastSyncSeq = sqlite3_column_int64(statement, 1)
        config.lastSyncTime = sqlite3_column_int64(statement, 2)
        config.isSyncing = sqlite3_column_int(statement, 3) == 1
        
        return config
    }
    
    public func updateLastSyncSeq(userID: String, seq: Int64) throws {
        // ✅ 使用 INSERT OR REPLACE 确保记录一定会被保存
        let sql = """
        INSERT OR REPLACE INTO sync_config (user_id, last_sync_seq, last_sync_time, is_syncing)
        VALUES (?, ?, ?, COALESCE((SELECT is_syncing FROM sync_config WHERE user_id = ?), 0))
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare sync seq update")
        }
        
        sqlite3_bind_text(statement, 1, userID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, seq)
        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970 * 1000))
        sqlite3_bind_text(statement, 4, userID, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update sync seq")
        }
    }
}


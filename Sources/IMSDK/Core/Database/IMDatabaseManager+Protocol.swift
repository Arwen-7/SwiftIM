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
            user_id, last_sync_time, is_syncing, conversation_states
        ) VALUES (?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare sync config insert")
        }
        
        // 将 conversationStates 序列化为 JSON
        let conversationStatesJSON: String
        if let jsonData = try? JSONEncoder().encode(config.conversationStates),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            conversationStatesJSON = jsonString
        } else {
            conversationStatesJSON = "{}"
        }
        
        sqlite3_bind_text(statement, 1, config.userID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, config.lastSyncTime)
        sqlite3_bind_int(statement, 3, config.isSyncing ? 1 : 0)
        sqlite3_bind_text(statement, 4, conversationStatesJSON, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to save sync config")
        }
    }
    
    public func getSyncConfig(userID: String) -> IMSyncConfig? {
        let sql = "SELECT user_id, last_sync_time, is_syncing, conversation_states FROM sync_config WHERE user_id = ?"
        
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
        config.lastSyncTime = sqlite3_column_int64(statement, 1)
        config.isSyncing = sqlite3_column_int(statement, 2) == 1
        
        // 反序列化 conversationStates
        if let jsonText = sqlite3_column_text(statement, 3) {
            let jsonString = String(cString: jsonText)
            if let jsonData = jsonString.data(using: .utf8),
               let states = try? JSONDecoder().decode([String: IMConversationSyncState].self, from: jsonData) {
                config.conversationStates = states
            }
        }
        
        return config
    }
}


/// IMDatabaseManager+Friend - 好友相关数据库操作
/// 实现好友的 CRUD 操作

import Foundation
import SQLite3

// MARK: - Friend Operations

extension IMDatabaseManager {
    
    // MARK: - Table Creation
    
    /// 创建好友表
    internal func createFriendTables() throws {
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS friends (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                friend_id TEXT NOT NULL,
                nickname TEXT,
                remark TEXT,
                source TEXT,
                create_time INTEGER NOT NULL,
                update_time INTEGER NOT NULL,
                UNIQUE(user_id, friend_id)
            );
            """)
        
        // 创建索引
        try execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_friends_user 
                ON friends(user_id);
            CREATE INDEX IF NOT EXISTS idx_friends_friend 
                ON friends(friend_id);
            """)
    }
    
    // MARK: - Save Friend
    
    /// 添加好友
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - friendID: 好友 ID
    ///   - remark: 备注
    ///   - source: 来源
    public func addFriend(userID: String, friendID: String, remark: String?, source: String?) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let exists = try friendExists(userID: userID, friendID: friendID)
        let finalRemark = remark ?? ""
        let finalSource = source ?? ""
        
        if exists {
            try updateFriend(userID: userID, friendID: friendID, remark: finalRemark, source: finalSource)
        } else {
            try insertFriend(userID: userID, friendID: friendID, remark: finalRemark, source: finalSource)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Add friend", elapsed: elapsed)
    }
    
    // MARK: - Insert/Update
    
    /// 插入好友
    private func insertFriend(userID: String, friendID: String, remark: String, source: String) throws {
        let sql = """
            INSERT INTO friends (
                user_id, friend_id, remark, source, create_time, update_time
            ) VALUES (?, ?, ?, ?, ?, ?);
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare insert: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (friendID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (remark as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 5, currentTime)
        sqlite3_bind_int64(statement, 6, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to insert friend: \(getErrorMessage())")
        }
    }
    
    /// 更新好友
    private func updateFriend(userID: String, friendID: String, remark: String, source: String) throws {
        let sql = """
            UPDATE friends SET
                remark = ?,
                source = ?,
                update_time = ?
            WHERE user_id = ? AND friend_id = ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (remark as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 3, currentTime)
        sqlite3_bind_text(statement, 4, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (friendID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update friend: \(getErrorMessage())")
        }
    }
    
    // MARK: - Query
    
    /// 获取好友列表
    /// - Parameter userID: 用户 ID
    /// - Returns: 好友用户对象数组
    public func getFriends(userID: String) -> [IMUser] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT friend_id FROM friends WHERE user_id = ? ORDER BY update_time DESC;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        var friendIDs: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let friendID = String(cString: sqlite3_column_text(statement, 0))
            friendIDs.append(friendID)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(friendIDs.count) friends", elapsed: elapsed)
        
        // 批量获取用户信息
        return getUsers(userIDs: friendIDs)
    }
    
    /// 获取好友备注
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - friendID: 好友 ID
    /// - Returns: 备注
    public func getFriendRemark(userID: String, friendID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT remark FROM friends WHERE user_id = ? AND friend_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (friendID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        if let remark = sqlite3_column_text(statement, 0) {
            return String(cString: remark)
        }
        
        return nil
    }
    
    /// 检查是否为好友
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - friendID: 好友 ID
    /// - Returns: 是否为好友
    public func isFriend(userID: String, friendID: String) -> Bool {
        do {
            return try friendExists(userID: userID, friendID: friendID)
        } catch {
            return false
        }
    }
    
    /// 搜索好友
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - keyword: 关键词（搜索备注）
    /// - Returns: 好友用户对象数组
    public func searchFriends(userID: String, keyword: String) -> [IMUser] {
        guard !keyword.isEmpty else { return [] }
        
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            SELECT friend_id FROM friends
            WHERE user_id = ? AND remark LIKE ?
            ORDER BY update_time DESC;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let searchPattern = "%\(keyword)%"
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
        
        var friendIDs: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let friendID = String(cString: sqlite3_column_text(statement, 0))
            friendIDs.append(friendID)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Search \(friendIDs.count) friends", elapsed: elapsed)
        
        // 批量获取用户信息
        return getUsers(userIDs: friendIDs)
    }
    
    // MARK: - Update
    
    /// 更新好友备注
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - friendID: 好友 ID
    ///   - remark: 备注
    public func updateFriendRemark(userID: String, friendID: String, remark: String) throws {
        let sql = """
            UPDATE friends SET
                remark = ?,
                update_time = ?
            WHERE user_id = ? AND friend_id = ?;
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
        
        sqlite3_bind_text(statement, 1, (remark as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (friendID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update friend remark: \(getErrorMessage())")
        }
    }
    
    // MARK: - Delete
    
    /// 删除好友
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - friendID: 好友 ID
    public func deleteFriend(userID: String, friendID: String) throws {
        let startTime = Date()
        
        let sql = "DELETE FROM friends WHERE user_id = ? AND friend_id = ?;"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare delete: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (friendID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to delete friend: \(getErrorMessage())")
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete friend", elapsed: elapsed)
    }
    
    /// 删除用户的所有好友关系
    /// - Parameter userID: 用户 ID
    public func deleteAllFriends(userID: String) throws {
        let startTime = Date()
        
        try execute(sql: "DELETE FROM friends WHERE user_id = '\(userID)';")
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete all friends for user", elapsed: elapsed)
    }
    
    // MARK: - Helper Methods
    
    /// 检查好友关系是否存在
    private func friendExists(userID: String, friendID: String) throws -> Bool {
        let sql = "SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (friendID as NSString).utf8String, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
}


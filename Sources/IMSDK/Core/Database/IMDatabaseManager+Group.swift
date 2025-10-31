/// IMDatabaseManager+Group - 群组相关数据库操作
/// 实现群组的 CRUD 操作

import Foundation
import SQLite3

// MARK: - Group Operations

extension IMDatabaseManager {
    
    // MARK: - Table Creation
    
    /// 创建群组相关表
    internal func createGroupTables() throws {
        // 群组表
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS groups (
                group_id TEXT PRIMARY KEY,
                group_name TEXT NOT NULL,
                face_url TEXT,
                owner_user_id TEXT NOT NULL,
                member_count INTEGER DEFAULT 0,
                introduction TEXT,
                notification TEXT,
                extra TEXT,
                status INTEGER DEFAULT 0,
                create_time INTEGER NOT NULL,
                update_time INTEGER NOT NULL
            );
            """)
        
        // 群成员表
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS group_members (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                nickname TEXT,
                role INTEGER DEFAULT 0,
                join_time INTEGER NOT NULL,
                UNIQUE(group_id, user_id)
            );
            """)
        
        // 创建索引
        try execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_group_members_group 
                ON group_members(group_id);
            CREATE INDEX IF NOT EXISTS idx_group_members_user 
                ON group_members(user_id);
            """)
    }
    
    // MARK: - Save Group
    
    /// 保存群组
    /// - Parameter group: 群组对象
    @discardableResult
    public func saveGroup(_ group: IMGroup) throws -> Bool {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let exists = try groupExists(groupID: group.groupID)
        
        if exists {
            try updateGroup(group)
        } else {
            try insertGroup(group)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save group", elapsed: elapsed)
        
        return true
    }
    
    /// 批量保存群组
    /// - Parameter groups: 群组数组
    @discardableResult
    public func saveGroups(_ groups: [IMGroup]) throws -> Int {
        guard !groups.isEmpty else { return 0 }
        
        let startTime = Date()
        var count = 0
        
        try transaction {
            for group in groups {
                try saveGroup(group)
                count += 1
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save \(count) groups", elapsed: elapsed)
        
        return count
    }
    
    // MARK: - Insert/Update
    
    /// 插入群组
    private func insertGroup(_ group: IMGroup) throws {
        let sql = """
            INSERT INTO groups (
                group_id, group_name, face_url, owner_user_id,
                member_count, introduction, notification, extra, status,
                create_time, update_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare insert: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (group.groupID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (group.groupName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (group.faceURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (group.ownerUserID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(group.memberCount))
        sqlite3_bind_text(statement, 6, (group.introduction as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (group.notification as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 8, (group.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 9, Int32(group.status))
        sqlite3_bind_int64(statement, 10, currentTime)
        sqlite3_bind_int64(statement, 11, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to insert group: \(getErrorMessage())")
        }
    }
    
    /// 更新群组
    private func updateGroup(_ group: IMGroup) throws {
        let sql = """
            UPDATE groups SET
                group_name = ?, face_url = ?, owner_user_id = ?,
                member_count = ?, introduction = ?, notification = ?,
                extra = ?, status = ?, update_time = ?
            WHERE group_id = ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (group.groupName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (group.faceURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (group.ownerUserID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 4, Int32(group.memberCount))
        sqlite3_bind_text(statement, 5, (group.introduction as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (group.notification as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (group.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 8, Int32(group.status))
        sqlite3_bind_int64(statement, 9, currentTime)
        sqlite3_bind_text(statement, 10, (group.groupID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update group: \(getErrorMessage())")
        }
    }
    
    // MARK: - Query
    
    /// 获取群组
    /// - Parameter groupID: 群组 ID
    /// - Returns: 群组对象
    public func getGroup(groupID: String) -> IMGroup? {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM groups WHERE group_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let group = parseGroup(from: statement)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get group", elapsed: elapsed)
        
        return group
    }
    
    /// 获取我的群组列表
    /// - Parameter userID: 用户 ID
    /// - Returns: 群组数组
    public func getMyGroups(userID: String) -> [IMGroup] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            SELECT g.* FROM groups g
            INNER JOIN group_members gm ON g.group_id = gm.group_id
            WHERE gm.user_id = ?
            ORDER BY g.update_time DESC;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        var groups: [IMGroup] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let group = parseGroup(from: statement)
            groups.append(group)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(groups.count) groups", elapsed: elapsed)
        
        return groups
    }
    
    // MARK: - Group Members
    
    /// 添加群成员
    /// - Parameters:
    ///   - groupID: 群组 ID
    ///   - userID: 用户 ID
    ///   - role: 角色（0=普通成员，1=管理员，2=群主）
    public func addGroupMember(groupID: String, userID: String, role: Int = 0) throws {
        let sql = """
            INSERT OR REPLACE INTO group_members (
                group_id, user_id, role, join_time
            ) VALUES (?, ?, ?, ?);
            """
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare insert: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (userID as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 3, Int32(role))
        sqlite3_bind_int64(statement, 4, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to add group member: \(getErrorMessage())")
        }
        
        // 更新群组成员数
        try updateGroupMemberCount(groupID: groupID)
    }
    
    /// 批量添加群成员
    /// - Parameters:
    ///   - groupID: 群组 ID
    ///   - userIDs: 用户 ID 数组
    public func addGroupMembers(groupID: String, userIDs: [String]) throws {
        try transaction {
            for userID in userIDs {
                try addGroupMember(groupID: groupID, userID: userID)
            }
        }
    }
    
    /// 移除群成员
    /// - Parameters:
    ///   - groupID: 群组 ID
    ///   - userID: 用户 ID
    public func removeGroupMember(groupID: String, userID: String) throws {
        let sql = "DELETE FROM group_members WHERE group_id = ? AND user_id = ?;"
        
        lock.lock()
        defer { lock.unlock() }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare delete: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to remove group member: \(getErrorMessage())")
        }
        
        // 更新群组成员数
        try updateGroupMemberCount(groupID: groupID)
    }
    
    /// 获取群成员列表
    /// - Parameter groupID: 群组 ID
    /// - Returns: 用户 ID 数组
    public func getGroupMembers(groupID: String) -> [String] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT user_id FROM group_members WHERE group_id = ?;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        
        var userIDs: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let userID = String(cString: sqlite3_column_text(statement, 0))
            userIDs.append(userID)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(userIDs.count) group members", elapsed: elapsed)
        
        return userIDs
    }
    
    /// 更新群组成员数
    private func updateGroupMemberCount(groupID: String) throws {
        let countSQL = "SELECT COUNT(*) FROM group_members WHERE group_id = ?;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare count: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        
        var count: Int32 = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = sqlite3_column_int(statement, 0)
        }
        
        // 更新群组表
        let updateSQL = "UPDATE groups SET member_count = ?, update_time = ? WHERE group_id = ?;"
        
        var updateStatement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(updateStatement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_int(updateStatement, 1, count)
        sqlite3_bind_int64(updateStatement, 2, currentTime)
        sqlite3_bind_text(updateStatement, 3, (groupID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update member count: \(getErrorMessage())")
        }
    }
    
    // MARK: - Delete
    
    /// 删除群组（包括群成员）
    /// - Parameter groupID: 群组 ID
    public func deleteGroup(groupID: String) throws {
        let startTime = Date()
        
        try transaction {
            // 删除群成员
            try execute(sql: "DELETE FROM group_members WHERE group_id = '\(groupID)';")
            
            // 删除群组
            try execute(sql: "DELETE FROM groups WHERE group_id = '\(groupID)';")
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete group", elapsed: elapsed)
    }
    
    // MARK: - Helper Methods
    
    /// 检查群组是否存在
    private func groupExists(groupID: String) throws -> Bool {
        let sql = "SELECT 1 FROM groups WHERE group_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (groupID as NSString).utf8String, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    /// 解析群组
    private func parseGroup(from statement: OpaquePointer?) -> IMGroup {
        let group = IMGroup()
        
        group.groupID = String(cString: sqlite3_column_text(statement, 0))
        group.groupName = String(cString: sqlite3_column_text(statement, 1))
        
        if let faceURL = sqlite3_column_text(statement, 2) {
            group.faceURL = String(cString: faceURL)
        }
        
        group.ownerUserID = String(cString: sqlite3_column_text(statement, 3))
        group.memberCount = Int(sqlite3_column_int(statement, 4))
        
        if let introduction = sqlite3_column_text(statement, 5) {
            group.introduction = String(cString: introduction)
        }
        
        if let notification = sqlite3_column_text(statement, 6) {
            group.notification = String(cString: notification)
        }
        
        if let extra = sqlite3_column_text(statement, 7) {
            group.extra = String(cString: extra)
        }
        
        group.status = Int(sqlite3_column_int(statement, 8))
        group.createTime = sqlite3_column_int64(statement, 9)
        group.updateTime = sqlite3_column_int64(statement, 10)
        
        return group
    }
}


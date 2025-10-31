/// IMDatabaseManager+User - 用户相关数据库操作
/// 实现用户的 CRUD 操作

import Foundation
import SQLite3

// MARK: - User Operations

extension IMDatabaseManager {
    
    // MARK: - Save User
    
    /// 保存用户
    /// - Parameter user: 用户对象
    @discardableResult
    public func saveUser(_ user: IMUser) throws -> Bool {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let exists = try userExists(userID: user.userID)
        
        if exists {
            try updateUser(user)
        } else {
            try insertUser(user)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save user", elapsed: elapsed)
        
        return true
    }
    
    /// 批量保存用户
    /// - Parameter users: 用户数组
    public func saveUsers(_ users: [IMUser]) throws {
        guard !users.isEmpty else { return }
        
        let startTime = Date()
        var count = 0
        
        try transaction {
            for user in users {
                try saveUser(user)
                count += 1
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Save \(count) users", elapsed: elapsed)
    }
    
    // MARK: - Insert/Update
    
    /// 插入用户
    private func insertUser(_ user: IMUser) throws {
        let sql = """
            INSERT INTO users (
                user_id, nickname, avatar,
                phone, email, gender, birth,
                signature, extra,
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
        
        sqlite3_bind_text(statement, 1, (user.userID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (user.nickname as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (user.avatar as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (user.phone as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (user.email as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 6, Int32(user.gender))
        sqlite3_bind_int64(statement, 7, user.birth)
        sqlite3_bind_text(statement, 8, (user.signature as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 9, (user.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 10, currentTime)
        sqlite3_bind_int64(statement, 11, currentTime)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to insert user: \(getErrorMessage())")
        }
    }
    
    /// 更新用户
    private func updateUser(_ user: IMUser) throws {
        let sql = """
            UPDATE users SET
                nickname = ?, avatar = ?,
                phone = ?, email = ?, gender = ?, birth = ?,
                signature = ?, extra = ?, update_time = ?
            WHERE user_id = ?;
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare update: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        sqlite3_bind_text(statement, 1, (user.nickname as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (user.avatar as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (user.phone as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (user.email as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(user.gender))
        sqlite3_bind_int64(statement, 6, user.birth)
        sqlite3_bind_text(statement, 7, (user.signature as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 8, (user.extra as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 9, currentTime)
        sqlite3_bind_text(statement, 10, (user.userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update user: \(getErrorMessage())")
        }
    }
    
    // MARK: - Query
    
    /// 获取用户
    /// - Parameter userID: 用户 ID
    /// - Returns: 用户对象
    public func getUser(userID: String) -> IMUser? {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM users WHERE user_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        let user = parseUser(from: statement)
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get user", elapsed: elapsed)
        
        return user
    }
    
    /// 批量获取用户
    /// - Parameter userIDs: 用户 ID 数组
    /// - Returns: 用户字典（userID -> IMUser）
    public func getUsers(userIDs: [String]) -> [String: IMUser] {
        guard !userIDs.isEmpty else { return [:] }
        
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        // 构建 IN 子句
        let placeholders = userIDs.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT * FROM users WHERE user_id IN (\(placeholders));"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return [:]
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // 绑定参数
        for (index, userID) in userIDs.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), (userID as NSString).utf8String, -1, nil)
        }
        
        var users: [String: IMUser] = [:]
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let user = parseUser(from: statement)
            users[user.userID] = user
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(users.count) users", elapsed: elapsed)
        
        return users
    }
    
    /// 搜索用户
    /// - Parameters:
    ///   - keyword: 关键词（搜索昵称、手机号、邮箱）
    ///   - limit: 数量限制
    /// - Returns: 用户数组
    public func searchUsers(keyword: String, limit: Int = 20) -> [IMUser] {
        guard !keyword.isEmpty else { return [] }
        
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
            SELECT * FROM users
            WHERE nickname LIKE ? OR phone LIKE ? OR email LIKE ?
            LIMIT ?;
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
        sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 4, Int32(limit))
        
        var users: [IMUser] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let user = parseUser(from: statement)
            users.append(user)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Search \(users.count) users", elapsed: elapsed)
        
        return users
    }
    
    /// 获取所有用户
    /// - Returns: 用户数组
    public func getAllUsers() -> [IMUser] {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT * FROM users ORDER BY update_time DESC;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            IMLogger.shared.error("Failed to prepare query: \(getErrorMessage())")
            return []
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var users: [IMUser] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let user = parseUser(from: statement)
            users.append(user)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Get \(users.count) users", elapsed: elapsed)
        
        return users
    }
    
    // MARK: - Update Specific Fields
    
    /// 更新在线状态
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - isOnline: 是否在线
    public func updateUserOnlineStatus(userID: String, isOnline: Bool) throws {
        let sql = """
            UPDATE users SET
                is_online = ?,
                update_time = ?
            WHERE user_id = ?;
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
        
        sqlite3_bind_int(statement, 1, isOnline ? 1 : 0)
        sqlite3_bind_int64(statement, 2, currentTime)
        sqlite3_bind_text(statement, 3, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to update online status: \(getErrorMessage())")
        }
    }
    
    // MARK: - Delete
    
    /// 删除用户
    /// - Parameter userID: 用户 ID
    public func deleteUser(userID: String) throws {
        let startTime = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "DELETE FROM users WHERE user_id = ?;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare delete: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IMError.databaseError("Failed to delete user: \(getErrorMessage())")
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        IMLogger.shared.database("Delete user", elapsed: elapsed)
    }
    
    // MARK: - Helper Methods
    
    /// 检查用户是否存在
    private func userExists(userID: String) throws -> Bool {
        let sql = "SELECT 1 FROM users WHERE user_id = ? LIMIT 1;"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IMError.databaseError("Failed to prepare query: \(getErrorMessage())")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_text(statement, 1, (userID as NSString).utf8String, -1, nil)
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    /// 解析用户
    private func parseUser(from statement: OpaquePointer?) -> IMUser {
        let user = IMUser()
        
        user.userID = String(cString: sqlite3_column_text(statement, 0))
        
        if let nickname = sqlite3_column_text(statement, 1) {
            user.nickname = String(cString: nickname)
        }
        
        if let avatar = sqlite3_column_text(statement, 2) {
            user.avatar = String(cString: avatar)
        }
        
        if let phone = sqlite3_column_text(statement, 3) {
            user.phone = String(cString: phone)
        }
        
        if let email = sqlite3_column_text(statement, 4) {
            user.email = String(cString: email)
        }
        
        user.gender = Int(sqlite3_column_int(statement, 5))
        user.birth = sqlite3_column_int64(statement, 6)
        
        if let signature = sqlite3_column_text(statement, 7) {
            user.signature = String(cString: signature)
        }
        
        if let extra = sqlite3_column_text(statement, 8) {
            user.extra = String(cString: extra)
        }
        
        user.createTime = sqlite3_column_int64(statement, 9)
        user.updateTime = sqlite3_column_int64(statement, 10)
        
        return user
    }
}


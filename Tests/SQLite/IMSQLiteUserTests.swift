/// IMSQLiteUserTests - 用户 CRUD 操作测试
///
/// 测试内容：
/// - 保存和查询用户
/// - 批量操作
/// - 用户搜索
/// - 在线状态更新
/// - 删除用户
/// - 性能测试

import XCTest
@testable import IMSDK

class IMSQLiteUserTests: IMSQLiteTestBase {
    
    // MARK: - 基本 CRUD 测试
    
    func testSaveAndGetUser() throws {
        // 创建测试用户
        let user = createTestUser(userID: "user_1", nickname: "张三")
        
        // 保存用户
        try database.saveUser(user)
        
        // 查询用户
        let readUser = database.getUser(userID: "user_1")
        
        // 验证
        XCTAssertNotNil(readUser)
        assertUsersEqual(user, readUser)
        
        IMLogger.shared.info("✅ 保存和查询用户测试通过")
    }
    
    func testUpdateUser() throws {
        // 保存初始用户
        let user = createTestUser(userID: "user_update", nickname: "Original")
        try database.saveUser(user)
        
        // 更新用户
        user.nickname = "Updated"
        user.avatar = "https://new-avatar.com"
        try database.saveUser(user)
        
        // 查询
        let readUser = database.getUser(userID: "user_update")
        
        // 验证
        XCTAssertEqual(readUser?.nickname, "Updated")
        XCTAssertEqual(readUser?.avatar, "https://new-avatar.com")
        
        IMLogger.shared.info("✅ 更新用户测试通过")
    }
    
    func testDeleteUser() throws {
        // 保存用户
        let user = createTestUser(userID: "user_delete")
        try database.saveUser(user)
        
        // 验证用户存在
        var readUser = database.getUser(userID: "user_delete")
        XCTAssertNotNil(readUser)
        
        // 删除用户
        try database.deleteUser(userID: "user_delete")
        
        // 验证用户已删除
        readUser = database.getUser(userID: "user_delete")
        XCTAssertNil(readUser)
        
        IMLogger.shared.info("✅ 删除用户测试通过")
    }
    
    // MARK: - 批量操作测试
    
    func testSaveBatchUsers() throws {
        // 创建多个用户
        var users: [IMUser] = []
        for i in 0..<10 {
            let user = createTestUser(userID: "user_batch_\(i)")
            users.append(user)
        }
        
        // 批量保存
        try database.saveUsers(users)
        
        // 验证所有用户都已保存
        for i in 0..<10 {
            let readUser = database.getUser(userID: "user_batch_\(i)")
            XCTAssertNotNil(readUser)
        }
        
        IMLogger.shared.info("✅ 批量保存用户测试通过")
    }
    
    func testGetBatchUsers() throws {
        // 保存多个用户
        for i in 0..<5 {
            let user = createTestUser(userID: "user_get_batch_\(i)")
            try database.saveUser(user)
        }
        
        // 批量查询
        let userIDs = ["user_get_batch_0", "user_get_batch_1", "user_get_batch_2"]
        let users = database.getUsers(userIDs: userIDs)
        
        // 验证
        XCTAssertEqual(users.count, 3)
        
        let retrievedIDs = users.map { $0.userID }
        XCTAssertTrue(retrievedIDs.contains("user_get_batch_0"))
        XCTAssertTrue(retrievedIDs.contains("user_get_batch_1"))
        XCTAssertTrue(retrievedIDs.contains("user_get_batch_2"))
        
        IMLogger.shared.info("✅ 批量查询用户测试通过")
    }
    
    // MARK: - 用户搜索测试
    
    func testSearchUsersByNickname() throws {
        // 保存多个用户
        let user1 = createTestUser(userID: "user_search_1", nickname: "张三")
        let user2 = createTestUser(userID: "user_search_2", nickname: "李四")
        let user3 = createTestUser(userID: "user_search_3", nickname: "张五")
        
        try database.saveUsers([user1, user2, user3])
        
        // 搜索包含"张"的用户
        let results = database.searchUsers(keyword: "张", limit: 10)
        
        // 验证：应该找到 2 个用户
        XCTAssertEqual(results.count, 2)
        
        let nicknames = results.map { $0.nickname }
        XCTAssertTrue(nicknames.contains("张三"))
        XCTAssertTrue(nicknames.contains("张五"))
        
        IMLogger.shared.info("✅ 按昵称搜索用户测试通过")
    }
    
    func testSearchUsersByPhone() throws {
        // 保存用户
        let user1 = createTestUser(userID: "user_phone_1")
        user1.phone = "13800138000"
        
        let user2 = createTestUser(userID: "user_phone_2")
        user2.phone = "13900139000"
        
        try database.saveUsers([user1, user2])
        
        // 搜索手机号包含"138"的用户
        let results = database.searchUsers(keyword: "138", limit: 10)
        
        // 验证
        XCTAssertGreaterThanOrEqual(results.count, 1)
        
        let phones = results.map { $0.phone }
        XCTAssertTrue(phones.contains("13800138000"))
        
        IMLogger.shared.info("✅ 按手机号搜索用户测试通过")
    }
    
    func testSearchUsersWithLimit() throws {
        // 保存 20 个用户
        for i in 0..<20 {
            let user = createTestUser(userID: "user_limit_\(i)", nickname: "User\(i)")
            try database.saveUser(user)
        }
        
        // 搜索，限制 5 条
        let results = database.searchUsers(keyword: "User", limit: 5)
        
        // 验证
        XCTAssertEqual(results.count, 5)
        
        IMLogger.shared.info("✅ 搜索限制数量测试通过")
    }
    
    // MARK: - 在线状态测试
    
    func testUpdateOnlineStatus() throws {
        // 保存用户
        let user = createTestUser(userID: "user_online", isOnline: false)
        try database.saveUser(user)
        
        // 更新为在线
        try database.updateUserOnlineStatus(userID: "user_online", isOnline: true)
        
        // 验证
        var readUser = database.getUser(userID: "user_online")
        XCTAssertEqual(readUser?.isOnline, true)
        
        // 更新为离线
        try database.updateUserOnlineStatus(userID: "user_online", isOnline: false)
        
        // 验证
        readUser = database.getUser(userID: "user_online")
        XCTAssertEqual(readUser?.isOnline, false)
        
        IMLogger.shared.info("✅ 更新在线状态测试通过")
    }
    
    // MARK: - 获取所有用户测试
    
    func testGetAllUsers() throws {
        // 保存多个用户
        for i in 0..<10 {
            let user = createTestUser(userID: "user_all_\(i)")
            try database.saveUser(user)
        }
        
        // 获取所有用户
        let allUsers = database.getAllUsers()
        
        // 验证
        XCTAssertGreaterThanOrEqual(allUsers.count, 10)
        
        IMLogger.shared.info("✅ 获取所有用户测试通过")
    }
    
    // MARK: - 用户信息完整性测试
    
    func testUserWithAllFields() throws {
        // 创建包含所有字段的用户
        let user = IMUser()
        user.userID = "user_full"
        user.nickname = "完整用户"
        user.avatar = "https://example.com/avatar.jpg"
        user.phone = "13800138000"
        user.email = "user@example.com"
        user.gender = 1
        user.birthday = "1990-01-01"
        user.signature = "Hello World"
        user.isOnline = true
        user.extra = "{\"key\":\"value\"}"
        
        // 保存
        try database.saveUser(user)
        
        // 查询
        let readUser = database.getUser(userID: "user_full")
        
        // 验证所有字段
        XCTAssertNotNil(readUser)
        XCTAssertEqual(readUser?.nickname, "完整用户")
        XCTAssertEqual(readUser?.phone, "13800138000")
        XCTAssertEqual(readUser?.email, "user@example.com")
        XCTAssertEqual(readUser?.gender, 1)
        XCTAssertEqual(readUser?.birthday, "1990-01-01")
        XCTAssertEqual(readUser?.signature, "Hello World")
        XCTAssertEqual(readUser?.isOnline, true)
        XCTAssertEqual(readUser?.extra, "{\"key\":\"value\"}")
        
        IMLogger.shared.info("✅ 完整用户信息测试通过")
    }
    
    // MARK: - 性能测试
    
    func testBatchSavePerformance() throws {
        // 创建 100 个用户
        var users: [IMUser] = []
        for i in 0..<100 {
            let user = createTestUser(userID: "user_perf_\(i)")
            users.append(user)
        }
        
        // 测试批量保存性能
        try assertPerformance(maxDuration: 0.15, {
            try self.database.saveUsers(users)
        }, description: "批量保存 100 个用户")
        
        IMLogger.shared.info("✅ 批量保存性能测试通过")
    }
    
    func testSearchPerformance() throws {
        // 保存 500 个用户
        for i in 0..<500 {
            let user = createTestUser(userID: "user_search_perf_\(i)", nickname: "用户\(i)")
            try database.saveUser(user)
        }
        
        // 测试搜索性能
        try assertPerformance(maxDuration: 0.05, {
            let _ = self.database.searchUsers(keyword: "用户", limit: 20)
        }, description: "搜索用户")
        
        IMLogger.shared.info("✅ 搜索性能测试通过")
    }
    
    func testBatchQueryPerformance() throws {
        // 保存 100 个用户
        for i in 0..<100 {
            let user = createTestUser(userID: "user_batch_query_\(i)")
            try database.saveUser(user)
        }
        
        // 创建 50 个 userID 列表
        var userIDs: [String] = []
        for i in 0..<50 {
            userIDs.append("user_batch_query_\(i)")
        }
        
        // 测试批量查询性能
        try assertPerformance(maxDuration: 0.02, {
            let _ = self.database.getUsers(userIDs: userIDs)
        }, description: "批量查询 50 个用户")
        
        IMLogger.shared.info("✅ 批量查询性能测试通过")
    }
}


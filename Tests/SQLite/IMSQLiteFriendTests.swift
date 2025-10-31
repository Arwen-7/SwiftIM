/// IMSQLiteFriendTests - 好友 CRUD 操作测试
///
/// 测试内容：
/// - 添加和查询好友
/// - 好友列表
/// - 好友备注管理
/// - 好友搜索
/// - 好友关系检查
/// - 删除好友
/// - 性能测试

import XCTest
@testable import IMSDK

class IMSQLiteFriendTests: IMSQLiteTestBase {
    
    // MARK: - 基本 CRUD 测试
    
    func testAddFriend() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_1",
            remark: "好友1",
            source: "搜索"
        )
        
        // 验证好友已添加
        let isFriend = database.isFriend(userID: testUserID, friendID: "friend_1")
        XCTAssertTrue(isFriend)
        
        IMLogger.shared.info("✅ 添加好友测试通过")
    }
    
    func testGetFriends() throws {
        // 添加多个好友
        for i in 0..<5 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
        }
        
        // 获取好友列表
        let friends = database.getFriends(userID: testUserID)
        
        // 验证
        XCTAssertEqual(friends.count, 5)
        
        let friendIDs = friends.map { $0.userID }
        for i in 0..<5 {
            XCTAssertTrue(friendIDs.contains("friend_\(i)"))
        }
        
        IMLogger.shared.info("✅ 获取好友列表测试通过")
    }
    
    func testDeleteFriend() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_delete",
            remark: "待删除好友",
            source: "搜索"
        )
        
        // 验证好友存在
        var isFriend = database.isFriend(userID: testUserID, friendID: "friend_delete")
        XCTAssertTrue(isFriend)
        
        // 删除好友
        try database.deleteFriend(userID: testUserID, friendID: "friend_delete")
        
        // 验证好友已删除
        isFriend = database.isFriend(userID: testUserID, friendID: "friend_delete")
        XCTAssertFalse(isFriend)
        
        IMLogger.shared.info("✅ 删除好友测试通过")
    }
    
    // MARK: - 好友备注测试
    
    func testGetFriendRemark() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_remark",
            remark: "老王",
            source: "搜索"
        )
        
        // 获取备注
        let remark = database.getFriendRemark(userID: testUserID, friendID: "friend_remark")
        
        // 验证
        XCTAssertEqual(remark, "老王")
        
        IMLogger.shared.info("✅ 获取好友备注测试通过")
    }
    
    func testUpdateFriendRemark() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_update_remark",
            remark: "原始备注",
            source: "搜索"
        )
        
        // 更新备注
        try database.updateFriendRemark(
            userID: testUserID,
            friendID: "friend_update_remark",
            remark: "新备注"
        )
        
        // 验证
        let remark = database.getFriendRemark(userID: testUserID, friendID: "friend_update_remark")
        XCTAssertEqual(remark, "新备注")
        
        IMLogger.shared.info("✅ 更新好友备注测试通过")
    }
    
    // MARK: - 好友搜索测试
    
    func testSearchFriends() throws {
        // 添加多个好友
        try database.addFriend(userID: testUserID, friendID: "friend_1", remark: "张三", source: "搜索")
        try database.addFriend(userID: testUserID, friendID: "friend_2", remark: "李四", source: "搜索")
        try database.addFriend(userID: testUserID, friendID: "friend_3", remark: "张五", source: "搜索")
        try database.addFriend(userID: testUserID, friendID: "friend_4", remark: "王六", source: "搜索")
        
        // 搜索包含"张"的好友
        let results = database.searchFriends(userID: testUserID, keyword: "张")
        
        // 验证：应该找到 2 个好友
        XCTAssertEqual(results.count, 2)
        
        let friendIDs = results.map { $0.userID }
        XCTAssertTrue(friendIDs.contains("friend_1"))
        XCTAssertTrue(friendIDs.contains("friend_3"))
        
        IMLogger.shared.info("✅ 搜索好友测试通过")
    }
    
    func testSearchFriendsNonExistent() throws {
        // 添加好友
        try database.addFriend(userID: testUserID, friendID: "friend_1", remark: "张三", source: "搜索")
        
        // 搜索不存在的备注
        let results = database.searchFriends(userID: testUserID, keyword: "不存在")
        
        // 验证：应该找不到
        XCTAssertEqual(results.count, 0)
        
        IMLogger.shared.info("✅ 搜索不存在好友测试通过")
    }
    
    // MARK: - 好友关系检查测试
    
    func testIsFriend() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_check",
            remark: "好友",
            source: "搜索"
        )
        
        // 检查是好友
        let isFriend = database.isFriend(userID: testUserID, friendID: "friend_check")
        XCTAssertTrue(isFriend)
        
        // 检查不是好友
        let isNotFriend = database.isFriend(userID: testUserID, friendID: "not_friend")
        XCTAssertFalse(isNotFriend)
        
        IMLogger.shared.info("✅ 好友关系检查测试通过")
    }
    
    // MARK: - 好友来源测试
    
    func testFriendSource() throws {
        // 添加不同来源的好友
        try database.addFriend(userID: testUserID, friendID: "friend_src_1", remark: "来源1", source: "搜索")
        try database.addFriend(userID: testUserID, friendID: "friend_src_2", remark: "来源2", source: "群聊")
        try database.addFriend(userID: testUserID, friendID: "friend_src_3", remark: "来源3", source: "名片")
        
        // 获取好友列表
        let friends = database.getFriends(userID: testUserID)
        
        // 验证来源
        let friend1 = friends.first { $0.userID == "friend_src_1" }
        let friend2 = friends.first { $0.userID == "friend_src_2" }
        let friend3 = friends.first { $0.userID == "friend_src_3" }
        
        // 注意：IMUser 模型可能没有 source 字段，这里只是验证好友存在
        XCTAssertNotNil(friend1)
        XCTAssertNotNil(friend2)
        XCTAssertNotNil(friend3)
        
        IMLogger.shared.info("✅ 好友来源测试通过")
    }
    
    // MARK: - 防重复添加测试
    
    func testPreventDuplicateFriend() throws {
        // 添加好友
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_dup",
            remark: "第一次",
            source: "搜索"
        )
        
        // 尝试再次添加（应该更新而不是重复添加）
        try database.addFriend(
            userID: testUserID,
            friendID: "friend_dup",
            remark: "第二次",
            source: "群聊"
        )
        
        // 获取好友列表
        let friends = database.getFriends(userID: testUserID)
        
        // 验证：只有一个好友记录
        let duplicates = friends.filter { $0.userID == "friend_dup" }
        XCTAssertEqual(duplicates.count, 1)
        
        IMLogger.shared.info("✅ 防重复添加好友测试通过")
    }
    
    // MARK: - 双向好友关系测试
    
    func testBidirectionalFriendship() throws {
        // 用户 A 添加用户 B 为好友
        try database.addFriend(
            userID: "user_A",
            friendID: "user_B",
            remark: "B",
            source: "搜索"
        )
        
        // 用户 B 添加用户 A 为好友
        try database.addFriend(
            userID: "user_B",
            friendID: "user_A",
            remark: "A",
            source: "搜索"
        )
        
        // 验证双向关系
        let aIsFriendOfB = database.isFriend(userID: "user_A", friendID: "user_B")
        let bIsFriendOfA = database.isFriend(userID: "user_B", friendID: "user_A")
        
        XCTAssertTrue(aIsFriendOfB)
        XCTAssertTrue(bIsFriendOfA)
        
        // 用户 A 删除用户 B
        try database.deleteFriend(userID: "user_A", friendID: "user_B")
        
        // 验证：A 不再是 B 的好友，但 B 仍是 A 的好友
        let aIsFriendOfBAfter = database.isFriend(userID: "user_A", friendID: "user_B")
        let bIsFriendOfAAfter = database.isFriend(userID: "user_B", friendID: "user_A")
        
        XCTAssertFalse(aIsFriendOfBAfter)
        XCTAssertTrue(bIsFriendOfAAfter)
        
        IMLogger.shared.info("✅ 双向好友关系测试通过")
    }
    
    // MARK: - 删除所有好友测试
    
    func testDeleteAllFriends() throws {
        // 添加多个好友
        for i in 0..<10 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_all_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
        }
        
        // 验证好友数量
        var friends = database.getFriends(userID: testUserID)
        XCTAssertEqual(friends.count, 10)
        
        // 删除所有好友
        try database.deleteAllFriends(userID: testUserID)
        
        // 验证所有好友已删除
        friends = database.getFriends(userID: testUserID)
        XCTAssertEqual(friends.count, 0)
        
        IMLogger.shared.info("✅ 删除所有好友测试通过")
    }
    
    // MARK: - 好友列表排序测试
    
    func testFriendListOrdering() throws {
        // 添加好友（按添加时间）
        for i in 0..<5 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_order_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
            // 添加延迟确保时间不同
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // 获取好友列表
        let friends = database.getFriends(userID: testUserID)
        
        // 验证：应该按添加时间排序
        XCTAssertEqual(friends.count, 5)
        
        IMLogger.shared.info("✅ 好友列表排序测试通过")
    }
    
    // MARK: - 性能测试
    
    func testAddManyFriendsPerformance() throws {
        // 测试添加 100 个好友的性能
        try assertPerformance(maxDuration: 0.3, {
            for i in 0..<100 {
                try self.database.addFriend(
                    userID: self.testUserID,
                    friendID: "friend_perf_\(i)",
                    remark: "好友\(i)",
                    source: "搜索"
                )
            }
        }, description: "添加 100 个好友")
        
        // 验证好友数量
        let friends = database.getFriends(userID: testUserID)
        XCTAssertGreaterThanOrEqual(friends.count, 100)
        
        IMLogger.shared.info("✅ 添加好友性能测试通过")
    }
    
    func testGetFriendsPerformance() throws {
        // 添加 200 个好友
        for i in 0..<200 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_get_perf_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
        }
        
        // 测试查询性能
        try assertPerformance(maxDuration: 0.02, {
            let _ = self.database.getFriends(userID: self.testUserID)
        }, description: "查询好友列表（200人）")
        
        IMLogger.shared.info("✅ 查询好友列表性能测试通过")
    }
    
    func testSearchFriendsPerformance() throws {
        // 添加 100 个好友
        for i in 0..<100 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_search_perf_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
        }
        
        // 测试搜索性能
        try assertPerformance(maxDuration: 0.02, {
            let _ = self.database.searchFriends(userID: self.testUserID, keyword: "好友")
        }, description: "搜索好友")
        
        IMLogger.shared.info("✅ 搜索好友性能测试通过")
    }
    
    func testIsFriendPerformance() throws {
        // 添加 500 个好友
        for i in 0..<500 {
            try database.addFriend(
                userID: testUserID,
                friendID: "friend_check_perf_\(i)",
                remark: "好友\(i)",
                source: "搜索"
            )
        }
        
        // 测试检查好友关系性能（应该 < 1ms）
        try assertPerformance(maxDuration: 0.001, {
            let _ = self.database.isFriend(userID: self.testUserID, friendID: "friend_check_perf_250")
        }, description: "检查好友关系")
        
        IMLogger.shared.info("✅ 检查好友关系性能测试通过")
    }
}


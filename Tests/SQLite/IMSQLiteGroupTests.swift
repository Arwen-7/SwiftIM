/// IMSQLiteGroupTests - 群组 CRUD 操作测试
///
/// 测试内容：
/// - 保存和查询群组
/// - 群成员管理（添加/删除/查询）
/// - 我的群组列表
/// - 级联删除
/// - 成员数自动更新
/// - 性能测试

import XCTest
@testable import IMSDK

class IMSQLiteGroupTests: IMSQLiteTestBase {
    
    // MARK: - 基本 CRUD 测试
    
    func testSaveAndGetGroup() throws {
        // 创建测试群组
        let group = createTestGroup(groupID: "group_1", groupName: "测试群组")
        
        // 保存群组
        try database.saveGroup(group)
        
        // 查询群组
        let readGroup = database.getGroup(groupID: "group_1")
        
        // 验证
        XCTAssertNotNil(readGroup)
        assertGroupsEqual(group, readGroup)
        
        IMLogger.shared.info("✅ 保存和查询群组测试通过")
    }
    
    func testUpdateGroup() throws {
        // 保存初始群组
        let group = createTestGroup(groupID: "group_update", groupName: "Original")
        try database.saveGroup(group)
        
        // 更新群组
        group.groupName = "Updated"
        group.introduction = "New introduction"
        try database.saveGroup(group)
        
        // 查询
        let readGroup = database.getGroup(groupID: "group_update")
        
        // 验证
        XCTAssertEqual(readGroup?.groupName, "Updated")
        XCTAssertEqual(readGroup?.introduction, "New introduction")
        
        IMLogger.shared.info("✅ 更新群组测试通过")
    }
    
    func testDeleteGroup() throws {
        // 创建群组并添加成员
        let group = createTestGroup(groupID: "group_delete")
        try database.saveGroup(group)
        
        // 添加几个成员
        try database.addGroupMember(groupID: "group_delete", userID: "user_1", role: 0)
        try database.addGroupMember(groupID: "group_delete", userID: "user_2", role: 0)
        
        // 验证群组和成员存在
        var readGroup = database.getGroup(groupID: "group_delete")
        XCTAssertNotNil(readGroup)
        
        var members = database.getGroupMembers(groupID: "group_delete")
        XCTAssertEqual(members.count, 2)
        
        // 删除群组（应该级联删除成员）
        try database.deleteGroup(groupID: "group_delete")
        
        // 验证群组已删除
        readGroup = database.getGroup(groupID: "group_delete")
        XCTAssertNil(readGroup)
        
        // 验证成员也已删除
        members = database.getGroupMembers(groupID: "group_delete")
        XCTAssertEqual(members.count, 0)
        
        IMLogger.shared.info("✅ 删除群组（级联删除成员）测试通过")
    }
    
    // MARK: - 群成员管理测试
    
    func testAddGroupMember() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_members", memberCount: 0)
        try database.saveGroup(group)
        
        // 添加成员
        try database.addGroupMember(
            groupID: "group_members",
            userID: "user_1",
            role: 0
        )
        
        // 验证成员已添加
        let members = database.getGroupMembers(groupID: "group_members")
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].userID, "user_1")
        
        // 验证群组成员数已更新
        let readGroup = database.getGroup(groupID: "group_members")
        XCTAssertEqual(readGroup?.memberCount, 1)
        
        IMLogger.shared.info("✅ 添加群成员测试通过")
    }
    
    func testAddMultipleGroupMembers() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_multi_members")
        try database.saveGroup(group)
        
        // 批量添加成员
        let userIDs = ["user_1", "user_2", "user_3", "user_4", "user_5"]
        try database.addGroupMembers(groupID: "group_multi_members", userIDs: userIDs)
        
        // 验证所有成员已添加
        let members = database.getGroupMembers(groupID: "group_multi_members")
        XCTAssertEqual(members.count, 5)
        
        // 验证群组成员数已更新
        let readGroup = database.getGroup(groupID: "group_multi_members")
        XCTAssertEqual(readGroup?.memberCount, 5)
        
        IMLogger.shared.info("✅ 批量添加群成员测试通过")
    }
    
    func testRemoveGroupMember() throws {
        // 创建群组并添加成员
        let group = createTestGroup(groupID: "group_remove")
        try database.saveGroup(group)
        
        try database.addGroupMember(groupID: "group_remove", userID: "user_1", role: 0)
        try database.addGroupMember(groupID: "group_remove", userID: "user_2", role: 0)
        
        // 移除一个成员
        try database.removeGroupMember(groupID: "group_remove", userID: "user_1")
        
        // 验证成员已移除
        let members = database.getGroupMembers(groupID: "group_remove")
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].userID, "user_2")
        
        // 验证群组成员数已更新
        let readGroup = database.getGroup(groupID: "group_remove")
        XCTAssertEqual(readGroup?.memberCount, 1)
        
        IMLogger.shared.info("✅ 移除群成员测试通过")
    }
    
    func testGetGroupMembers() throws {
        // 创建群组并添加成员
        let group = createTestGroup(groupID: "group_get_members")
        try database.saveGroup(group)
        
        // 添加不同角色的成员
        try database.addGroupMember(groupID: "group_get_members", userID: "owner", role: 2)  // 群主
        try database.addGroupMember(groupID: "group_get_members", userID: "admin", role: 1)  // 管理员
        try database.addGroupMember(groupID: "group_get_members", userID: "member", role: 0) // 普通成员
        
        // 获取所有成员
        let members = database.getGroupMembers(groupID: "group_get_members")
        
        // 验证
        XCTAssertEqual(members.count, 3)
        
        let userIDs = members.map { $0.userID }
        XCTAssertTrue(userIDs.contains("owner"))
        XCTAssertTrue(userIDs.contains("admin"))
        XCTAssertTrue(userIDs.contains("member"))
        
        IMLogger.shared.info("✅ 获取群成员测试通过")
    }
    
    // MARK: - 我的群组列表测试
    
    func testGetMyGroups() throws {
        // 创建多个群组
        for i in 0..<5 {
            let group = createTestGroup(groupID: "group_my_\(i)", groupName: "我的群组\(i)")
            try database.saveGroup(group)
            
            // 将 testUserID 添加为成员
            try database.addGroupMember(
                groupID: "group_my_\(i)",
                userID: testUserID,
                role: 0
            )
        }
        
        // 创建一个不属于我的群组
        let otherGroup = createTestGroup(groupID: "group_other", groupName: "其他群组")
        try database.saveGroup(otherGroup)
        try database.addGroupMember(groupID: "group_other", userID: "other_user", role: 0)
        
        // 获取我的群组
        let myGroups = database.getMyGroups(userID: testUserID)
        
        // 验证：应该只包含我参与的 5 个群组
        XCTAssertEqual(myGroups.count, 5)
        
        let groupNames = myGroups.map { $0.groupName }
        for i in 0..<5 {
            XCTAssertTrue(groupNames.contains("我的群组\(i)"))
        }
        XCTAssertFalse(groupNames.contains("其他群组"))
        
        IMLogger.shared.info("✅ 获取我的群组列表测试通过")
    }
    
    // MARK: - 成员角色测试
    
    func testMemberRoles() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_roles")
        try database.saveGroup(group)
        
        // 添加不同角色的成员
        try database.addGroupMember(groupID: "group_roles", userID: "owner", role: 2)
        try database.addGroupMember(groupID: "group_roles", userID: "admin", role: 1)
        try database.addGroupMember(groupID: "group_roles", userID: "member", role: 0)
        
        // 获取成员列表
        let members = database.getGroupMembers(groupID: "group_roles")
        
        // 验证角色
        let ownerMember = members.first { $0.userID == "owner" }
        let adminMember = members.first { $0.userID == "admin" }
        let normalMember = members.first { $0.userID == "member" }
        
        XCTAssertEqual(ownerMember?.role, 2)
        XCTAssertEqual(adminMember?.role, 1)
        XCTAssertEqual(normalMember?.role, 0)
        
        IMLogger.shared.info("✅ 成员角色测试通过")
    }
    
    // MARK: - 成员数自动更新测试
    
    func testMemberCountAutoUpdate() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_count", memberCount: 0)
        try database.saveGroup(group)
        
        // 添加成员
        for i in 0..<10 {
            try database.addGroupMember(
                groupID: "group_count",
                userID: "user_\(i)",
                role: 0
            )
        }
        
        // 验证成员数
        var readGroup = database.getGroup(groupID: "group_count")
        XCTAssertEqual(readGroup?.memberCount, 10)
        
        // 移除 3 个成员
        try database.removeGroupMember(groupID: "group_count", userID: "user_0")
        try database.removeGroupMember(groupID: "group_count", userID: "user_1")
        try database.removeGroupMember(groupID: "group_count", userID: "user_2")
        
        // 验证成员数已更新
        readGroup = database.getGroup(groupID: "group_count")
        XCTAssertEqual(readGroup?.memberCount, 7)
        
        IMLogger.shared.info("✅ 成员数自动更新测试通过")
    }
    
    // MARK: - 防重复添加测试
    
    func testPreventDuplicateMember() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_dup")
        try database.saveGroup(group)
        
        // 添加成员
        try database.addGroupMember(groupID: "group_dup", userID: "user_1", role: 0)
        
        // 尝试再次添加同一个成员（应该不会报错，但也不会重复添加）
        try database.addGroupMember(groupID: "group_dup", userID: "user_1", role: 0)
        
        // 验证：只有一个成员
        let members = database.getGroupMembers(groupID: "group_dup")
        XCTAssertEqual(members.count, 1)
        
        // 验证成员数
        let readGroup = database.getGroup(groupID: "group_dup")
        XCTAssertEqual(readGroup?.memberCount, 1)
        
        IMLogger.shared.info("✅ 防重复添加测试通过")
    }
    
    // MARK: - 群组信息完整性测试
    
    func testGroupWithAllFields() throws {
        // 创建包含所有字段的群组
        let group = IMGroup()
        group.groupID = "group_full"
        group.groupName = "完整群组"
        group.groupAvatar = "https://example.com/group.jpg"
        group.ownerID = "owner_123"
        group.groupType = 1
        group.memberCount = 100
        group.introduction = "这是一个测试群组"
        group.notification = "群公告"
        group.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        group.extra = "{\"key\":\"value\"}"
        
        // 保存
        try database.saveGroup(group)
        
        // 查询
        let readGroup = database.getGroup(groupID: "group_full")
        
        // 验证所有字段
        XCTAssertNotNil(readGroup)
        XCTAssertEqual(readGroup?.groupName, "完整群组")
        XCTAssertEqual(readGroup?.ownerID, "owner_123")
        XCTAssertEqual(readGroup?.groupType, 1)
        XCTAssertEqual(readGroup?.memberCount, 100)
        XCTAssertEqual(readGroup?.introduction, "这是一个测试群组")
        XCTAssertEqual(readGroup?.notification, "群公告")
        XCTAssertEqual(readGroup?.extra, "{\"key\":\"value\"}")
        
        IMLogger.shared.info("✅ 完整群组信息测试通过")
    }
    
    // MARK: - 性能测试
    
    func testBatchAddMembersPerformance() throws {
        // 创建群组
        let group = createTestGroup(groupID: "group_perf")
        try database.saveGroup(group)
        
        // 准备 100 个用户 ID
        var userIDs: [String] = []
        for i in 0..<100 {
            userIDs.append("user_perf_\(i)")
        }
        
        // 测试批量添加性能
        try assertPerformance(maxDuration: 0.2, {
            try self.database.addGroupMembers(groupID: "group_perf", userIDs: userIDs)
        }, description: "批量添加 100 个群成员")
        
        // 验证成员数
        let readGroup = database.getGroup(groupID: "group_perf")
        XCTAssertEqual(readGroup?.memberCount, 100)
        
        IMLogger.shared.info("✅ 批量添加成员性能测试通过")
    }
    
    func testGetMyGroupsPerformance() throws {
        // 创建 50 个群组
        for i in 0..<50 {
            let group = createTestGroup(groupID: "group_my_perf_\(i)")
            try database.saveGroup(group)
            try database.addGroupMember(
                groupID: "group_my_perf_\(i)",
                userID: testUserID,
                role: 0
            )
        }
        
        // 测试查询性能
        try assertPerformance(maxDuration: 0.03, {
            let _ = self.database.getMyGroups(userID: self.testUserID)
        }, description: "查询我的群组列表")
        
        IMLogger.shared.info("✅ 查询我的群组性能测试通过")
    }
    
    func testGetGroupMembersPerformance() throws {
        // 创建群组并添加 500 个成员
        let group = createTestGroup(groupID: "group_members_perf")
        try database.saveGroup(group)
        
        var userIDs: [String] = []
        for i in 0..<500 {
            userIDs.append("user_\(i)")
        }
        try database.addGroupMembers(groupID: "group_members_perf", userIDs: userIDs)
        
        // 测试查询成员性能
        try assertPerformance(maxDuration: 0.05, {
            let _ = self.database.getGroupMembers(groupID: "group_members_perf")
        }, description: "查询群成员列表（500人）")
        
        IMLogger.shared.info("✅ 查询群成员性能测试通过")
    }
}


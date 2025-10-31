/// IMSQLiteConversationTests - 会话 CRUD 操作测试
///
/// 测试内容：
/// - 保存和查询会话
/// - 未读数管理（更新/清空/统计）
/// - 置顶功能
/// - 免打扰功能
/// - 草稿管理
/// - 删除会话
/// - 批量操作
/// - 排序和过滤

import XCTest
@testable import IMSDK

class IMSQLiteConversationTests: IMSQLiteTestBase {
    
    // MARK: - 基本 CRUD 测试
    
    func testSaveAndGetConversation() throws {
        // 创建测试会话
        let conversation = createTestConversation(conversationID: "conv_1")
        
        // 保存会话
        try database.saveConversation(conversation)
        
        // 查询会话
        let readConversation = database.getConversation(conversationID: "conv_1")
        
        // 验证
        XCTAssertNotNil(readConversation)
        assertConversationsEqual(conversation, readConversation)
        
        IMLogger.shared.info("✅ 保存和查询会话测试通过")
    }
    
    func testUpdateConversation() throws {
        // 保存初始会话
        let conversation = createTestConversation(conversationID: "conv_update")
        conversation.lastMessageContent = "Original"
        try database.saveConversation(conversation)
        
        // 更新会话
        conversation.lastMessageContent = "Updated"
        conversation.unreadCount = 5
        try database.saveConversation(conversation)
        
        // 查询
        let readConversation = database.getConversation(conversationID: "conv_update")
        
        // 验证
        XCTAssertEqual(readConversation?.lastMessageContent, "Updated")
        XCTAssertEqual(readConversation?.unreadCount, 5)
        
        IMLogger.shared.info("✅ 更新会话测试通过")
    }
    
    func testDeleteConversation() throws {
        // 保存会话
        let conversation = createTestConversation(conversationID: "conv_delete")
        try database.saveConversation(conversation)
        
        // 验证会话存在
        var readConversation = database.getConversation(conversationID: "conv_delete")
        XCTAssertNotNil(readConversation)
        
        // 删除会话
        try database.deleteConversation(conversationID: "conv_delete")
        
        // 验证会话已删除
        readConversation = database.getConversation(conversationID: "conv_delete")
        XCTAssertNil(readConversation)
        
        IMLogger.shared.info("✅ 删除会话测试通过")
    }
    
    // MARK: - 未读数管理测试
    
    func testUpdateUnreadCount() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_unread")
        conversation.unreadCount = 0
        try database.saveConversation(conversation)
        
        // 更新未读数
        try database.updateConversationUnreadCount(
            conversationID: "conv_unread",
            unreadCount: 10
        )
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_unread")
        XCTAssertEqual(readConversation?.unreadCount, 10)
        
        IMLogger.shared.info("✅ 更新未读数测试通过")
    }
    
    func testIncrementUnreadCount() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_increment")
        conversation.unreadCount = 5
        try database.saveConversation(conversation)
        
        // 增加未读数
        try database.incrementUnreadCount(conversationID: "conv_increment", by: 3)
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_increment")
        XCTAssertEqual(readConversation?.unreadCount, 8)
        
        IMLogger.shared.info("✅ 增加未读数测试通过")
    }
    
    func testClearUnreadCount() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_clear")
        conversation.unreadCount = 10
        try database.saveConversation(conversation)
        
        // 清空未读数
        try database.clearUnreadCount(conversationID: "conv_clear")
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_clear")
        XCTAssertEqual(readConversation?.unreadCount, 0)
        
        IMLogger.shared.info("✅ 清空未读数测试通过")
    }
    
    func testGetTotalUnreadCount() throws {
        // 创建多个会话
        let conv1 = createTestConversation(conversationID: "conv_total_1", unreadCount: 5)
        let conv2 = createTestConversation(conversationID: "conv_total_2", unreadCount: 3)
        let conv3 = createTestConversation(conversationID: "conv_total_3", unreadCount: 7)
        
        try database.saveConversation(conv1)
        try database.saveConversation(conv2)
        try database.saveConversation(conv3)
        
        // 获取总未读数
        let totalUnread = database.getTotalUnreadCount()
        
        // 验证
        XCTAssertEqual(totalUnread, 15)
        
        IMLogger.shared.info("✅ 获取总未读数测试通过")
    }
    
    func testGetTotalUnreadCountWithMuted() throws {
        // 创建会话（一个免打扰）
        let conv1 = createTestConversation(
            conversationID: "conv_muted_1",
            unreadCount: 5,
            isMuted: false
        )
        let conv2 = createTestConversation(
            conversationID: "conv_muted_2",
            unreadCount: 10,
            isMuted: true  // 免打扰
        )
        
        try database.saveConversation(conv1)
        try database.saveConversation(conv2)
        
        // 获取总未读数（应该不包括免打扰会话）
        let totalUnread = database.getTotalUnreadCount()
        
        // 验证：只计算非免打扰的会话
        XCTAssertEqual(totalUnread, 5)
        
        IMLogger.shared.info("✅ 免打扰会话未读数统计测试通过")
    }
    
    // MARK: - 置顶功能测试
    
    func testSetConversationPinned() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_pin")
        conversation.isPinned = false
        try database.saveConversation(conversation)
        
        // 设置置顶
        try database.setConversationPinned(conversationID: "conv_pin", isPinned: true)
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_pin")
        XCTAssertEqual(readConversation?.isPinned, true)
        
        // 取消置顶
        try database.setConversationPinned(conversationID: "conv_pin", isPinned: false)
        
        // 验证
        let updatedConversation = database.getConversation(conversationID: "conv_pin")
        XCTAssertEqual(updatedConversation?.isPinned, false)
        
        IMLogger.shared.info("✅ 置顶功能测试通过")
    }
    
    // MARK: - 免打扰功能测试
    
    func testSetConversationMuted() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_mute")
        conversation.isMuted = false
        try database.saveConversation(conversation)
        
        // 设置免打扰
        try database.setConversationMuted(conversationID: "conv_mute", isMuted: true)
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_mute")
        XCTAssertEqual(readConversation?.isMuted, true)
        
        // 取消免打扰
        try database.setConversationMuted(conversationID: "conv_mute", isMuted: false)
        
        // 验证
        let updatedConversation = database.getConversation(conversationID: "conv_mute")
        XCTAssertEqual(updatedConversation?.isMuted, false)
        
        IMLogger.shared.info("✅ 免打扰功能测试通过")
    }
    
    // MARK: - 草稿管理测试
    
    func testUpdateDraft() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_draft")
        try database.saveConversation(conversation)
        
        // 更新草稿
        try database.updateDraft(conversationID: "conv_draft", draft: "Draft content")
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_draft")
        XCTAssertEqual(readConversation?.draftText, "Draft content")
        
        // 清空草稿
        try database.updateDraft(conversationID: "conv_draft", draft: "")
        
        // 验证
        let updatedConversation = database.getConversation(conversationID: "conv_draft")
        XCTAssertEqual(updatedConversation?.draftText, "")
        
        IMLogger.shared.info("✅ 草稿管理测试通过")
    }
    
    // MARK: - 会话列表查询测试
    
    func testGetAllConversations() throws {
        // 创建多个会话
        for i in 0..<5 {
            let conversation = createTestConversation(
                conversationID: "conv_list_\(i)",
                lastMessageTime: Int64(Date().timeIntervalSince1970 * 1000) + Int64(i * 1000)
            )
            try database.saveConversation(conversation)
        }
        
        // 获取所有会话
        let conversations = database.getAllConversations(sortByTime: true)
        
        // 验证
        XCTAssertEqual(conversations.count, 5)
        
        // 验证排序（按时间倒序）
        for i in 0..<conversations.count - 1 {
            XCTAssertGreaterThanOrEqual(
                conversations[i].lastMessageTime,
                conversations[i + 1].lastMessageTime
            )
        }
        
        IMLogger.shared.info("✅ 获取会话列表测试通过")
    }
    
    func testGetConversationsSortedWithPinned() throws {
        // 创建会话（混合置顶和普通）
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        let conv1 = createTestConversation(
            conversationID: "conv_sort_1",
            lastMessageTime: baseTime + 1000,
            isPinned: false
        )
        let conv2 = createTestConversation(
            conversationID: "conv_sort_2",
            lastMessageTime: baseTime + 2000,
            isPinned: true  // 置顶
        )
        let conv3 = createTestConversation(
            conversationID: "conv_sort_3",
            lastMessageTime: baseTime + 3000,
            isPinned: false
        )
        let conv4 = createTestConversation(
            conversationID: "conv_sort_4",
            lastMessageTime: baseTime + 4000,
            isPinned: true  // 置顶
        )
        
        try database.saveConversation(conv1)
        try database.saveConversation(conv2)
        try database.saveConversation(conv3)
        try database.saveConversation(conv4)
        
        // 获取会话列表（按时间排序）
        let conversations = database.getAllConversations(sortByTime: true)
        
        // 验证：置顶的应该在前面
        XCTAssertTrue(conversations[0].isPinned)
        XCTAssertTrue(conversations[1].isPinned)
        XCTAssertFalse(conversations[2].isPinned)
        XCTAssertFalse(conversations[3].isPinned)
        
        // 验证：置顶的之间按时间倒序，普通的之间也按时间倒序
        XCTAssertEqual(conversations[0].conversationID, "conv_sort_4")  // 置顶，时间最晚
        XCTAssertEqual(conversations[1].conversationID, "conv_sort_2")  // 置顶，时间较早
        XCTAssertEqual(conversations[2].conversationID, "conv_sort_3")  // 普通，时间较晚
        XCTAssertEqual(conversations[3].conversationID, "conv_sort_1")  // 普通，时间最早
        
        IMLogger.shared.info("✅ 会话排序（置顶优先）测试通过")
    }
    
    // MARK: - 批量操作测试
    
    func testBatchUpdateUnreadCount() throws {
        // 创建多个会话
        var conversations: [IMConversation] = []
        for i in 0..<5 {
            let conv = createTestConversation(
                conversationID: "conv_batch_\(i)",
                unreadCount: 0
            )
            conversations.append(conv)
            try database.saveConversation(conv)
        }
        
        // 批量更新未读数
        let updates: [String: Int] = [
            "conv_batch_0": 5,
            "conv_batch_1": 10,
            "conv_batch_2": 3
        ]
        
        try database.batchUpdateUnreadCount(updates: updates)
        
        // 验证
        XCTAssertEqual(database.getConversation(conversationID: "conv_batch_0")?.unreadCount, 5)
        XCTAssertEqual(database.getConversation(conversationID: "conv_batch_1")?.unreadCount, 10)
        XCTAssertEqual(database.getConversation(conversationID: "conv_batch_2")?.unreadCount, 3)
        XCTAssertEqual(database.getConversation(conversationID: "conv_batch_3")?.unreadCount, 0)
        
        IMLogger.shared.info("✅ 批量更新未读数测试通过")
    }
    
    // MARK: - 最后消息更新测试
    
    func testUpdateLastMessage() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_last_msg")
        try database.saveConversation(conversation)
        
        // 更新最后一条消息
        try database.updateConversationLastMessage(
            conversationID: "conv_last_msg",
            lastMessageID: "msg_new",
            lastMessageContent: "New message",
            lastMessageTime: Int64(Date().timeIntervalSince1970 * 1000)
        )
        
        // 验证
        let readConversation = database.getConversation(conversationID: "conv_last_msg")
        XCTAssertEqual(readConversation?.lastMessageID, "msg_new")
        XCTAssertEqual(readConversation?.lastMessageContent, "New message")
        
        IMLogger.shared.info("✅ 更新最后消息测试通过")
    }
    
    // MARK: - 会话类型测试
    
    func testConversationTypes() throws {
        // 创建不同类型的会话
        let singleConv = createTestConversation(
            conversationID: "conv_single",
            conversationType: .single
        )
        let groupConv = createTestConversation(
            conversationID: "conv_group",
            conversationType: .group
        )
        
        try database.saveConversation(singleConv)
        try database.saveConversation(groupConv)
        
        // 验证
        let readSingle = database.getConversation(conversationID: "conv_single")
        let readGroup = database.getConversation(conversationID: "conv_group")
        
        XCTAssertEqual(readSingle?.conversationType, .single)
        XCTAssertEqual(readGroup?.conversationType, .group)
        
        IMLogger.shared.info("✅ 会话类型测试通过")
    }
    
    // MARK: - 未读数计算测试
    
    func testCalculateUnreadCount() throws {
        // 创建会话
        let conversation = createTestConversation(conversationID: "conv_calc")
        conversation.lastReadTime = Int64(Date().timeIntervalSince1970 * 1000)
        try database.saveConversation(conversation)
        
        // 保存一些消息（时间晚于 lastReadTime）
        for i in 0..<5 {
            let message = createTestMessage(
                messageID: "msg_unread_\(i)",
                conversationID: "conv_calc"
            )
            message.createTime = conversation.lastReadTime + Int64(i + 1) * 1000
            message.direction = .incoming  // 接收的消息
            try database.saveMessage(message)
        }
        
        // 计算未读数
        let unreadCount = database.calculateUnreadCount(conversationID: "conv_calc")
        
        // 验证
        XCTAssertEqual(unreadCount, 5)
        
        IMLogger.shared.info("✅ 计算未读数测试通过")
    }
    
    // MARK: - 性能测试
    
    func testConversationQueryPerformance() throws {
        // 创建 100 个会话
        for i in 0..<100 {
            let conversation = createTestConversation(
                conversationID: "conv_perf_\(i)",
                lastMessageTime: Int64(Date().timeIntervalSince1970 * 1000) + Int64(i * 1000)
            )
            try database.saveConversation(conversation)
        }
        
        // 测试查询性能
        try assertPerformance(maxDuration: 0.01, {
            let _ = self.database.getAllConversations(sortByTime: true)
        }, description: "查询所有会话")
        
        IMLogger.shared.info("✅ 会话查询性能测试通过")
    }
    
    func testUnreadCountPerformance() throws {
        // 创建 50 个会话
        for i in 0..<50 {
            let conversation = createTestConversation(
                conversationID: "conv_unread_perf_\(i)",
                unreadCount: i
            )
            try database.saveConversation(conversation)
        }
        
        // 测试总未读数查询性能
        try assertPerformance(maxDuration: 0.005, {
            let _ = self.database.getTotalUnreadCount()
        }, description: "查询总未读数")
        
        IMLogger.shared.info("✅ 未读数查询性能测试通过")
    }
}


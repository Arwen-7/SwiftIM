/// IMSQLiteMessageTests - 消息 CRUD 操作测试
///
/// 测试内容：
/// - 保存单条消息
/// - 批量保存消息
/// - 查询消息（单条/列表）
/// - 历史消息分页
/// - 消息搜索
/// - 删除消息
/// - 消息去重
/// - 性能测试

import XCTest
@testable import IMSDK

class IMSQLiteMessageTests: IMSQLiteTestBase {
    
    // MARK: - 基本 CRUD 测试
    
    func testSaveAndGetMessage() throws {
        // 创建测试消息
        let message = createTestMessage(messageID: "msg_1", content: "Hello World")
        
        // 保存消息
        try database.saveMessage(message)
        
        // 查询消息
        let readMessage = database.getMessage(messageID: "msg_1")
        
        // 验证
        XCTAssertNotNil(readMessage)
        assertMessagesEqual(message, readMessage)
        
        IMLogger.shared.info("✅ 保存和查询单条消息测试通过")
    }
    
    func testSaveMessageWithAllFields() throws {
        // 创建包含所有字段的消息
        let message = createTestMessage(messageID: "msg_full")
        message.messageType = .image
        message.status = .delivered
        message.direction = .incoming
        message.seq = 12345
        message.isRead = true
        message.extra = "{\"key\":\"value\"}"
        
        // 保存
        try database.saveMessage(message)
        
        // 查询
        let readMessage = database.getMessage(messageID: "msg_full")
        
        // 验证所有字段
        XCTAssertNotNil(readMessage)
        XCTAssertEqual(readMessage?.messageType, .image)
        XCTAssertEqual(readMessage?.status, .delivered)
        XCTAssertEqual(readMessage?.direction, .incoming)
        XCTAssertEqual(readMessage?.seq, 12345)
        XCTAssertEqual(readMessage?.isRead, true)
        XCTAssertEqual(readMessage?.extra, "{\"key\":\"value\"}")
        
        IMLogger.shared.info("✅ 保存完整字段消息测试通过")
    }
    
    func testUpdateMessage() throws {
        // 保存初始消息
        let message = createTestMessage(messageID: "msg_update", content: "Original")
        message.status = .sending
        try database.saveMessage(message)
        
        // 更新消息
        message.content = "Updated"
        message.status = .sent
        try database.saveMessage(message)
        
        // 查询
        let readMessage = database.getMessage(messageID: "msg_update")
        
        // 验证更新后的内容
        XCTAssertEqual(readMessage?.content, "Updated")
        XCTAssertEqual(readMessage?.status, .sent)
        
        IMLogger.shared.info("✅ 更新消息测试通过")
    }
    
    func testDeleteMessage() throws {
        // 保存消息
        let message = createTestMessage(messageID: "msg_delete")
        try database.saveMessage(message)
        
        // 验证消息存在
        var readMessage = database.getMessage(messageID: "msg_delete")
        XCTAssertNotNil(readMessage)
        
        // 删除消息
        try database.deleteMessage(messageID: "msg_delete")
        
        // 验证消息已删除
        readMessage = database.getMessage(messageID: "msg_delete")
        XCTAssertNil(readMessage)
        
        IMLogger.shared.info("✅ 删除消息测试通过")
    }
    
    // MARK: - 批量操作测试
    
    func testSaveBatchMessages() throws {
        // 创建 10 条消息
        let messages = createTestMessages(count: 10, conversationID: "conv_batch")
        
        // 批量保存
        try database.saveMessages(messages)
        
        // 验证所有消息都已保存
        for i in 0..<10 {
            let readMessage = database.getMessage(messageID: "msg_\(i)")
            XCTAssertNotNil(readMessage)
        }
        
        IMLogger.shared.info("✅ 批量保存消息测试通过")
    }
    
    func testBatchSavePerformance() throws {
        // 测试批量保存性能
        let messageCount = 100
        let messages = createTestMessages(count: messageCount)
        
        try assertPerformance(maxDuration: 0.2, {
            try self.database.saveMessages(messages)
        }, description: "批量保存 \(messageCount) 条消息")
        
        IMLogger.shared.info("✅ 批量保存性能测试通过")
    }
    
    // MARK: - 查询测试
    
    func testGetMessages() throws {
        // 准备 20 条消息
        let messages = createTestMessages(count: 20, conversationID: "conv_query")
        try database.saveMessages(messages)
        
        // 查询会话消息（默认最新 20 条）
        let readMessages = database.getMessages(conversationID: "conv_query", limit: 20)
        
        // 验证
        XCTAssertEqual(readMessages.count, 20)
        
        // 验证顺序（应该按时间倒序）
        for i in 0..<readMessages.count - 1 {
            XCTAssertGreaterThanOrEqual(
                readMessages[i].createTime,
                readMessages[i + 1].createTime
            )
        }
        
        IMLogger.shared.info("✅ 查询会话消息测试通过")
    }
    
    func testGetMessagesWithLimit() throws {
        // 准备 50 条消息
        let messages = createTestMessages(count: 50, conversationID: "conv_limit")
        try database.saveMessages(messages)
        
        // 只查询 10 条
        let readMessages = database.getMessages(conversationID: "conv_limit", limit: 10)
        
        // 验证
        XCTAssertEqual(readMessages.count, 10)
        
        IMLogger.shared.info("✅ 限制数量查询测试通过")
    }
    
    // MARK: - 历史消息分页测试
    
    func testGetHistoryMessages() throws {
        // 准备 30 条消息，时间递增
        var messages: [IMMessage] = []
        for i in 0..<30 {
            let message = createTestMessage(
                messageID: "msg_history_\(i)",
                conversationID: "conv_history"
            )
            message.createTime = Int64(Date().timeIntervalSince1970 * 1000) + Int64(i * 1000)
            messages.append(message)
        }
        try database.saveMessages(messages)
        
        // 第一页：最新 10 条
        let page1 = database.getMessages(conversationID: "conv_history", limit: 10)
        XCTAssertEqual(page1.count, 10)
        
        // 第二页：使用第一页最早的时间
        let oldestTimeInPage1 = page1.last?.createTime ?? 0
        let page2 = database.getHistoryMessages(
            conversationID: "conv_history",
            startTime: oldestTimeInPage1,
            count: 10
        )
        
        // 验证：第二页应该有 10 条，且时间更早
        XCTAssertEqual(page2.count, 10)
        if let firstInPage2 = page2.first, let lastInPage1 = page1.last {
            XCTAssertLessThan(firstInPage2.createTime, lastInPage1.createTime)
        }
        
        IMLogger.shared.info("✅ 历史消息分页测试通过")
    }
    
    func testGetHistoryMessagesBySeq() throws {
        // 准备消息，seq 从 1 到 30
        var messages: [IMMessage] = []
        for i in 1...30 {
            let message = createTestMessage(
                messageID: "msg_seq_\(i)",
                conversationID: "conv_seq",
                seq: Int64(i)
            )
            messages.append(message)
        }
        try database.saveMessages(messages)
        
        // 查询 seq < 20 的消息，最多 10 条
        let result = database.getHistoryMessagesBySeq(
            conversationID: "conv_seq",
            startSeq: 20,
            count: 10
        )
        
        // 验证
        XCTAssertEqual(result.count, 10)
        
        // 验证 seq 范围（应该是 10-19）
        for message in result {
            XCTAssertLessThan(message.seq, 20)
            XCTAssertGreaterThanOrEqual(message.seq, 10)
        }
        
        IMLogger.shared.info("✅ 基于 seq 的历史消息查询测试通过")
    }
    
    // MARK: - 消息搜索测试
    
    func testSearchMessages() throws {
        // 准备不同内容的消息
        let message1 = createTestMessage(messageID: "msg_search_1", content: "Hello World")
        let message2 = createTestMessage(messageID: "msg_search_2", content: "Swift Programming")
        let message3 = createTestMessage(messageID: "msg_search_3", content: "Hello Swift")
        
        try database.saveMessages([message1, message2, message3])
        
        // 搜索 "Hello"
        let results = database.searchMessages(
            keyword: "Hello",
            conversationID: nil,
            limit: 10
        )
        
        // 应该找到 2 条（msg_search_1 和 msg_search_3）
        XCTAssertEqual(results.count, 2)
        
        let messageIDs = results.map { $0.messageID }
        XCTAssertTrue(messageIDs.contains("msg_search_1"))
        XCTAssertTrue(messageIDs.contains("msg_search_3"))
        
        IMLogger.shared.info("✅ 消息搜索测试通过")
    }
    
    func testSearchMessagesInConversation() throws {
        // 在不同会话中保存消息
        let message1 = createTestMessage(
            messageID: "msg_conv1_1",
            conversationID: "conv_1",
            content: "Test message"
        )
        let message2 = createTestMessage(
            messageID: "msg_conv2_1",
            conversationID: "conv_2",
            content: "Test message"
        )
        
        try database.saveMessages([message1, message2])
        
        // 只在 conv_1 中搜索
        let results = database.searchMessages(
            keyword: "Test",
            conversationID: "conv_1",
            limit: 10
        )
        
        // 应该只找到 1 条
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.conversationID, "conv_1")
        
        IMLogger.shared.info("✅ 会话内搜索测试通过")
    }
    
    func testSearchMessageCount() throws {
        // 准备测试数据
        for i in 0..<5 {
            let message = createTestMessage(
                messageID: "msg_count_\(i)",
                content: "Searchable message \(i)"
            )
            try database.saveMessage(message)
        }
        
        // 获取搜索结果数量
        let count = database.searchMessageCount(keyword: "Searchable")
        
        XCTAssertEqual(count, 5)
        
        IMLogger.shared.info("✅ 搜索结果计数测试通过")
    }
    
    // MARK: - 消息去重测试
    
    func testMessageDeduplication() throws {
        // 保存同一条消息两次
        let message = createTestMessage(messageID: "msg_dup", content: "Original")
        
        try database.saveMessage(message)
        
        // 修改内容后再次保存（相同 messageID）
        message.content = "Updated"
        try database.saveMessage(message)
        
        // 验证：只有一条消息，内容是更新后的
        let readMessage = database.getMessage(messageID: "msg_dup")
        XCTAssertEqual(readMessage?.content, "Updated")
        
        // 验证：数据库中只有一条记录
        let allMessages = database.getMessages(
            conversationID: message.conversationID,
            limit: 100
        )
        let duplicates = allMessages.filter { $0.messageID == "msg_dup" }
        XCTAssertEqual(duplicates.count, 1)
        
        IMLogger.shared.info("✅ 消息去重测试通过")
    }
    
    // MARK: - 状态更新测试
    
    func testUpdateMessageStatus() throws {
        // 保存消息
        let message = createTestMessage(messageID: "msg_status")
        message.status = .sending
        try database.saveMessage(message)
        
        // 更新状态为已发送
        try database.updateMessageStatus(
            messageID: "msg_status",
            status: .sent
        )
        
        // 验证
        let readMessage = database.getMessage(messageID: "msg_status")
        XCTAssertEqual(readMessage?.status, .sent)
        
        IMLogger.shared.info("✅ 更新消息状态测试通过")
    }
    
    func testMarkMessagesAsRead() throws {
        // 保存多条未读消息
        var messages: [IMMessage] = []
        for i in 0..<5 {
            let message = createTestMessage(
                messageID: "msg_read_\(i)",
                conversationID: "conv_read"
            )
            message.isRead = false
            messages.append(message)
        }
        try database.saveMessages(messages)
        
        // 标记为已读
        let messageIDs = messages.map { $0.messageID }
        try database.markMessagesAsRead(messageIDs: messageIDs)
        
        // 验证
        for id in messageIDs {
            let message = database.getMessage(messageID: id)
            XCTAssertEqual(message?.isRead, true)
        }
        
        IMLogger.shared.info("✅ 批量标记已读测试通过")
    }
    
    // MARK: - 时间范围查询测试
    
    func testGetMessagesInTimeRange() throws {
        // 准备消息，时间间隔 1 秒
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        var messages: [IMMessage] = []
        for i in 0..<10 {
            let message = createTestMessage(
                messageID: "msg_time_\(i)",
                conversationID: "conv_time"
            )
            message.createTime = baseTime + Int64(i * 1000)
            messages.append(message)
        }
        try database.saveMessages(messages)
        
        // 查询时间范围：baseTime+2000 到 baseTime+7000
        let startTime = baseTime + 2000
        let endTime = baseTime + 7000
        
        let results = database.getMessagesInTimeRange(
            conversationID: "conv_time",
            startTime: startTime,
            endTime: endTime
        )
        
        // 应该返回 6 条消息（索引 2-7）
        XCTAssertEqual(results.count, 6)
        
        // 验证时间范围
        for message in results {
            XCTAssertGreaterThanOrEqual(message.createTime, startTime)
            XCTAssertLessThanOrEqual(message.createTime, endTime)
        }
        
        IMLogger.shared.info("✅ 时间范围查询测试通过")
    }
    
    // MARK: - seq 相关测试
    
    func testGetMaxSeq() throws {
        // 保存不同 seq 的消息
        let message1 = createTestMessage(messageID: "msg_seq1", seq: 100)
        let message2 = createTestMessage(messageID: "msg_seq2", seq: 200)
        let message3 = createTestMessage(messageID: "msg_seq3", seq: 150)
        
        try database.saveMessages([message1, message2, message3])
        
        // 获取最大 seq
        let maxSeq = database.getMaxSeq()
        
        XCTAssertEqual(maxSeq, 200)
        
        IMLogger.shared.info("✅ 获取最大 seq 测试通过")
    }
    
    func testGetOldestAndLatestTime() throws {
        // 准备消息
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        let message1 = createTestMessage(messageID: "msg_t1")
        message1.createTime = baseTime
        message1.conversationID = "conv_time_test"
        
        let message2 = createTestMessage(messageID: "msg_t2")
        message2.createTime = baseTime + 10000
        message2.conversationID = "conv_time_test"
        
        try database.saveMessages([message1, message2])
        
        // 获取最早和最晚时间
        let oldestTime = database.getOldestMessageTime(conversationID: "conv_time_test")
        let latestTime = database.getLatestMessageTime(conversationID: "conv_time_test")
        
        XCTAssertEqual(oldestTime, baseTime)
        XCTAssertEqual(latestTime, baseTime + 10000)
        
        IMLogger.shared.info("✅ 获取最早/最晚时间测试通过")
    }
    
    // MARK: - 性能测试
    
    func testQueryPerformance() throws {
        // 准备 1000 条消息
        for batch in 0..<10 {
            let messages = createTestMessages(
                count: 100,
                conversationID: "conv_perf",
                startSeq: Int64(batch * 100)
            )
            try database.saveMessages(messages)
        }
        
        // 测试查询性能
        try assertPerformance(maxDuration: 0.01, {
            let _ = self.database.getMessages(conversationID: "conv_perf", limit: 20)
        }, description: "查询最新 20 条消息")
        
        IMLogger.shared.info("✅ 查询性能测试通过")
    }
    
    func testSearchPerformance() throws {
        // 准备 500 条消息
        for i in 0..<500 {
            let message = createTestMessage(
                messageID: "msg_search_perf_\(i)",
                content: "Message number \(i)"
            )
            try database.saveMessage(message)
        }
        
        // 测试搜索性能
        try assertPerformance(maxDuration: 0.05, {
            let _ = self.database.searchMessages(
                keyword: "number",
                conversationID: nil,
                limit: 20
            )
        }, description: "搜索消息")
        
        IMLogger.shared.info("✅ 搜索性能测试通过")
    }
}


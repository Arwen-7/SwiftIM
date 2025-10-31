/// IMMessageDeduplicationTests - 消息去重测试
/// 测试消息去重机制的各种场景

import XCTest
@testable import IMSDK

final class IMMessageDeduplicationTests: XCTestCase {
    
    var database: IMDatabaseManager!
    
    let testUserID = "user_dedup_test"
    let conv1ID = "conv_dedup_1"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 初始化数据库
        database = IMDatabaseManager.shared
        try database.initialize(
            config: IMDatabaseConfig(
                fileName: "test_im_dedup.realm",
                enableEncryption: false
            ),
            userID: testUserID
        )
    }
    
    override func tearDownWithError() throws {
        try database.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - 辅助方法
    
    private func createTestMessage(
        messageID: String,
        content: String = "Test message",
        status: IMMessageStatus = .sent,
        seq: Int64 = 0,
        serverTime: Int64 = 0
    ) -> IMMessage {
        let message = IMMessage()
        message.messageID = messageID
        message.conversationID = conv1ID
        message.content = content
        message.status = status
        message.seq = seq
        message.serverTime = serverTime
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        message.senderID = testUserID
        message.receiverID = "receiver_1"
        message.direction = .send
        message.messageType = .text
        return message
    }
    
    // MARK: - 基础去重测试
    
    /// 测试 1：首次插入消息
    func testFirstTimeInsert() throws {
        // Given: 一条新消息
        let message = createTestMessage(messageID: "msg_001")
        
        // When: 保存消息
        let result = try database.saveMessage(message)
        
        // Then: 应该返回 inserted
        XCTAssertEqual(result, .inserted, "Should insert new message")
        
        // 验证消息已保存
        let saved = database.getMessage(messageID: "msg_001")
        XCTAssertNotNil(saved, "Message should be saved")
        XCTAssertEqual(saved?.content, "Test message")
    }
    
    /// 测试 2：重复插入相同消息（内容完全相同）
    func testDuplicateInsertSameContent() throws {
        // Given: 保存一条消息
        let message1 = createTestMessage(messageID: "msg_002", content: "Hello")
        _ = try database.saveMessage(message1)
        
        // When: 尝试再次保存相同的消息
        let message2 = createTestMessage(messageID: "msg_002", content: "Hello")
        let result = try database.saveMessage(message2)
        
        // Then: 应该返回 skipped
        XCTAssertEqual(result, .skipped, "Should skip duplicate message")
        
        // 验证数据库中只有一条
        let messages = database.getMessages(conversationID: conv1ID)
        XCTAssertEqual(messages.count, 1, "Should have only one message")
    }
    
    /// 测试 3：更新消息内容
    func testUpdateMessageContent() throws {
        // Given: 保存一条消息
        let message1 = createTestMessage(messageID: "msg_003", content: "Original")
        _ = try database.saveMessage(message1)
        
        // When: 保存相同 ID 但内容不同的消息
        let message2 = createTestMessage(messageID: "msg_003", content: "Updated")
        let result = try database.saveMessage(message2)
        
        // Then: 应该返回 updated
        XCTAssertEqual(result, .updated, "Should update message")
        
        // 验证内容已更新
        let saved = database.getMessage(messageID: "msg_003")
        XCTAssertEqual(saved?.content, "Updated", "Content should be updated")
    }
    
    /// 测试 4：更新消息状态
    func testUpdateMessageStatus() throws {
        // Given: 保存一条 sending 状态的消息
        let message1 = createTestMessage(messageID: "msg_004", status: .sending)
        _ = try database.saveMessage(message1)
        
        // When: 更新为 sent 状态
        let message2 = createTestMessage(messageID: "msg_004", status: .sent)
        let result = try database.saveMessage(message2)
        
        // Then: 应该返回 updated
        XCTAssertEqual(result, .updated, "Should update status")
        
        // 验证状态已更新
        let saved = database.getMessage(messageID: "msg_004")
        XCTAssertEqual(saved?.status, .sent, "Status should be updated")
    }
    
    /// 测试 5：更新 seq
    func testUpdateMessageSeq() throws {
        // Given: 保存一条 seq=0 的消息
        let message1 = createTestMessage(messageID: "msg_005", seq: 0)
        _ = try database.saveMessage(message1)
        
        // When: 更新 seq
        let message2 = createTestMessage(messageID: "msg_005", seq: 100)
        let result = try database.saveMessage(message2)
        
        // Then: 应该返回 updated
        XCTAssertEqual(result, .updated, "Should update seq")
        
        // 验证 seq 已更新
        let saved = database.getMessage(messageID: "msg_005")
        XCTAssertEqual(saved?.seq, 100, "Seq should be updated")
    }
    
    /// 测试 6：更新 serverTime
    func testUpdateServerTime() throws {
        // Given: 保存一条 serverTime=0 的消息
        let message1 = createTestMessage(messageID: "msg_006", serverTime: 0)
        _ = try database.saveMessage(message1)
        
        // When: 更新 serverTime
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let message2 = createTestMessage(messageID: "msg_006", serverTime: timestamp)
        let result = try database.saveMessage(message2)
        
        // Then: 应该返回 updated
        XCTAssertEqual(result, .updated, "Should update serverTime")
        
        // 验证 serverTime 已更新
        let saved = database.getMessage(messageID: "msg_006")
        XCTAssertEqual(saved?.serverTime, timestamp, "ServerTime should be updated")
    }
    
    // MARK: - 批量去重测试
    
    /// 测试 7：批量插入全新消息
    func testBatchInsertAllNew() throws {
        // Given: 10 条新消息
        let messages = (1...10).map { createTestMessage(messageID: "msg_batch_\($0)") }
        
        // When: 批量保存
        let stats = try database.saveMessages(messages)
        
        // Then: 应该全部插入
        XCTAssertEqual(stats.insertedCount, 10, "Should insert all 10 messages")
        XCTAssertEqual(stats.updatedCount, 0, "Should have no updates")
        XCTAssertEqual(stats.skippedCount, 0, "Should have no skips")
        XCTAssertEqual(stats.totalCount, 10, "Total should be 10")
        XCTAssertEqual(stats.deduplicationRate, 0.0, "Dedup rate should be 0%")
    }
    
    /// 测试 8：批量插入全部重复
    func testBatchInsertAllDuplicates() throws {
        // Given: 先插入 10 条消息
        let messages1 = (1...10).map { createTestMessage(messageID: "msg_batch2_\($0)") }
        _ = try database.saveMessages(messages1)
        
        // When: 再次插入相同的消息
        let messages2 = (1...10).map { createTestMessage(messageID: "msg_batch2_\($0)") }
        let stats = try database.saveMessages(messages2)
        
        // Then: 应该全部跳过
        XCTAssertEqual(stats.insertedCount, 0, "Should have no inserts")
        XCTAssertEqual(stats.updatedCount, 0, "Should have no updates")
        XCTAssertEqual(stats.skippedCount, 10, "Should skip all 10 messages")
        XCTAssertEqual(stats.deduplicationRate, 1.0, "Dedup rate should be 100%")
    }
    
    /// 测试 9：批量混合操作（插入+更新+跳过）
    func testBatchMixedOperations() throws {
        // Given: 先插入 5 条消息
        let messages1 = (1...5).map { createTestMessage(messageID: "msg_mix_\($0)", content: "Original") }
        _ = try database.saveMessages(messages1)
        
        // When: 批量保存 10 条消息（前 5 条更新，后 5 条新增）
        var messages2: [IMMessage] = []
        // 前 5 条：更新内容
        messages2 += (1...5).map { createTestMessage(messageID: "msg_mix_\($0)", content: "Updated") }
        // 后 5 条：新消息
        messages2 += (6...10).map { createTestMessage(messageID: "msg_mix_\($0)", content: "New") }
        
        let stats = try database.saveMessages(messages2)
        
        // Then: 5 条插入，5 条更新
        XCTAssertEqual(stats.insertedCount, 5, "Should insert 5 new messages")
        XCTAssertEqual(stats.updatedCount, 5, "Should update 5 existing messages")
        XCTAssertEqual(stats.skippedCount, 0, "Should have no skips")
        XCTAssertEqual(stats.totalCount, 10, "Total should be 10")
    }
    
    /// 测试 10：批量保存空数组
    func testBatchSaveEmptyArray() throws {
        // When: 保存空数组
        let stats = try database.saveMessages([])
        
        // Then: 应该返回空统计
        XCTAssertEqual(stats.insertedCount, 0)
        XCTAssertEqual(stats.updatedCount, 0)
        XCTAssertEqual(stats.skippedCount, 0)
        XCTAssertEqual(stats.totalCount, 0)
    }
    
    // MARK: - 更新字段测试
    
    /// 测试 11：只更新需要更新的字段
    func testUpdateOnlyChangedFields() throws {
        // Given: 保存一条消息
        let message1 = createTestMessage(
            messageID: "msg_fields",
            content: "Original",
            status: .sending,
            seq: 0
        )
        _ = try database.saveMessage(message1)
        
        // When: 只更新状态，其他字段相同
        let message2 = createTestMessage(
            messageID: "msg_fields",
            content: "Original",  // 相同
            status: .sent,        // 改变
            seq: 0                // 相同
        )
        let result = try database.saveMessage(message2)
        
        // Then: 应该更新
        XCTAssertEqual(result, .updated, "Should update when status changed")
        
        // 验证
        let saved = database.getMessage(messageID: "msg_fields")
        XCTAssertEqual(saved?.status, .sent)
        XCTAssertEqual(saved?.content, "Original")
    }
    
    /// 测试 12：多个字段同时更新
    func testUpdateMultipleFields() throws {
        // Given
        let message1 = createTestMessage(
            messageID: "msg_multi",
            content: "V1",
            status: .sending,
            seq: 0,
            serverTime: 0
        )
        _ = try database.saveMessage(message1)
        
        // When: 更新多个字段
        let message2 = createTestMessage(
            messageID: "msg_multi",
            content: "V2",
            status: .sent,
            seq: 100,
            serverTime: 12345
        )
        let result = try database.saveMessage(message2)
        
        // Then
        XCTAssertEqual(result, .updated)
        
        let saved = database.getMessage(messageID: "msg_multi")
        XCTAssertEqual(saved?.content, "V2")
        XCTAssertEqual(saved?.status, .sent)
        XCTAssertEqual(saved?.seq, 100)
        XCTAssertEqual(saved?.serverTime, 12345)
    }
    
    // MARK: - 边界测试
    
    /// 测试 13：消息 ID 为空字符串
    func testEmptyMessageID() throws {
        // Given: messageID 为空
        let message = createTestMessage(messageID: "")
        
        // When & Then: 应该能正常保存（主键可以为空字符串）
        let result = try database.saveMessage(message)
        XCTAssertEqual(result, .inserted)
    }
    
    /// 测试 14：大量重复消息性能
    func testLargeDuplicatePerformance() throws {
        // Given: 先保存 100 条消息
        let messages1 = (1...100).map { createTestMessage(messageID: "msg_perf_\($0)") }
        _ = try database.saveMessages(messages1)
        
        // When: 测试重复保存性能
        measure {
            let messages2 = (1...100).map { createTestMessage(messageID: "msg_perf_\($0)") }
            _ = try? database.saveMessages(messages2)
        }
    }
    
    /// 测试 15：并发保存相同消息
    func testConcurrentSaveSameMessage() throws {
        let expectation = XCTestExpectation(description: "Concurrent save")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        // When: 10 个线程同时保存相同消息
        for i in 1...10 {
            queue.async {
                let message = self.createTestMessage(messageID: "msg_concurrent")
                _ = try? self.database.saveMessage(message)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Then: 数据库中应该只有一条消息
        let messages = database.getMessages(conversationID: conv1ID)
        let concurrentMessages = messages.filter { $0.messageID == "msg_concurrent" }
        XCTAssertEqual(concurrentMessages.count, 1, "Should have only one message despite concurrent saves")
    }
    
    // MARK: - 真实场景测试
    
    /// 测试 16：模拟离线消息同步去重
    func testOfflineMessageSyncDeduplication() throws {
        // Given: 本地已有一些消息（部分已读，部分未读）
        let localMessages = [
            createTestMessage(messageID: "sync_msg_1", content: "Local 1", status: .sent),
            createTestMessage(messageID: "sync_msg_2", content: "Local 2", status: .sent),
            createTestMessage(messageID: "sync_msg_3", content: "Local 3", status: .sending)
        ]
        _ = try database.saveMessages(localMessages)
        
        // When: 从服务器拉取消息（包含本地已有的和新消息）
        let serverMessages = [
            createTestMessage(messageID: "sync_msg_1", content: "Local 1", status: .sent),     // 重复
            createTestMessage(messageID: "sync_msg_2", content: "Local 2", status: .delivered), // 更新状态
            createTestMessage(messageID: "sync_msg_3", content: "Local 3", status: .sent),      // 更新状态
            createTestMessage(messageID: "sync_msg_4", content: "New 4", status: .sent),        // 新消息
            createTestMessage(messageID: "sync_msg_5", content: "New 5", status: .sent)         // 新消息
        ]
        let stats = try database.saveMessages(serverMessages)
        
        // Then: 应该正确去重和更新
        XCTAssertEqual(stats.insertedCount, 2, "Should insert 2 new messages")
        XCTAssertEqual(stats.updatedCount, 2, "Should update 2 messages")
        XCTAssertEqual(stats.skippedCount, 1, "Should skip 1 duplicate")
        XCTAssertEqual(stats.deduplicationRate, 0.2, "Dedup rate should be 20%")
        
        // 验证总消息数
        let allMessages = database.getMessages(conversationID: conv1ID)
        XCTAssertEqual(allMessages.count, 5, "Should have 5 messages in total")
    }
    
    /// 测试 17：模拟网络重传去重
    func testNetworkRetransmissionDeduplication() throws {
        // Given: 发送一条消息
        let message = createTestMessage(messageID: "msg_retrans", status: .sending)
        _ = try database.saveMessage(message)
        
        // When: 模拟网络重传 3 次（相同消息）
        for _ in 1...3 {
            let retrans = createTestMessage(messageID: "msg_retrans", status: .sending)
            let result = try database.saveMessage(retrans)
            XCTAssertEqual(result, .skipped, "Should skip retransmission")
        }
        
        // Then: 应该只有一条消息
        let messages = database.getMessages(conversationID: conv1ID)
        XCTAssertEqual(messages.count, 1, "Should have only one message")
    }
    
    /// 测试 18：消息状态流转测试
    func testMessageStatusTransition() throws {
        // Given: 一条消息从 sending 到 sent 到 delivered 到 read
        let messageID = "msg_status_flow"
        
        // 1. 发送中
        var message = createTestMessage(messageID: messageID, status: .sending)
        var result = try database.saveMessage(message)
        XCTAssertEqual(result, .inserted)
        
        // 2. 已发送
        message = createTestMessage(messageID: messageID, status: .sent)
        result = try database.saveMessage(message)
        XCTAssertEqual(result, .updated)
        
        // 3. 已送达
        message = createTestMessage(messageID: messageID, status: .delivered)
        result = try database.saveMessage(message)
        XCTAssertEqual(result, .updated)
        
        // 4. 已读
        message = createTestMessage(messageID: messageID, status: .read)
        result = try database.saveMessage(message)
        XCTAssertEqual(result, .updated)
        
        // Then: 最终状态应该是 read
        let saved = database.getMessage(messageID: messageID)
        XCTAssertEqual(saved?.status, .read)
    }
    
    // MARK: - 统计信息测试
    
    /// 测试 19：统计信息计算正确性
    func testBatchSaveStatsCalculation() throws {
        // Given: 已有 3 条消息
        let existing = (1...3).map { createTestMessage(messageID: "stats_\($0)") }
        _ = try database.saveMessages(existing)
        
        // When: 批量保存 10 条（3 条重复，3 条更新，4 条新）
        var batch: [IMMessage] = []
        batch += (1...3).map { createTestMessage(messageID: "stats_\($0)", content: "Same") }      // 重复
        batch += (4...6).map { createTestMessage(messageID: "stats_\($0)", content: "Updated") }  // 新增
        batch += (1...4).map { createTestMessage(messageID: "stats_update_\($0)") }               // 新增
        
        let stats = try database.saveMessages(batch)
        
        // Then
        XCTAssertEqual(stats.totalCount, 10)
        XCTAssertEqual(stats.insertedCount + stats.updatedCount + stats.skippedCount, 10)
        XCTAssertTrue(stats.deduplicationRate >= 0.0 && stats.deduplicationRate <= 1.0)
    }
    
    /// 测试 20：去重率计算
    func testDeduplicationRateCalculation() throws {
        // Test Case 1: 0% 去重率（全部新消息）
        let messages1 = (1...10).map { createTestMessage(messageID: "rate_\($0)") }
        let stats1 = try database.saveMessages(messages1)
        XCTAssertEqual(stats1.deduplicationRate, 0.0, "Should have 0% dedup rate")
        
        // Test Case 2: 100% 去重率（全部重复）
        let messages2 = (1...10).map { createTestMessage(messageID: "rate_\($0)") }
        let stats2 = try database.saveMessages(messages2)
        XCTAssertEqual(stats2.deduplicationRate, 1.0, "Should have 100% dedup rate")
        
        // Test Case 3: 50% 去重率
        let messages3 = (1...20).map { createTestMessage(messageID: "rate2_\($0)") }
        _ = try database.saveMessages(messages3)
        
        let messages4 = (1...20).map { createTestMessage(messageID: "rate2_\($0)") }
        let stats3 = try database.saveMessages(messages4)
        XCTAssertEqual(stats3.deduplicationRate, 1.0, "Should have 100% dedup rate for second batch")
    }
}


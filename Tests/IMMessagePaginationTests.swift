/// IMMessagePaginationTests - 消息分页加载测试
/// 测试消息分页加载的各种场景

import XCTest
@testable import IMSDK

final class IMMessagePaginationTests: XCTestCase {
    
    var database: IMDatabaseManager!
    var messageManager: IMMessageManager!
    
    let testUserID = "test_user_123"
    let testConversationID = "conv_pagination_test"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 初始化测试组件
        database = IMDatabaseManager.shared
        try database.initialize(
            config: IMDatabaseConfig(
                fileName: "test_im_pagination.realm",
                enableEncryption: false
            ),
            userID: testUserID
        )
        
        let protocolHandler = IMProtocolHandler()
        messageManager = IMMessageManager(
            database: database,
            protocolHandler: protocolHandler,
            websocket: nil
        )
        
        // 插入测试数据
        try insertTestMessages()
    }
    
    override func tearDownWithError() throws {
        // 清理测试数据
        try database.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - 测试数据准备
    
    /// 插入测试消息（100 条）
    private func insertTestMessages() throws {
        var messages: [IMMessage] = []
        
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        for i in 0..<100 {
            let message = IMMessage()
            message.messageID = "msg_\(i)"
            message.conversationID = testConversationID
            message.senderID = "user_sender"
            message.content = "Test message \(i)"
            message.createTime = baseTime - Int64(i * 1000)  // 每条消息间隔 1 秒
            message.seq = Int64(100 - i)  // seq 从 100 到 1
            message.messageType = .text
            message.direction = .receive
            messages.append(message)
        }
        
        try database.saveMessages(messages)
        
        IMLogger.shared.info("Inserted \(messages.count) test messages")
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：首次加载（加载最新的 20 条）
    func testLoadInitialMessages() throws {
        // When: 加载最新的 20 条消息
        let messages = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            startTime: 0,
            count: 20
        )
        
        // Then: 应该返回 20 条消息
        XCTAssertEqual(messages.count, 20, "Should load 20 messages")
        
        // 消息应该按时间倒序（最新的在前）
        for i in 0..<messages.count-1 {
            XCTAssertGreaterThan(messages[i].createTime, messages[i+1].createTime, 
                                "Messages should be ordered by time descending")
        }
        
        // 第一条应该是最新的消息
        XCTAssertEqual(messages.first?.messageID, "msg_0", "First message should be the newest")
    }
    
    /// 测试 2：加载更多（分页）
    func testLoadMoreMessages() throws {
        // Given: 已加载第一页
        let firstPage = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            count: 20
        )
        
        XCTAssertEqual(firstPage.count, 20, "First page should have 20 messages")
        
        // When: 加载第二页（使用第一页最后一条消息的时间）
        guard let lastMessage = firstPage.last else {
            XCTFail("First page should have messages")
            return
        }
        
        let secondPage = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            startTime: lastMessage.createTime,
            count: 20
        )
        
        // Then: 应该返回不同的 20 条消息
        XCTAssertEqual(secondPage.count, 20, "Second page should have 20 messages")
        
        // 第二页的消息应该比第一页的更早
        XCTAssertLessThan(secondPage.first!.createTime, firstPage.last!.createTime,
                         "Second page messages should be older than first page")
        
        // 确保没有重复消息
        let firstPageIDs = Set(firstPage.map { $0.messageID })
        let secondPageIDs = Set(secondPage.map { $0.messageID })
        let intersection = firstPageIDs.intersection(secondPageIDs)
        XCTAssertTrue(intersection.isEmpty, "Should have no duplicate messages between pages")
    }
    
    /// 测试 3：加载所有页
    func testLoadAllPages() throws {
        var allMessages: [IMMessage] = []
        var startTime: Int64 = 0
        let pageSize = 20
        
        // When: 循环加载所有页
        while true {
            let messages = try messageManager.getHistoryMessages(
                conversationID: testConversationID,
                startTime: startTime,
                count: pageSize
            )
            
            if messages.isEmpty {
                break
            }
            
            allMessages.append(contentsOf: messages)
            
            // 更新 startTime 为最后一条消息的时间
            startTime = messages.last!.createTime
            
            // 如果这一页不满，说明没有更多了
            if messages.count < pageSize {
                break
            }
        }
        
        // Then: 应该加载了所有 100 条消息
        XCTAssertEqual(allMessages.count, 100, "Should load all 100 messages")
        
        // 确保没有重复
        let uniqueIDs = Set(allMessages.map { $0.messageID })
        XCTAssertEqual(uniqueIDs.count, 100, "Should have 100 unique messages")
    }
    
    /// 测试 4：基于 seq 的分页
    func testLoadMessagesBySeq() throws {
        // When: 基于 seq 加载
        let messages = try messageManager.getHistoryMessagesBySeq(
            conversationID: testConversationID,
            startSeq: 0,
            count: 20
        )
        
        // Then: 应该返回 20 条消息
        XCTAssertEqual(messages.count, 20, "Should load 20 messages")
        
        // 消息应该按 seq 倒序
        for i in 0..<messages.count-1 {
            XCTAssertGreaterThan(messages[i].seq, messages[i+1].seq,
                                "Messages should be ordered by seq descending")
        }
    }
    
    /// 测试 5：获取消息总数
    func testGetMessageCount() {
        // When: 获取消息总数
        let count = messageManager.getMessageCount(conversationID: testConversationID)
        
        // Then: 应该是 100
        XCTAssertEqual(count, 100, "Should have 100 messages")
    }
    
    /// 测试 6：检查是否还有更多消息
    func testHasMoreMessages() {
        // Given: 已加载 20 条
        let currentCount = 20
        
        // When: 检查是否还有更多
        let hasMore = messageManager.hasMoreMessages(
            conversationID: testConversationID,
            currentCount: currentCount
        )
        
        // Then: 应该还有更多
        XCTAssertTrue(hasMore, "Should have more messages")
        
        // When: 已加载全部 100 条
        let allLoaded = 100
        let noMore = messageManager.hasMoreMessages(
            conversationID: testConversationID,
            currentCount: allLoaded
        )
        
        // Then: 不应该有更多
        XCTAssertFalse(noMore, "Should have no more messages")
    }
    
    /// 测试 7：获取最早和最新的消息时间
    func testGetOldestAndLatestMessageTime() {
        // When: 获取最早的消息时间
        let oldestTime = messageManager.getOldestMessageTime(conversationID: testConversationID)
        
        // When: 获取最新的消息时间
        let latestTime = messageManager.getLatestMessageTime(conversationID: testConversationID)
        
        // Then: 最新时间应该大于最早时间
        XCTAssertGreaterThan(latestTime, oldestTime, "Latest time should be greater than oldest time")
        
        // 最新时间应该是 msg_0 的时间
        // 最早时间应该是 msg_99 的时间
        XCTAssertGreaterThan(oldestTime, 0, "Oldest time should be greater than 0")
        XCTAssertGreaterThan(latestTime, 0, "Latest time should be greater than 0")
    }
    
    /// 测试 8：获取指定时间范围内的消息
    func testGetMessagesInTimeRange() throws {
        // Given: 获取第一条和第 10 条消息的时间
        let allMessages = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            count: 100
        )
        
        let startTime = allMessages[9].createTime  // 第 10 条
        let endTime = allMessages[0].createTime    // 第 1 条
        
        // When: 获取这个时间范围内的消息
        let messages = try messageManager.getMessagesInTimeRange(
            conversationID: testConversationID,
            startTime: startTime,
            endTime: endTime
        )
        
        // Then: 应该是 10 条消息（包含边界）
        XCTAssertEqual(messages.count, 10, "Should have 10 messages in this time range")
        
        // 所有消息的时间应该在范围内
        for message in messages {
            XCTAssertGreaterThanOrEqual(message.createTime, startTime, "Message time should be >= startTime")
            XCTAssertLessThanOrEqual(message.createTime, endTime, "Message time should be <= endTime")
        }
    }
    
    // MARK: - 边界测试
    
    /// 测试 9：空会话（没有消息）
    func testEmptyConversation() throws {
        let emptyConvID = "empty_conv"
        
        // When: 加载空会话的消息
        let messages = try messageManager.getHistoryMessages(
            conversationID: emptyConvID,
            count: 20
        )
        
        // Then: 应该返回空数组
        XCTAssertTrue(messages.isEmpty, "Should return empty array for empty conversation")
        
        // 消息总数应该是 0
        let count = messageManager.getMessageCount(conversationID: emptyConvID)
        XCTAssertEqual(count, 0, "Message count should be 0 for empty conversation")
    }
    
    /// 测试 10：消息数少于页大小
    func testFewMessages() throws {
        let fewConvID = "few_conv"
        
        // Given: 只插入 5 条消息
        var messages: [IMMessage] = []
        for i in 0..<5 {
            let message = IMMessage()
            message.messageID = "few_\(i)"
            message.conversationID = fewConvID
            message.senderID = "user_sender"
            message.content = "Few message \(i)"
            message.createTime = Int64(Date().timeIntervalSince1970 * 1000) - Int64(i * 1000)
            messages.append(message)
        }
        try database.saveMessages(messages)
        
        // When: 请求 20 条消息
        let loadedMessages = try messageManager.getHistoryMessages(
            conversationID: fewConvID,
            count: 20
        )
        
        // Then: 只应该返回 5 条
        XCTAssertEqual(loadedMessages.count, 5, "Should only return 5 messages")
        
        // hasMore 应该返回 false
        let hasMore = messageManager.hasMoreMessages(
            conversationID: fewConvID,
            currentCount: 5
        )
        XCTAssertFalse(hasMore, "Should have no more messages")
    }
    
    /// 测试 11：极大的 startTime
    func testVeryLargeStartTime() throws {
        // When: 使用 Int64.max 作为 startTime（表示从最新开始）
        let messages = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            startTime: Int64.max,
            count: 20
        )
        
        // Then: 应该正常返回最新的 20 条消息
        XCTAssertEqual(messages.count, 20, "Should load 20 messages with Int64.max startTime")
    }
    
    /// 测试 12：startTime 为 0（表示从最新开始）
    func testStartTimeZero() throws {
        // When: startTime = 0
        let messages = try messageManager.getHistoryMessages(
            conversationID: testConversationID,
            startTime: 0,
            count: 20
        )
        
        // Then: 应该返回最新的 20 条消息
        XCTAssertEqual(messages.count, 20, "Should load 20 messages with startTime = 0")
        XCTAssertEqual(messages.first?.messageID, "msg_0", "First message should be the newest")
    }
    
    // MARK: - 性能测试
    
    /// 测试 13：大量消息的查询性能
    func testLargeDatasetPerformance() throws {
        // Given: 插入大量消息（1000 条）
        let largeConvID = "large_conv"
        var largeMessages: [IMMessage] = []
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        for i in 0..<1000 {
            let message = IMMessage()
            message.messageID = "large_\(i)"
            message.conversationID = largeConvID
            message.senderID = "user_sender"
            message.content = "Large message \(i)"
            message.createTime = baseTime - Int64(i * 1000)
            message.seq = Int64(1000 - i)
            largeMessages.append(message)
        }
        try database.saveMessages(largeMessages)
        
        // When: 测试查询性能
        let startTime = Date()
        
        let messages = try messageManager.getHistoryMessages(
            conversationID: largeConvID,
            startTime: baseTime - 500_000,  // 从中间某个位置开始
            count: 20
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: 应该很快（< 100ms）
        XCTAssertLessThan(duration, 0.1, "Query should complete in less than 100ms")
        XCTAssertEqual(messages.count, 20, "Should load 20 messages")
        
        print("Query 1000 messages dataset, load 20 messages: \(duration * 1000)ms")
    }
    
    /// 测试 14：连续分页查询性能
    func testContinuousPaginationPerformance() throws {
        // When: 连续加载 5 页
        let startTime = Date()
        
        var currentTime: Int64 = 0
        for _ in 0..<5 {
            let messages = try messageManager.getHistoryMessages(
                conversationID: testConversationID,
                startTime: currentTime,
                count: 20
            )
            
            currentTime = messages.last?.createTime ?? 0
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: 应该很快（< 500ms）
        XCTAssertLessThan(duration, 0.5, "5 page queries should complete in less than 500ms")
        
        print("Continuous 5 page queries: \(duration * 1000)ms")
    }
}


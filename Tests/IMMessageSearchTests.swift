/// IMMessageSearchTests - 消息搜索测试
/// 测试消息搜索的各种场景

import XCTest
@testable import IMSDK

final class IMMessageSearchTests: XCTestCase {
    
    var database: IMDatabaseManager!
    var messageManager: IMMessageManager!
    
    let testUserID = "test_user_123"
    let conv1ID = "conv_search_1"
    let conv2ID = "conv_search_2"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 初始化测试组件
        database = IMDatabaseManager.shared
        try database.initialize(
            config: IMDatabaseConfig(
                fileName: "test_im_search.realm",
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
    
    /// 插入测试消息
    private func insertTestMessages() throws {
        var messages: [IMMessage] = []
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 会话 1 的消息
        let conv1Messages = [
            ("重要文件已发送", IMMessageType.text, "user1"),
            ("这是一个重要的会议通知", .text, "user2"),
            ("请查收附件", .file, "user1"),
            ("今天天气很好", .text, "user3"),
            ("重要：明天下午开会", .text, "user1"),
            ("收到", .text, "user2"),
            ("重要项目进展", .text, "user1"),
            ("好的", .text, "user3"),
        ]
        
        for (index, (content, type, sender)) in conv1Messages.enumerated() {
            let message = IMMessage()
            message.messageID = "conv1_msg_\(index)"
            message.conversationID = conv1ID
            message.senderID = sender
            message.content = content
            message.messageType = type
            message.createTime = baseTime - Int64(index * 1000)
            message.direction = .receive
            messages.append(message)
        }
        
        // 会话 2 的消息
        let conv2Messages = [
            ("重要提醒：明天休息", IMMessageType.text, "user4"),
            ("谢谢", .text, "user5"),
            ("周末愉快", .text, "user4"),
            ("Important information", .text, "user5"),  // 英文
            ("重要数据已更新", .text, "user4"),
        ]
        
        for (index, (content, type, sender)) in conv2Messages.enumerated() {
            let message = IMMessage()
            message.messageID = "conv2_msg_\(index)"
            message.conversationID = conv2ID
            message.senderID = sender
            message.content = content
            message.messageType = type
            message.createTime = baseTime - Int64((index + 10) * 1000)
            message.direction = .receive
            messages.append(message)
        }
        
        try database.saveMessages(messages)
        
        IMLogger.shared.info("Inserted \(messages.count) test messages")
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：基础全局搜索
    func testBasicGlobalSearch() throws {
        // When: 搜索"重要"
        let results = try messageManager.searchMessages(
            keyword: "重要"
        )
        
        // Then: 应该找到所有包含"重要"的消息
        XCTAssertGreaterThan(results.count, 0, "Should find messages containing '重要'")
        
        // 验证所有结果都包含关键词
        for message in results {
            XCTAssertTrue(message.content.contains("重要"), 
                         "All results should contain the keyword")
        }
        
        print("Found \(results.count) messages containing '重要'")
    }
    
    /// 测试 2：会话内搜索
    func testSearchInConversation() throws {
        // When: 在会话 1 内搜索"重要"
        let results = try messageManager.searchMessages(
            keyword: "重要",
            conversationID: conv1ID
        )
        
        // Then: 只应该返回会话 1 的消息
        XCTAssertGreaterThan(results.count, 0, "Should find messages in conversation 1")
        
        for message in results {
            XCTAssertEqual(message.conversationID, conv1ID, 
                          "All results should be from conversation 1")
            XCTAssertTrue(message.content.contains("重要"), 
                         "All results should contain the keyword")
        }
        
        print("Found \(results.count) messages in conversation 1")
    }
    
    /// 测试 3：不区分大小写
    func testCaseInsensitiveSearch() throws {
        // Given: 有消息包含"Important"
        
        // When: 搜索"important"（小写）
        let results = try messageManager.searchMessages(
            keyword: "important"
        )
        
        // Then: 应该能找到"Important"（大写）
        XCTAssertGreaterThan(results.count, 0, "Should find messages (case insensitive)")
        
        let hasImportant = results.contains { $0.content.lowercased().contains("important") }
        XCTAssertTrue(hasImportant, "Should find 'Important' when searching 'important'")
    }
    
    /// 测试 4：按消息类型筛选
    func testSearchByMessageType() throws {
        // When: 搜索文本类型的消息
        let textResults = try messageManager.searchMessages(
            keyword: "重要",
            messageTypes: [.text]
        )
        
        // Then: 所有结果都应该是文本类型
        for message in textResults {
            XCTAssertEqual(message.messageType, .text, "All results should be text messages")
        }
        
        // When: 搜索文件类型的消息
        let fileResults = try messageManager.searchMessages(
            keyword: "附件",
            messageTypes: [.file]
        )
        
        // Then: 应该找到文件类型的消息
        for message in fileResults {
            XCTAssertEqual(message.messageType, .file, "All results should be file messages")
        }
        
        print("Text messages: \(textResults.count), File messages: \(fileResults.count)")
    }
    
    /// 测试 5：时间范围筛选
    func testSearchByTimeRange() throws {
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // When: 搜索最近 5 秒内的消息
        let startTime = baseTime - 5000
        let endTime = baseTime
        
        let results = try messageManager.searchMessages(
            keyword: "重要",
            startTime: startTime,
            endTime: endTime
        )
        
        // Then: 所有结果的时间都应该在范围内
        for message in results {
            XCTAssertGreaterThanOrEqual(message.createTime, startTime, 
                                       "Message time should be >= startTime")
            XCTAssertLessThanOrEqual(message.createTime, endTime, 
                                    "Message time should be <= endTime")
        }
        
        print("Found \(results.count) messages in time range")
    }
    
    /// 测试 6：搜索消息数量
    func testSearchMessageCount() {
        // When: 获取搜索结果数量
        let count = messageManager.searchMessageCount(
            keyword: "重要"
        )
        
        // Then: 数量应该大于 0
        XCTAssertGreaterThan(count, 0, "Should have messages containing '重要'")
        
        // When: 获取会话内的搜索结果数量
        let conv1Count = messageManager.searchMessageCount(
            keyword: "重要",
            conversationID: conv1ID
        )
        
        let conv2Count = messageManager.searchMessageCount(
            keyword: "重要",
            conversationID: conv2ID
        )
        
        // Then: 总数应该等于各会话的数量之和
        XCTAssertEqual(count, conv1Count + conv2Count, 
                      "Total count should equal sum of conversation counts")
        
        print("Total: \(count), Conv1: \(conv1Count), Conv2: \(conv2Count)")
    }
    
    /// 测试 7：按发送者搜索
    func testSearchBySender() throws {
        // When: 搜索 user1 发送的消息
        let results = try messageManager.searchMessagesBySender(
            senderID: "user1"
        )
        
        // Then: 所有结果都应该是 user1 发送的
        XCTAssertGreaterThan(results.count, 0, "Should find messages from user1")
        
        for message in results {
            XCTAssertEqual(message.senderID, "user1", "All results should be from user1")
        }
        
        // When: 在会话 1 内搜索 user1 的消息
        let conv1Results = try messageManager.searchMessagesBySender(
            senderID: "user1",
            conversationID: conv1ID
        )
        
        // Then: 结果应该小于等于全局搜索
        XCTAssertLessThanOrEqual(conv1Results.count, results.count, 
                                "Conversation results should be <= global results")
        
        print("User1 messages: \(results.count), In conv1: \(conv1Results.count)")
    }
    
    // MARK: - 边界测试
    
    /// 测试 8：空关键词
    func testEmptyKeyword() throws {
        // When: 搜索空字符串
        let results = try messageManager.searchMessages(keyword: "")
        
        // Then: 应该返回空数组
        XCTAssertTrue(results.isEmpty, "Should return empty array for empty keyword")
    }
    
    /// 测试 9：空格关键词
    func testWhitespaceKeyword() throws {
        // When: 搜索只包含空格的字符串
        let results = try messageManager.searchMessages(keyword: "   ")
        
        // Then: 应该返回空数组
        XCTAssertTrue(results.isEmpty, "Should return empty array for whitespace keyword")
    }
    
    /// 测试 10：不存在的关键词
    func testNonExistentKeyword() throws {
        // When: 搜索不存在的关键词
        let results = try messageManager.searchMessages(keyword: "不存在的关键词XYZ123")
        
        // Then: 应该返回空数组
        XCTAssertTrue(results.isEmpty, "Should return empty array for non-existent keyword")
    }
    
    /// 测试 11：限制返回数量
    func testSearchLimit() throws {
        // When: 限制返回 3 条
        let results = try messageManager.searchMessages(
            keyword: "重要",
            limit: 3
        )
        
        // Then: 最多返回 3 条
        XCTAssertLessThanOrEqual(results.count, 3, "Should return at most 3 results")
    }
    
    /// 测试 12：特殊字符
    func testSpecialCharacters() throws {
        // Given: 插入包含特殊字符的消息
        let specialMessage = IMMessage()
        specialMessage.messageID = "special_msg"
        specialMessage.conversationID = conv1ID
        specialMessage.senderID = "user_test"
        specialMessage.content = "这是特殊字符：@#$%^&*()"
        specialMessage.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        try database.saveMessages([specialMessage])
        
        // When: 搜索特殊字符
        let results = try messageManager.searchMessages(keyword: "@#$")
        
        // Then: 应该能找到
        XCTAssertGreaterThan(results.count, 0, "Should find messages with special characters")
    }
    
    // MARK: - 组合条件测试
    
    /// 测试 13：组合条件搜索
    func testCombinedSearch() throws {
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        // When: 组合多个条件
        let results = try messageManager.searchMessages(
            keyword: "重要",
            conversationID: conv1ID,
            messageTypes: [.text],
            startTime: baseTime - 10000,
            endTime: baseTime,
            limit: 10
        )
        
        // Then: 所有结果都应该满足所有条件
        for message in results {
            XCTAssertEqual(message.conversationID, conv1ID, "Should be from conv1")
            XCTAssertEqual(message.messageType, .text, "Should be text message")
            XCTAssertTrue(message.content.contains("重要"), "Should contain keyword")
            XCTAssertGreaterThanOrEqual(message.createTime, baseTime - 10000)
            XCTAssertLessThanOrEqual(message.createTime, baseTime)
        }
        
        XCTAssertLessThanOrEqual(results.count, 10, "Should respect limit")
        
        print("Combined search found \(results.count) messages")
    }
    
    // MARK: - 性能测试
    
    /// 测试 14：大量数据搜索性能
    func testSearchPerformanceWithLargeDataset() throws {
        // Given: 插入大量消息（1000 条）
        var largeMessages: [IMMessage] = []
        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        for i in 0..<1000 {
            let message = IMMessage()
            message.messageID = "large_msg_\(i)"
            message.conversationID = "large_conv"
            message.senderID = "user_large"
            message.content = i % 10 == 0 ? "重要消息 \(i)" : "普通消息 \(i)"
            message.createTime = baseTime - Int64(i * 100)
            largeMessages.append(message)
        }
        
        try database.saveMessages(largeMessages)
        
        // When: 测试搜索性能
        let startTime = Date()
        
        let results = try messageManager.searchMessages(
            keyword: "重要",
            limit: 50
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: 应该很快（< 500ms）
        XCTAssertLessThan(duration, 0.5, "Search should complete in less than 500ms")
        XCTAssertGreaterThan(results.count, 0, "Should find messages")
        
        print("Search 1000+ messages: \(duration * 1000)ms, found: \(results.count)")
    }
    
    /// 测试 15：多次搜索性能
    func testMultipleSearchPerformance() throws {
        let keywords = ["重要", "会议", "文件", "通知", "项目"]
        
        let startTime = Date()
        
        for keyword in keywords {
            _ = try messageManager.searchMessages(keyword: keyword)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: 5 次搜索应该很快（< 1s）
        XCTAssertLessThan(duration, 1.0, "5 searches should complete in less than 1s")
        
        print("5 searches completed in: \(duration * 1000)ms")
    }
    
    // MARK: - 结果验证测试
    
    /// 测试 16：结果按时间倒序
    func testResultsOrderedByTime() throws {
        // When: 搜索消息
        let results = try messageManager.searchMessages(keyword: "重要")
        
        // Then: 结果应该按时间倒序（最新的在前）
        for i in 0..<results.count-1 {
            XCTAssertGreaterThanOrEqual(results[i].createTime, results[i+1].createTime,
                                       "Results should be ordered by time descending")
        }
    }
    
    /// 测试 17：搜索结果一致性
    func testSearchResultConsistency() throws {
        // When: 多次搜索同一关键词
        let results1 = try messageManager.searchMessages(keyword: "重要")
        let results2 = try messageManager.searchMessages(keyword: "重要")
        
        // Then: 结果应该一致
        XCTAssertEqual(results1.count, results2.count, "Multiple searches should return same count")
        
        for i in 0..<results1.count {
            XCTAssertEqual(results1[i].messageID, results2[i].messageID,
                          "Multiple searches should return same messages in same order")
        }
    }
}


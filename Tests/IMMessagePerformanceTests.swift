/// IMMessagePerformanceTests - 消息性能测试
/// 测试消息发送和接收的端到端延迟

import XCTest
@testable import IMSDK

final class IMMessagePerformanceTests: XCTestCase {
    
    var messageManager: IMMessageManager!
    var database: IMDatabaseManager!
    var protocolHandler: IMProtocolHandler!
    var batchWriter: IMMessageBatchWriter!
    
    override func setUp() {
        super.setUp()
        
        // 创建测试数据库
        database = IMDatabaseManager(userID: "test_user_perf")
        try? database.clearAll()
        
        // 创建协议处理器
        protocolHandler = IMProtocolHandler()
        
        // 创建消息管理器
        messageManager = IMMessageManager(
            database: database,
            protocolHandler: protocolHandler,
            websocket: nil
        )
        
        // 创建批量写入器
        batchWriter = IMMessageBatchWriter(database: database, batchSize: 50, maxWaitTime: 0.1)
    }
    
    override func tearDown() {
        try? database.clearAll()
        super.tearDown()
    }
    
    // MARK: - 发送性能测试
    
    /// 测试：传统发送方式的性能
    func testSendMessageTraditionalPerformance() throws {
        let message = createTestMessage()
        
        measure {
            _ = try? messageManager.sendMessage(message)
        }
        
        // 预期：~30ms（包含同步数据库写入）
        // Baseline: 记录此值作为对比
    }
    
    /// 测试：优化后发送方式的性能
    func testSendMessageFastPerformance() {
        let message = createTestMessage()
        
        measure {
            _ = messageManager.sendMessageFast(message)
        }
        
        // 预期：~3-5ms（异步数据库写入）
        // 目标：比传统方式快 80%+
    }
    
    /// 测试：发送性能对比
    func testSendPerformanceComparison() throws {
        let iterations = 100
        
        // 1. 测试传统方式
        var traditionalTimes: [TimeInterval] = []
        for _ in 0..<iterations {
            let message = createTestMessage()
            let start = Date()
            _ = try? messageManager.sendMessage(message)
            let elapsed = Date().timeIntervalSince(start) * 1000
            traditionalTimes.append(elapsed)
        }
        
        // 2. 测试优化方式
        var fastTimes: [TimeInterval] = []
        for _ in 0..<iterations {
            let message = createTestMessage()
            let start = Date()
            _ = messageManager.sendMessageFast(message)
            let elapsed = Date().timeIntervalSince(start) * 1000
            fastTimes.append(elapsed)
        }
        
        // 等待异步操作完成
        Thread.sleep(forTimeInterval: 2.0)
        
        // 3. 统计结果
        let traditionalAvg = traditionalTimes.reduce(0, +) / Double(traditionalTimes.count)
        let fastAvg = fastTimes.reduce(0, +) / Double(fastTimes.count)
        let improvement = ((traditionalAvg - fastAvg) / traditionalAvg) * 100
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 发送性能对比（\(iterations) 次迭代）
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            传统方式：\(String(format: "%.2f", traditionalAvg))ms
            优化方式：\(String(format: "%.2f", fastAvg))ms
            性能提升：\(String(format: "%.1f", improvement))%
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：优化方式应该明显更快
        XCTAssertLessThan(fastAvg, traditionalAvg * 0.3, "优化方式应该快至少 70%")
    }
    
    // MARK: - 接收性能测试
    
    /// 测试：消息接收的性能
    func testReceiveMessagePerformance() {
        let message = createTestMessage()
        message.direction = .receive
        
        measure {
            messageManager.handleReceivedMessageFast(message)
        }
        
        // 预期：~4-6ms（异步数据库写入）
    }
    
    // MARK: - 批量写入性能测试
    
    /// 测试：单条写入 vs 批量写入
    func testBatchWritePerformance() throws {
        let messageCount = 100
        let messages = (0..<messageCount).map { _ in createTestMessage() }
        
        // 1. 测试单条写入
        let singleWriteStart = Date()
        for message in messages {
            _ = try? database.saveMessage(message)
        }
        let singleWriteElapsed = Date().timeIntervalSince(singleWriteStart) * 1000
        let singleAvg = singleWriteElapsed / Double(messageCount)
        
        // 2. 测试批量写入
        let batchWriteStart = Date()
        let stats = try database.saveMessages(messages)
        let batchWriteElapsed = Date().timeIntervalSince(batchWriteStart) * 1000
        let batchAvg = batchWriteElapsed / Double(messageCount)
        
        let improvement = ((singleAvg - batchAvg) / singleAvg) * 100
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 批量写入性能对比（\(messageCount) 条消息）
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            单条写入：
              - 总耗时：\(String(format: "%.2f", singleWriteElapsed))ms
              - 平均：\(String(format: "%.2f", singleAvg))ms/条
            
            批量写入：
              - 总耗时：\(String(format: "%.2f", batchWriteElapsed))ms
              - 平均：\(String(format: "%.2f", batchAvg))ms/条
              - 统计：\(stats.description)
            
            性能提升：\(String(format: "%.1f", improvement))%
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：批量写入应该明显更快
        XCTAssertLessThan(batchAvg, singleAvg * 0.2, "批量写入应该快至少 80%")
    }
    
    /// 测试：批量写入器的性能
    func testBatchWriterPerformance() throws {
        let messageCount = 200
        let messages = (0..<messageCount).map { _ in createTestMessage() }
        
        let startTime = Date()
        
        // 添加消息到批量写入器
        for message in messages {
            batchWriter.addMessage(message)
        }
        
        // 强制刷新
        batchWriter.flush()
        
        // 等待异步写入完成
        Thread.sleep(forTimeInterval: 1.0)
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let avg = elapsed / Double(messageCount)
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 批量写入器性能（\(messageCount) 条消息）
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            总耗时：\(String(format: "%.2f", elapsed))ms
            平均：\(String(format: "%.2f", avg))ms/条
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：批量写入器应该高效
        XCTAssertLessThan(avg, 3.0, "批量写入器平均耗时应该小于 3ms/条")
    }
    
    // MARK: - 端到端延迟模拟测试
    
    /// 测试：模拟端到端延迟
    func testEndToEndLatencySimulation() {
        let message = createTestMessage()
        
        // 1. 发送端
        let sendStart = Date()
        _ = messageManager.sendMessageFast(message)
        let sendElapsed = Date().timeIntervalSince(sendStart) * 1000
        
        // 2. 模拟网络延迟（40ms 上行 + 5ms 服务器 + 40ms 下行）
        let networkLatency: TimeInterval = 85
        
        // 3. 接收端
        let receiveStart = Date()
        messageManager.handleReceivedMessageFast(message)
        let receiveElapsed = Date().timeIntervalSince(receiveStart) * 1000
        
        // 4. 总延迟
        let totalLatency = sendElapsed + networkLatency + receiveElapsed
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 端到端延迟模拟
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            发送端：\(String(format: "%.2f", sendElapsed))ms
            网络：\(String(format: "%.2f", networkLatency))ms
            接收端：\(String(format: "%.2f", receiveElapsed))ms
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            总延迟：\(String(format: "%.2f", totalLatency))ms
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：总延迟应该小于 100ms
        XCTAssertLessThan(totalLatency, 100, "端到端延迟应该小于 100ms")
    }
    
    // MARK: - 压力测试
    
    /// 测试：高并发发送
    func testHighConcurrencySend() {
        let concurrency = 10
        let messagesPerThread = 50
        let expectation = self.expectation(description: "high_concurrency_send")
        expectation.expectedFulfillmentCount = concurrency
        
        let startTime = Date()
        
        for _ in 0..<concurrency {
            DispatchQueue.global().async {
                for _ in 0..<messagesPerThread {
                    let message = self.createTestMessage()
                    _ = self.messageManager.sendMessageFast(message)
                }
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10)
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let totalMessages = concurrency * messagesPerThread
        let avg = elapsed / Double(totalMessages)
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 高并发发送测试
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            并发数：\(concurrency)
            总消息：\(totalMessages)
            总耗时：\(String(format: "%.2f", elapsed))ms
            平均：\(String(format: "%.2f", avg))ms/条
            吞吐量：\(String(format: "%.0f", Double(totalMessages) / elapsed * 1000)) 条/秒
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：高并发下仍然保持高性能
        XCTAssertLessThan(avg, 10.0, "高并发下平均耗时应该小于 10ms/条")
    }
    
    /// 测试：高并发接收
    func testHighConcurrencyReceive() {
        let concurrency = 10
        let messagesPerThread = 50
        let expectation = self.expectation(description: "high_concurrency_receive")
        expectation.expectedFulfillmentCount = concurrency
        
        let startTime = Date()
        
        for _ in 0..<concurrency {
            DispatchQueue.global().async {
                for _ in 0..<messagesPerThread {
                    let message = self.createTestMessage()
                    message.direction = .receive
                    self.messageManager.handleReceivedMessageFast(message)
                }
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10)
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let totalMessages = concurrency * messagesPerThread
        let avg = elapsed / Double(totalMessages)
        
        print("""
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊 高并发接收测试
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            并发数：\(concurrency)
            总消息：\(totalMessages)
            总耗时：\(String(format: "%.2f", elapsed))ms
            平均：\(String(format: "%.2f", avg))ms/条
            吞吐量：\(String(format: "%.0f", Double(totalMessages) / elapsed * 1000)) 条/秒
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            """)
        
        // 断言：高并发下仍然保持高性能
        XCTAssertLessThan(avg, 10.0, "高并发下平均耗时应该小于 10ms/条")
    }
    
    // MARK: - 数据一致性测试
    
    /// 测试：一致性保障器
    func testConsistencyGuard() throws {
        let guard_ = IMConsistencyGuard.shared
        guard_.setDatabase(database)
        
        // 1. 标记待写入消息
        let messages = (0..<10).map { _ in createTestMessage() }
        for message in messages {
            guard_.markPending(message)
        }
        
        XCTAssertEqual(guard_.getPendingCount(), 10, "应该有 10 条待写入消息")
        
        // 2. 强制刷新
        guard_.ensureAllWritten()
        
        // 3. 验证已清空
        XCTAssertEqual(guard_.getPendingCount(), 0, "所有消息应该已写入")
        
        // 4. 验证数据库中有这些消息
        for message in messages {
            let saved = database.findByPrimaryKey(IMMessage.self, primaryKey: message.messageID)
            XCTAssertNotNil(saved, "消息应该已保存到数据库")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestMessage() -> IMMessage {
        let message = IMMessage()
        message.messageID = UUID().uuidString
        message.conversationID = "test_conversation"
        message.senderID = "test_sender"
        message.receiverID = "test_receiver"
        message.messageType = .text
        message.content = "Test message content"
        message.status = .sending
        message.direction = .send
        message.sendTime = Int64(Date().timeIntervalSince1970 * 1000)
        return message
    }
}


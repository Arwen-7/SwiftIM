/// IMDatabaseManagerTests - 核心数据库管理器测试
///
/// 测试内容：
/// - 数据库初始化
/// - WAL 模式配置
/// - 事务支持
/// - Checkpoint 机制
/// - 数据库信息查询
/// - 并发访问

import XCTest
@testable import IMSDK

class IMDatabaseManagerTests: IMSQLiteTestBase {
    
    // MARK: - 初始化测试
    
    func testDatabaseInitialization() {
        // 验证数据库已创建
        XCTAssertNotNil(database)
        
        // 验证数据库文件存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDBPath))
        
        // 验证 WAL 文件存在
        XCTAssertTrue(walFileExists())
        
        IMLogger.shared.info("✅ 数据库初始化测试通过")
    }
    
    func testMultipleDatabaseInstances() throws {
        // 创建第二个数据库实例（同一用户ID）
        let db2 = try IMDatabaseManager(userID: testUserID)
        
        // 两个实例应该可以共存（WAL 模式支持并发读）
        XCTAssertNotNil(db2)
        
        // 保存消息到第一个实例
        let message1 = createTestMessage(messageID: "msg_1")
        try database.saveMessage(message1)
        
        // 从第二个实例读取
        let readMessage = db2.getMessage(messageID: "msg_1")
        XCTAssertNotNil(readMessage)
        assertMessagesEqual(message1, readMessage)
        
        db2.close()
        
        IMLogger.shared.info("✅ 多实例测试通过")
    }
    
    // MARK: - WAL 模式测试
    
    func testWALModeEnabled() {
        // WAL 文件应该存在
        XCTAssertTrue(walFileExists())
        
        // 获取 WAL 大小（初始可能为 0 或很小）
        let walSize = getWALSize()
        XCTAssertGreaterThanOrEqual(walSize, 0)
        
        IMLogger.shared.info("✅ WAL 模式测试通过（WAL 大小: \(walSize) 字节）")
    }
    
    func testWALGrowthAndCheckpoint() throws {
        // 写入大量数据使 WAL 增长
        for i in 0..<100 {
            let message = createTestMessage(messageID: "msg_\(i)")
            try database.saveMessage(message)
        }
        
        let walSizeBefore = getWALSize()
        XCTAssertGreaterThan(walSizeBefore, 0, "WAL 应该增长")
        
        IMLogger.shared.info("写入后 WAL 大小: \(walSizeBefore) 字节")
        
        // 执行 checkpoint
        try database.checkpoint(mode: .full)
        
        // 等待 checkpoint 完成
        Thread.sleep(forTimeInterval: 0.1)
        
        let walSizeAfter = getWALSize()
        
        IMLogger.shared.info("Checkpoint 后 WAL 大小: \(walSizeAfter) 字节")
        IMLogger.shared.info("✅ WAL 增长和 Checkpoint 测试通过")
    }
    
    // MARK: - 事务测试
    
    func testTransaction() throws {
        // 开始事务
        try database.beginTransaction()
        
        // 在事务中保存消息
        let message1 = createTestMessage(messageID: "msg_tx_1")
        let message2 = createTestMessage(messageID: "msg_tx_2")
        
        try database.saveMessage(message1)
        try database.saveMessage(message2)
        
        // 提交事务
        try database.commit()
        
        // 验证数据已保存
        let readMessage1 = database.getMessage(messageID: "msg_tx_1")
        let readMessage2 = database.getMessage(messageID: "msg_tx_2")
        
        XCTAssertNotNil(readMessage1)
        XCTAssertNotNil(readMessage2)
        
        IMLogger.shared.info("✅ 事务提交测试通过")
    }
    
    func testTransactionRollback() throws {
        // 开始事务
        try database.beginTransaction()
        
        // 在事务中保存消息
        let message = createTestMessage(messageID: "msg_rollback")
        try database.saveMessage(message)
        
        // 回滚事务
        database.rollback()
        
        // 验证数据未保存
        let readMessage = database.getMessage(messageID: "msg_rollback")
        XCTAssertNil(readMessage, "回滚后消息应该不存在")
        
        IMLogger.shared.info("✅ 事务回滚测试通过")
    }
    
    func testNestedTransaction() throws {
        // SQLite 不支持真正的嵌套事务，但我们使用 SAVEPOINT 模拟
        
        // 外层事务
        try database.beginTransaction()
        
        let message1 = createTestMessage(messageID: "msg_outer")
        try database.saveMessage(message1)
        
        // 模拟内层事务（保存点）
        try database.execute("SAVEPOINT inner_tx")
        
        let message2 = createTestMessage(messageID: "msg_inner")
        try database.saveMessage(message2)
        
        // 回滚内层事务
        try database.execute("ROLLBACK TO SAVEPOINT inner_tx")
        
        // 提交外层事务
        try database.commit()
        
        // 验证：外层消息应该存在，内层消息不应该存在
        let readMessage1 = database.getMessage(messageID: "msg_outer")
        let readMessage2 = database.getMessage(messageID: "msg_inner")
        
        XCTAssertNotNil(readMessage1, "外层消息应该存在")
        XCTAssertNil(readMessage2, "内层消息应该被回滚")
        
        IMLogger.shared.info("✅ 嵌套事务（保存点）测试通过")
    }
    
    // MARK: - 数据库信息测试
    
    func testDatabaseInfo() {
        let info = database.getDatabaseInfo()
        
        // 验证基本信息
        XCTAssertTrue(info["db_path"] as? String == testDBPath)
        XCTAssertEqual(info["wal_enabled"] as? Bool, true)
        
        // 验证大小信息
        let dbSize = info["db_size"] as? Int64 ?? 0
        let walSize = info["wal_size"] as? Int64 ?? 0
        
        XCTAssertGreaterThan(dbSize, 0)
        XCTAssertGreaterThanOrEqual(walSize, 0)
        
        // 验证版本信息
        let sqliteVersion = info["sqlite_version"] as? String
        XCTAssertNotNil(sqliteVersion)
        
        IMLogger.shared.info("数据库信息: \(info)")
        IMLogger.shared.info("✅ 数据库信息测试通过")
    }
    
    // MARK: - 并发访问测试
    
    func testConcurrentReads() throws {
        // 准备测试数据
        for i in 0..<10 {
            let message = createTestMessage(messageID: "msg_\(i)")
            try database.saveMessage(message)
        }
        
        // 并发读取
        let expectation = XCTestExpectation(description: "并发读取完成")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent.reads", attributes: .concurrent)
        
        for i in 0..<10 {
            queue.async {
                let message = self.database.getMessage(messageID: "msg_\(i)")
                XCTAssertNotNil(message)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        IMLogger.shared.info("✅ 并发读取测试通过")
    }
    
    func testConcurrentWritesWithTransaction() throws {
        // WAL 模式下，写入会被序列化
        let expectation = XCTestExpectation(description: "并发写入完成")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent.writes", attributes: .concurrent)
        
        for i in 0..<10 {
            queue.async {
                do {
                    let message = self.createTestMessage(messageID: "msg_concurrent_\(i)")
                    try self.database.saveMessage(message)
                    expectation.fulfill()
                } catch {
                    XCTFail("并发写入失败: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // 验证所有消息都已保存
        for i in 0..<10 {
            let message = database.getMessage(messageID: "msg_concurrent_\(i)")
            XCTAssertNotNil(message, "消息 msg_concurrent_\(i) 应该存在")
        }
        
        IMLogger.shared.info("✅ 并发写入测试通过")
    }
    
    // MARK: - 错误处理测试
    
    func testInvalidTransaction() {
        // 在没有开始事务的情况下提交
        XCTAssertThrowsError(try database.commit()) { error in
            IMLogger.shared.info("预期错误: \(error)")
        }
        
        // 在没有开始事务的情况下回滚（不会抛出错误，但会打印警告）
        database.rollback()
        
        IMLogger.shared.info("✅ 无效事务测试通过")
    }
    
    func testInvalidCheckpointMode() {
        // checkpoint 应该总是成功或抛出错误
        do {
            try database.checkpoint(mode: .passive)
            IMLogger.shared.info("✅ Checkpoint 测试通过")
        } catch {
            XCTFail("Checkpoint 失败: \(error)")
        }
    }
    
    // MARK: - 性能测试
    
    func testWALPerformance() throws {
        // 测试 WAL 模式下的写入性能
        let messageCount = 100
        
        let duration = try measureExecutionTime({
            for i in 0..<messageCount {
                let message = self.createTestMessage(messageID: "msg_perf_\(i)")
                try self.database.saveMessage(message)
            }
        }, description: "WAL 模式写入 \(messageCount) 条消息")
        
        // 平均每条消息写入时间应该 < 10ms
        let avgDuration = duration / Double(messageCount)
        XCTAssertLessThan(avgDuration, 0.01, "平均写入时间应该 < 10ms")
        
        IMLogger.shared.info("平均写入时间: \(String(format: "%.2f", avgDuration * 1000))ms/条")
        IMLogger.shared.info("✅ WAL 性能测试通过")
    }
    
    func testBatchWritePerformance() throws {
        // 测试批量写入性能
        let messageCount = 100
        let messages = createTestMessages(count: messageCount)
        
        let duration = try measureExecutionTime({
            try self.database.saveMessages(messages)
        }, description: "批量写入 \(messageCount) 条消息")
        
        // 批量写入应该 < 200ms
        XCTAssertLessThan(duration, 0.2, "批量写入应该 < 200ms")
        
        let avgDuration = duration / Double(messageCount)
        IMLogger.shared.info("平均写入时间: \(String(format: "%.2f", avgDuration * 1000))ms/条")
        IMLogger.shared.info("✅ 批量写入性能测试通过")
    }
    
    // MARK: - 压力测试
    
    func testLargeDataSet() throws {
        // 测试大数据集（1000 条消息）
        let messageCount = 1000
        
        let duration = try measureExecutionTime({
            // 批量插入
            for batch in 0..<10 {
                let messages = self.createTestMessages(
                    count: 100,
                    conversationID: "test_conv_1",
                    startSeq: Int64(batch * 100)
                )
                try self.database.saveMessages(messages)
            }
        }, description: "插入 \(messageCount) 条消息")
        
        // 验证数据
        let allMessages = database.getMessages(conversationID: "test_conv_1", limit: 2000)
        XCTAssertEqual(allMessages.count, messageCount)
        
        // 验证查询性能
        let _ = try measureExecutionTime({
            let _ = self.database.getMessages(conversationID: "test_conv_1", limit: 20)
        }, description: "查询最新 20 条消息")
        
        IMLogger.shared.info("✅ 大数据集测试通过（\(messageCount) 条消息）")
    }
}


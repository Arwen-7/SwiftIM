/// IMMessageSyncManagerTests - 消息增量同步测试
/// 测试消息同步的各种场景

import XCTest
@testable import IMSDK

final class IMMessageSyncManagerTests: XCTestCase {
    
    var database: IMDatabaseManager!
    var httpManager: IMHTTPManager!
    var messageManager: IMMessageManager!
    var syncManager: IMMessageSyncManager!
    
    let testUserID = "test_user_123"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 初始化测试组件
        database = IMDatabaseManager.shared
        try database.initialize(
            config: IMDatabaseConfig(
                fileName: "test_im_sync.realm",
                enableEncryption: false
            ),
            userID: testUserID
        )
        
        httpManager = IMHTTPManager(
            baseURL: "https://api.test.com",
            timeout: 30
        )
        
        let protocolHandler = IMProtocolHandler()
        messageManager = IMMessageManager(
            database: database,
            protocolHandler: protocolHandler,
            websocket: nil
        )
        
        syncManager = IMMessageSyncManager(
            database: database,
            httpManager: httpManager,
            messageManager: messageManager,
            userID: testUserID
        )
    }
    
    override func tearDownWithError() throws {
        // 清理测试数据
        try database.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：首次同步
    func testFirstSync() {
        let expectation = self.expectation(description: "First sync")
        
        // Given: lastSyncSeq = 0（首次同步）
        let config = database.getSyncConfig(userID: testUserID)
        XCTAssertEqual(config.lastSyncSeq, 0, "Initial lastSyncSeq should be 0")
        
        // When: 开始同步
        syncManager.startSync { result in
            // Then: 同步完成
            switch result {
            case .success:
                XCTAssertTrue(true, "Sync should succeed")
            case .failure(let error):
                XCTFail("Sync failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30)
    }
    
    /// 测试 2：增量同步
    func testIncrementalSync() {
        let expectation = self.expectation(description: "Incremental sync")
        
        // Given: lastSyncSeq = 1000（已有历史消息）
        try? database.updateLastSyncSeq(userID: testUserID, seq: 1000)
        
        // When: 开始同步
        syncManager.startSync { result in
            // Then: 应该只拉取 seq > 1000 的消息
            switch result {
            case .success:
                let config = self.database.getSyncConfig(userID: self.testUserID)
                XCTAssertGreaterThan(config.lastSyncSeq, 1000, "lastSyncSeq should be updated")
            case .failure(let error):
                XCTFail("Sync failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30)
    }
    
    /// 测试 3：分批拉取
    func testBatchSync() {
        let expectation = self.expectation(description: "Batch sync")
        
        var progressUpdates: [IMSyncProgress] = []
        
        // 监听进度
        syncManager.onProgress = { progress in
            progressUpdates.append(progress)
            print("Progress: \(Int(progress.progress * 100))% - Batch \(progress.currentBatch)")
        }
        
        // When: 同步大量消息
        syncManager.startSync { result in
            // Then: 应该有多次进度更新
            XCTAssertGreaterThan(progressUpdates.count, 0, "Should have progress updates")
            
            // 最后一次进度应该是 100%
            if let lastProgress = progressUpdates.last {
                XCTAssertGreaterThanOrEqual(lastProgress.progress, 1.0, "Final progress should be 100%")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 60)
    }
    
    /// 测试 4：消息去重
    func testMessageDeduplication() throws {
        // Given: 创建测试消息
        let message = IMMessage()
        message.messageID = "msg_test_001"
        message.conversationID = "conv_123"
        message.senderID = "user_456"
        message.content = "Hello"
        message.seq = 100
        message.createTime = IMUtils.currentTimeMillis()
        
        // When: 保存两次相同的消息
        try database.saveMessages([message])
        try database.saveMessages([message])
        
        // Then: 数据库中应该只有一条消息
        let messages = try database.getMessages(conversationID: "conv_123")
        XCTAssertEqual(messages.count, 1, "Should have only one message after deduplication")
    }
    
    /// 测试 5：并发同步控制
    func testConcurrentSyncControl() {
        let expectation = self.expectation(description: "Concurrent sync")
        expectation.expectedFulfillmentCount = 3
        
        var completionCount = 0
        let completionLock = NSLock()
        
        // When: 同时调用 startSync 3 次
        for i in 1...3 {
            syncManager.startSync { result in
                completionLock.lock()
                completionCount += 1
                print("Sync \(i) completed")
                completionLock.unlock()
                
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 60)
        
        // Then: 应该都完成了（第一个真正执行，后续的直接返回）
        XCTAssertEqual(completionCount, 3, "All sync calls should complete")
    }
    
    // MARK: - 状态管理测试
    
    /// 测试 6：同步状态变化
    func testSyncStateChanges() {
        let expectation = self.expectation(description: "Sync state")
        
        var stateChanges: [IMSyncState] = []
        
        // 监听状态变化
        syncManager.onStateChanged = { state in
            stateChanges.append(state)
            print("State changed: \(state)")
        }
        
        // When: 开始同步
        syncManager.startSync { _ in
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30)
        
        // Then: 应该经历状态变化
        XCTAssertGreaterThan(stateChanges.count, 0, "Should have state changes")
        
        // 最后状态应该是 completed 或 failed
        if let lastState = stateChanges.last {
            switch lastState {
            case .completed, .failed:
                XCTAssertTrue(true, "Final state should be completed or failed")
            default:
                XCTFail("Final state should be completed or failed")
            }
        }
    }
    
    /// 测试 7：停止同步
    func testStopSync() {
        // When: 开始同步
        syncManager.startSync()
        
        // 等待一小段时间
        Thread.sleep(forTimeInterval: 0.5)
        
        // Then: 停止同步
        syncManager.stopSync()
        
        let state = syncManager.getSyncState()
        
        // 状态应该变为 idle
        if case .idle = state {
            XCTAssertTrue(true, "State should be idle after stop")
        } else {
            XCTFail("State should be idle after stop")
        }
    }
    
    /// 测试 8：重置同步
    func testResetSync() throws {
        let expectation = self.expectation(description: "Reset sync")
        
        // Given: 设置 lastSyncSeq
        try database.updateLastSyncSeq(userID: testUserID, seq: 5000)
        
        var config = database.getSyncConfig(userID: testUserID)
        XCTAssertEqual(config.lastSyncSeq, 5000, "lastSyncSeq should be 5000")
        
        // When: 重置同步
        syncManager.resetSync { result in
            // Then: lastSyncSeq 应该重置为 0
            let newConfig = self.database.getSyncConfig(userID: self.testUserID)
            XCTAssertEqual(newConfig.lastSyncSeq, 0, "lastSyncSeq should be reset to 0")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30)
    }
    
    // MARK: - 性能测试
    
    /// 测试 9：大量消息同步性能
    func testLargeMessageSyncPerformance() {
        let expectation = self.expectation(description: "Large message sync")
        
        let startTime = Date()
        
        // When: 同步大量消息
        syncManager.startSync { result in
            let duration = Date().timeIntervalSince(startTime)
            
            print("Sync duration: \(duration) seconds")
            
            // Then: 应该在合理时间内完成（< 60 秒）
            XCTAssertLessThan(duration, 60.0, "Sync should complete within 60 seconds")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 90)
    }
    
    /// 测试 10：批量插入性能
    func testBatchInsertPerformance() throws {
        // Given: 创建 1000 条测试消息
        var messages: [IMMessage] = []
        for i in 0..<1000 {
            let message = IMMessage()
            message.messageID = "msg_\(i)"
            message.conversationID = "conv_test"
            message.senderID = "user_test"
            message.content = "Test message \(i)"
            message.seq = Int64(i)
            message.createTime = IMUtils.currentTimeMillis()
            messages.append(message)
        }
        
        let startTime = Date()
        
        // When: 批量保存
        try database.saveMessages(messages)
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("Batch insert duration: \(duration) seconds")
        
        // Then: 应该很快（< 1 秒）
        XCTAssertLessThan(duration, 1.0, "Batch insert should be fast (< 1s)")
        
        // 验证数量
        let saved = try database.getMessages(conversationID: "conv_test")
        XCTAssertEqual(saved.count, 1000, "Should have 1000 messages")
    }
    
    // MARK: - 数据库方法测试
    
    /// 测试 11：获取最大 seq
    func testGetMaxSeq() throws {
        // Given: 插入一些消息
        let messages = [
            createTestMessage(seq: 100),
            createTestMessage(seq: 500),
            createTestMessage(seq: 300)
        ]
        try database.saveMessages(messages)
        
        // When: 获取最大 seq
        let maxSeq = database.getMaxSeq()
        
        // Then: 应该是 500
        XCTAssertEqual(maxSeq, 500, "Max seq should be 500")
    }
    
    /// 测试 12：更新同步配置
    func testUpdateSyncConfig() throws {
        // When: 更新 lastSyncSeq
        try database.updateLastSyncSeq(userID: testUserID, seq: 9999)
        
        // Then: 配置应该被更新
        let config = database.getSyncConfig(userID: testUserID)
        XCTAssertEqual(config.lastSyncSeq, 9999, "lastSyncSeq should be updated")
        XCTAssertGreaterThan(config.lastSyncTime, 0, "lastSyncTime should be updated")
    }
    
    // MARK: - Helper Methods
    
    private func createTestMessage(seq: Int64) -> IMMessage {
        let message = IMMessage()
        message.messageID = "msg_\(UUID().uuidString)"
        message.conversationID = "conv_test"
        message.senderID = "user_test"
        message.content = "Test message"
        message.seq = seq
        message.createTime = IMUtils.currentTimeMillis()
        return message
    }
}


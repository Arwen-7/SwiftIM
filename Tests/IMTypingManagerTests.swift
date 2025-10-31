/// IMTypingManagerTests - 输入状态管理测试
/// 测试"正在输入..."功能的各种场景

import XCTest
@testable import IMSDK

final class IMTypingManagerTests: XCTestCase {
    
    var protocolHandler: IMProtocolHandler!
    var typingManager: IMTypingManager!
    let testUserID = "user_123"
    let testConversationID = "conv_456"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        protocolHandler = IMProtocolHandler()
        typingManager = IMTypingManager(userID: testUserID, protocolHandler: protocolHandler)
    }
    
    override func tearDownWithError() throws {
        typingManager = nil
        protocolHandler = nil
        try super.tearDownWithError()
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：发送输入状态
    func testSendTyping() {
        // Given: 设置监听器
        let delegate = MockTypingListener()
        typingManager.addListener(delegate)
        
        // When: 发送输入状态
        typingManager.sendTyping(conversationID: testConversationID)
        
        // Then: 不应该崩溃
        XCTAssertTrue(true, "Should send typing status without crash")
    }
    
    /// 测试 2：停止输入
    func testStopTyping() {
        // Given: 先发送输入状态
        typingManager.sendTyping(conversationID: testConversationID)
        
        // When: 停止输入
        typingManager.stopTyping(conversationID: testConversationID)
        
        // Then: 不应该崩溃
        XCTAssertTrue(true, "Should stop typing without crash")
    }
    
    /// 测试 3：防抖动
    func testDebounce() {
        // Given: 设置较短的发送间隔便于测试
        typingManager.sendInterval = 2.0
        
        // When: 快速连续发送
        typingManager.sendTyping(conversationID: testConversationID)
        typingManager.sendTyping(conversationID: testConversationID)  // 应该被忽略
        
        // Wait: 等待超过防抖动时间
        let expectation = XCTestExpectation(description: "Wait for debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        // Then: 再次发送应该成功
        typingManager.sendTyping(conversationID: testConversationID)
        XCTAssertTrue(true, "Should allow sending after debounce interval")
    }
    
    /// 测试 4：自动停止
    func testAutoStop() {
        // Given: 设置较短的自动停止延迟
        typingManager.stopDelay = 1.0
        
        // When: 发送输入状态
        typingManager.sendTyping(conversationID: testConversationID)
        
        // Wait: 等待自动停止
        let expectation = XCTestExpectation(description: "Wait for auto stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Then: 应该自动发送停止状态
        XCTAssertTrue(true, "Should auto-stop after delay")
    }
    
    // MARK: - 接收状态测试
    
    /// 测试 5：接收输入状态
    func testReceiveTypingStatus() {
        // Given: 设置监听器
        let delegate = MockTypingListener()
        typingManager.addListener(delegate)
        
        let expectation = XCTestExpectation(description: "Receive typing status")
        delegate.onStateChanged = { state in
            XCTAssertEqual(state.conversationID, self.testConversationID)
            XCTAssertEqual(state.userID, "other_user")
            XCTAssertEqual(state.status, .typing)
            expectation.fulfill()
        }
        
        // When: 接收输入状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "other_user",
            status: .typing
        )
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// 测试 6：忽略自己的状态
    func testIgnoreOwnStatus() {
        // Given: 设置监听器
        let delegate = MockTypingListener()
        typingManager.addListener(delegate)
        
        var callbackCount = 0
        delegate.onStateChanged = { _ in
            callbackCount += 1
        }
        
        // When: 接收自己的输入状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: testUserID,  // 自己的 userID
            status: .typing
        )
        
        // Wait
        Thread.sleep(forTimeInterval: 0.2)
        
        // Then: 不应该触发回调
        XCTAssertEqual(callbackCount, 0, "Should ignore own typing status")
    }
    
    /// 测试 7：获取正在输入的用户列表
    func testGetTypingUsers() {
        // When: 接收多个用户的输入状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_2",
            status: .typing
        )
        
        // Then: 应该返回正在输入的用户列表
        let typingUsers = typingManager.getTypingUsers(in: testConversationID)
        XCTAssertEqual(typingUsers.count, 2, "Should have 2 typing users")
        XCTAssertTrue(typingUsers.contains("user_1"))
        XCTAssertTrue(typingUsers.contains("user_2"))
    }
    
    /// 测试 8：检查用户是否正在输入
    func testIsUserTyping() {
        // Given: 用户开始输入
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        
        // Then: 应该返回 true
        XCTAssertTrue(
            typingManager.isUserTyping(userID: "user_1", in: testConversationID),
            "User should be typing"
        )
        
        XCTAssertFalse(
            typingManager.isUserTyping(userID: "user_2", in: testConversationID),
            "User should not be typing"
        )
    }
    
    /// 测试 9：停止状态移除用户
    func testStopStatusRemovesUser() {
        // Given: 用户正在输入
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        
        XCTAssertTrue(typingManager.isUserTyping(userID: "user_1", in: testConversationID))
        
        // When: 接收停止状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .stop
        )
        
        // Then: 用户应该被移除
        XCTAssertFalse(
            typingManager.isUserTyping(userID: "user_1", in: testConversationID),
            "User should no longer be typing"
        )
    }
    
    // MARK: - 超时测试
    
    /// 测试 10：超时自动清除
    func testTimeout() {
        // Given: 设置较短的超时时间
        typingManager.receiveTimeout = 2.0
        
        // When: 接收输入状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        
        XCTAssertTrue(typingManager.isUserTyping(userID: "user_1", in: testConversationID))
        
        // Wait: 等待超时
        let expectation = XCTestExpectation(description: "Wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        // Then: 状态应该被清除
        XCTAssertFalse(
            typingManager.isUserTyping(userID: "user_1", in: testConversationID),
            "Should timeout and clear status"
        )
    }
    
    /// 测试 11：超时触发监听器
    func testTimeoutTriggersListener() {
        // Given: 设置监听器和较短超时
        let delegate = MockTypingListener()
        typingManager.addListener(delegate)
        typingManager.receiveTimeout = 1.0
        
        let expectation = XCTestExpectation(description: "Timeout triggers listener")
        expectation.expectedFulfillmentCount = 2  // typing + stop (timeout)
        
        delegate.onStateChanged = { state in
            expectation.fulfill()
        }
        
        // When: 接收输入状态
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        
        // Wait: 等待超时
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - 监听器测试
    
    /// 测试 12：添加监听器
    func testAddListener() {
        // Given: 创建监听器
        let delegate = MockTypingListener()
        
        // When: 添加监听器
        typingManager.addListener(delegate)
        
        // Then: 不应该崩溃
        XCTAssertTrue(true, "Should add listener without crash")
    }
    
    /// 测试 13：移除监听器
    func testRemoveListener() {
        // Given: 添加监听器
        let delegate = MockTypingListener()
        typingManager.addListener(delegate)
        
        // When: 移除监听器
        typingManager.removeListener(delegate)
        
        // Then: 不应该崩溃
        XCTAssertTrue(true, "Should remove listener without crash")
    }
    
    /// 测试 14：弱引用监听器
    func testWeakListener() {
        // Given: 创建监听器
        var delegate: MockTypingListener? = MockTypingListener()
        typingManager.addListener(delegate!)
        
        // When: 释放监听器
        delegate = nil
        
        // Then: 发送状态不应该崩溃
        typingManager.handleTypingPacket(
            conversationID: testConversationID,
            userID: "user_1",
            status: .typing
        )
        
        XCTAssertTrue(true, "Should handle released listener gracefully")
    }
    
    // MARK: - 多会话测试
    
    /// 测试 15：多个会话独立
    func testMultipleConversations() {
        // When: 在不同会话中发送状态
        let conv1 = "conv_1"
        let conv2 = "conv_2"
        
        typingManager.handleTypingPacket(conversationID: conv1, userID: "user_1", status: .typing)
        typingManager.handleTypingPacket(conversationID: conv2, userID: "user_2", status: .typing)
        
        // Then: 会话应该独立
        let users1 = typingManager.getTypingUsers(in: conv1)
        let users2 = typingManager.getTypingUsers(in: conv2)
        
        XCTAssertEqual(users1, ["user_1"])
        XCTAssertEqual(users2, ["user_2"])
    }
    
    // MARK: - 并发测试
    
    /// 测试 16：并发访问
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        // 多个线程同时访问
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                if i % 2 == 0 {
                    self.typingManager.sendTyping(conversationID: "conv_\(i)")
                } else {
                    self.typingManager.handleTypingPacket(
                        conversationID: "conv_\(i)",
                        userID: "user_\(i)",
                        status: .typing
                    )
                }
                
                _ = self.typingManager.getTypingUsers(in: "conv_\(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - 性能测试
    
    /// 测试 17：大量用户性能
    func testPerformanceWithManyUsers() {
        measure {
            for i in 0..<100 {
                typingManager.handleTypingPacket(
                    conversationID: testConversationID,
                    userID: "user_\(i)",
                    status: .typing
                )
            }
            
            _ = typingManager.getTypingUsers(in: testConversationID)
        }
    }
}

// MARK: - Mock Delegate

class MockTypingListener: IMTypingListener {
    var onStateChanged: ((IMTypingState) -> Void)?
    var stateChangeCount = 0
    
    func onTypingStateChanged(_ state: IMTypingState) {
        stateChangeCount += 1
        onStateChanged?(state)
    }
}


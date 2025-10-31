/// IMUnreadCountTests - 会话未读计数测试
/// 测试未读消息计数的各种场景

import XCTest
@testable import IMSDK

final class IMUnreadCountTests: XCTestCase {
    
    var database: IMDatabaseManager!
    var conversationManager: IMConversationManager!
    var messageManager: IMMessageManager!
    
    let testUserID = "user_123"
    let conv1ID = "conv_unread_1"
    let conv2ID = "conv_unread_2"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 初始化组件
        database = IMDatabaseManager.shared
        try database.initialize(
            config: IMDatabaseConfig(
                fileName: "test_im_unread.realm",
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
        
        conversationManager = IMConversationManager(
            database: database,
            messageManager: messageManager
        )
        
        // 关联管理器
        messageManager.conversationManager = conversationManager
        
        // 创建测试会话
        try createTestConversations()
    }
    
    override func tearDownWithError() throws {
        try database.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - 测试数据准备
    
    private func createTestConversations() throws {
        let conv1 = IMConversation()
        conv1.conversationID = conv1ID
        conv1.conversationType = .single
        conv1.showName = "会话1"
        conv1.unreadCount = 0
        
        let conv2 = IMConversation()
        conv2.conversationID = conv2ID
        conv2.conversationType = .single
        conv2.showName = "会话2"
        conv2.unreadCount = 0
        
        try database.saveConversation(conv1)
        try database.saveConversation(conv2)
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：增加未读数
    func testIncrementUnreadCount() throws {
        // When: 增加未读数
        try database.incrementUnreadCount(conversationID: conv1ID, by: 1)
        
        // Then: 未读数应该增加
        let unreadCount = database.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(unreadCount, 1, "Unread count should be 1")
        
        // When: 再次增加
        try database.incrementUnreadCount(conversationID: conv1ID, by: 3)
        
        // Then: 未读数应该累加
        let newCount = database.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(newCount, 4, "Unread count should be 4")
    }
    
    /// 测试 2：清空未读数
    func testClearUnreadCount() throws {
        // Given: 有未读消息
        try database.incrementUnreadCount(conversationID: conv1ID, by: 5)
        XCTAssertEqual(database.getUnreadCount(conversationID: conv1ID), 5)
        
        // When: 清空未读数
        try database.clearUnreadCount(conversationID: conv1ID)
        
        // Then: 未读数应该为 0
        let unreadCount = database.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(unreadCount, 0, "Unread count should be cleared to 0")
    }
    
    /// 测试 3：获取未读数
    func testGetUnreadCount() throws {
        // Given: 设置未读数
        try database.incrementUnreadCount(conversationID: conv1ID, by: 10)
        
        // When: 获取未读数
        let count = conversationManager.getUnreadCount(conversationID: conv1ID)
        
        // Then: 应该返回正确的数量
        XCTAssertEqual(count, 10, "Should return correct unread count")
    }
    
    /// 测试 4：标记为已读
    func testMarkAsRead() throws {
        // Given: 有未读消息
        try database.incrementUnreadCount(conversationID: conv1ID, by: 8)
        
        // When: 标记为已读
        try conversationManager.markAsRead(conversationID: conv1ID)
        
        // Then: 未读数应该清零
        let count = conversationManager.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(count, 0, "Unread count should be 0 after marking as read")
    }
    
    // MARK: - 总未读数测试
    
    /// 测试 5：获取总未读数
    func testGetTotalUnreadCount() throws {
        // Given: 两个会话都有未读消息
        try database.incrementUnreadCount(conversationID: conv1ID, by: 5)
        try database.incrementUnreadCount(conversationID: conv2ID, by: 3)
        
        // When: 获取总未读数
        let totalCount = conversationManager.getTotalUnreadCount()
        
        // Then: 应该是两个会话的总和
        XCTAssertEqual(totalCount, 8, "Total unread count should be 8")
    }
    
    /// 测试 6：免打扰不计入总未读数
    func testMutedConversationNotCountedInTotal() throws {
        // Given: 两个会话都有未读消息
        try database.incrementUnreadCount(conversationID: conv1ID, by: 5)
        try database.incrementUnreadCount(conversationID: conv2ID, by: 3)
        
        // When: 设置会话1为免打扰
        try conversationManager.setMuted(conversationID: conv1ID, muted: true)
        
        // Then: 总未读数应该只包含未免打扰的会话
        let totalCount = conversationManager.getTotalUnreadCount()
        XCTAssertEqual(totalCount, 3, "Total should not include muted conversation")
    }
    
    /// 测试 7：取消免打扰后重新计入
    func testUnmutedConversationCountedInTotal() throws {
        // Given: 会话免打扰且有未读
        try database.incrementUnreadCount(conversationID: conv1ID, by: 5)
        try conversationManager.setMuted(conversationID: conv1ID, muted: true)
        
        // When: 取消免打扰
        try conversationManager.setMuted(conversationID: conv1ID, muted: false)
        
        // Then: 应该重新计入总数
        let totalCount = conversationManager.getTotalUnreadCount()
        XCTAssertEqual(totalCount, 5, "Should count after unmuting")
    }
    
    // MARK: - 免打扰功能测试
    
    /// 测试 8：设置免打扰
    func testSetMuted() throws {
        // When: 设置免打扰
        try conversationManager.setMuted(conversationID: conv1ID, muted: true)
        
        // Then: 会话应该被设置为免打扰
        if let conversation = conversationManager.getConversation(conversationID: conv1ID) {
            XCTAssertTrue(conversation.isMuted, "Conversation should be muted")
        } else {
            XCTFail("Conversation not found")
        }
    }
    
    /// 测试 9：取消免打扰
    func testUnsetMuted() throws {
        // Given: 会话已免打扰
        try conversationManager.setMuted(conversationID: conv1ID, muted: true)
        
        // When: 取消免打扰
        try conversationManager.setMuted(conversationID: conv1ID, muted: false)
        
        // Then: 会话应该不再免打扰
        if let conversation = conversationManager.getConversation(conversationID: conv1ID) {
            XCTAssertFalse(conversation.isMuted, "Conversation should not be muted")
        } else {
            XCTFail("Conversation not found")
        }
    }
    
    // MARK: - 当前会话测试
    
    /// 测试 10：设置当前会话
    func testSetCurrentConversation() {
        // When: 设置当前会话
        messageManager.setCurrentConversation(conv1ID)
        
        // Then: 应该能获取当前会话
        let currentConvID = messageManager.getCurrentConversation()
        XCTAssertEqual(currentConvID, conv1ID, "Should set current conversation")
    }
    
    /// 测试 11：清除当前会话
    func testClearCurrentConversation() {
        // Given: 已设置当前会话
        messageManager.setCurrentConversation(conv1ID)
        
        // When: 清除当前会话
        messageManager.setCurrentConversation(nil)
        
        // Then: 当前会话应该为 nil
        let currentConvID = messageManager.getCurrentConversation()
        XCTAssertNil(currentConvID, "Current conversation should be nil")
    }
    
    /// 测试 12：当前会话的消息不增加未读数
    func testCurrentConversationMessageNotIncreaseUnread() throws {
        // Given: 设置当前会话
        messageManager.setCurrentConversation(conv1ID)
        
        let initialCount = conversationManager.getUnreadCount(conversationID: conv1ID)
        
        // When: 收到当前会话的消息
        let message = IMMessage()
        message.messageID = "msg_test_1"
        message.conversationID = conv1ID
        message.direction = .receive  // 接收的消息
        message.content = "Test message"
        message.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        messageManager.handleReceivedMessage(message)
        
        // Then: 未读数不应该增加
        let newCount = conversationManager.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(newCount, initialCount, "Unread count should not increase for current conversation")
    }
    
    /// 测试 13：非当前会话的消息增加未读数
    func testOtherConversationMessageIncreaseUnread() throws {
        // Given: 设置当前会话为 conv1
        messageManager.setCurrentConversation(conv1ID)
        
        let initialCount = conversationManager.getUnreadCount(conversationID: conv2ID)
        
        // When: 收到 conv2 的消息
        let message = IMMessage()
        message.messageID = "msg_test_2"
        message.conversationID = conv2ID
        message.direction = .receive
        message.content = "Test message"
        message.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        messageManager.handleReceivedMessage(message)
        
        // Then: conv2 的未读数应该增加
        let newCount = conversationManager.getUnreadCount(conversationID: conv2ID)
        XCTAssertEqual(newCount, initialCount + 1, "Unread count should increase for other conversation")
    }
    
    /// 测试 14：发送的消息不增加未读数
    func testSentMessageNotIncreaseUnread() throws {
        let initialCount = conversationManager.getUnreadCount(conversationID: conv1ID)
        
        // When: 发送消息（direction = .send）
        let message = IMMessage()
        message.messageID = "msg_test_3"
        message.conversationID = conv1ID
        message.direction = .send  // 发送的消息
        message.content = "Sent message"
        message.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        
        messageManager.handleReceivedMessage(message)
        
        // Then: 未读数不应该增加
        let newCount = conversationManager.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(newCount, initialCount, "Unread count should not increase for sent message")
    }
    
    // MARK: - 批量更新测试
    
    /// 测试 15：批量更新未读数
    func testBatchUpdateUnreadCount() throws {
        // When: 批量更新
        let changes: [String: Int] = [
            conv1ID: 5,
            conv2ID: 3
        ]
        
        try database.batchUpdateUnreadCount(changes)
        
        // Then: 所有会话的未读数都应该更新
        XCTAssertEqual(database.getUnreadCount(conversationID: conv1ID), 5)
        XCTAssertEqual(database.getUnreadCount(conversationID: conv2ID), 3)
    }
    
    // MARK: - 边界测试
    
    /// 测试 16：不存在的会话
    func testNonExistentConversation() {
        // When: 获取不存在会话的未读数
        let count = conversationManager.getUnreadCount(conversationID: "non_existent")
        
        // Then: 应该返回 0
        XCTAssertEqual(count, 0, "Should return 0 for non-existent conversation")
    }
    
    /// 测试 17：多次清空未读数
    func testMultipleClear() throws {
        // Given: 有未读消息
        try database.incrementUnreadCount(conversationID: conv1ID, by: 5)
        
        // When: 多次清空
        try conversationManager.markAsRead(conversationID: conv1ID)
        try conversationManager.markAsRead(conversationID: conv1ID)
        
        // Then: 不应该出错，未读数保持为 0
        let count = conversationManager.getUnreadCount(conversationID: conv1ID)
        XCTAssertEqual(count, 0, "Should remain 0 after multiple clears")
    }
    
    // MARK: - 性能测试
    
    /// 测试 18：大量会话的总未读数性能
    func testTotalUnreadCountPerformance() throws {
        // Given: 创建多个会话并设置未读数
        for i in 0..<100 {
            let conv = IMConversation()
            conv.conversationID = "perf_conv_\(i)"
            conv.showName = "Performance \(i)"
            conv.unreadCount = i % 10
            try database.saveConversation(conv)
        }
        
        // When: 测试获取总未读数的性能
        measure {
            _ = conversationManager.getTotalUnreadCount()
        }
    }
    
    // MARK: - 监听器测试
    
    /// 测试 19：未读数变化通知
    func testUnreadCountChangeNotification() throws {
        let delegate = MockConversationListener()
        conversationManager.addListener(delegate)
        
        let expectation = XCTestExpectation(description: "Unread count changed")
        delegate.onUnreadChanged = { conversationID, count in
            XCTAssertEqual(conversationID, self.conv1ID)
            XCTAssertEqual(count, 5)
            expectation.fulfill()
        }
        
        // When: 增加未读数
        conversationManager.incrementUnreadCount(conversationID: conv1ID, by: 5)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// 测试 20：总未读数变化通知
    func testTotalUnreadCountChangeNotification() throws {
        let delegate = MockConversationListener()
        conversationManager.addListener(delegate)
        
        let expectation = XCTestExpectation(description: "Total unread count changed")
        delegate.onTotalUnreadChanged = { count in
            XCTAssertEqual(count, 3)
            expectation.fulfill()
        }
        
        // When: 增加未读数
        conversationManager.incrementUnreadCount(conversationID: conv1ID, by: 3)
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Delegate

class MockConversationListener: IMConversationListener {
    var onUnreadChanged: ((String, Int) -> Void)?
    var onTotalUnreadChanged: ((Int) -> Void)?
    
    func onUnreadCountChanged(_ conversationID: String, count: Int) {
        onUnreadChanged?(conversationID, count)
    }
    
    func onTotalUnreadCountChanged(_ count: Int) {
        onTotalUnreadChanged?(count)
    }
}


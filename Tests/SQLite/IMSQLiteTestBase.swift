/// IMSQLiteTestBase - SQLite 测试基类
///
/// 提供所有 SQLite 测试的基础设施：
/// - 测试数据库的创建和清理
/// - 常用测试数据生成
/// - 测试辅助方法

import XCTest
@testable import IMSDK
import Foundation

class IMSQLiteTestBase: XCTestCase {
    
    // MARK: - Properties
    
    var database: IMDatabaseManager!
    var testUserID: String!
    var testDBPath: String!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // 生成唯一的测试用户 ID
        testUserID = "test_user_\(UUID().uuidString)"
        
        do {
            // 创建测试数据库
            database = try IMDatabaseManager(userID: testUserID)
            
            // 获取数据库路径（用于验证）
            let fileURL = try FileManager.default
                .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("im_sdk_\(testUserID).sqlite")
            testDBPath = fileURL.path
            
            IMLogger.shared.info("[SQLiteTest] 测试数据库创建成功: \(testUserID)")
        } catch {
            XCTFail("创建测试数据库失败: \(error)")
        }
    }
    
    override func tearDown() {
        // 关闭数据库
        database?.close()
        database = nil
        
        // 删除测试数据库文件
        if let dbPath = testDBPath {
            do {
                let fileManager = FileManager.default
                
                // 删除主数据库文件
                if fileManager.fileExists(atPath: dbPath) {
                    try fileManager.removeItem(atPath: dbPath)
                }
                
                // 删除 WAL 文件
                let walPath = dbPath + "-wal"
                if fileManager.fileExists(atPath: walPath) {
                    try fileManager.removeItem(atPath: walPath)
                }
                
                // 删除 SHM 文件
                let shmPath = dbPath + "-shm"
                if fileManager.fileExists(atPath: shmPath) {
                    try fileManager.removeItem(atPath: shmPath)
                }
                
                IMLogger.shared.info("[SQLiteTest] 测试数据库已清理: \(testUserID ?? "")")
            } catch {
                IMLogger.shared.error("[SQLiteTest] 清理测试数据库失败: \(error)")
            }
        }
        
        testUserID = nil
        testDBPath = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Data Generators
    
    /// 创建测试消息
    func createTestMessage(
        messageID: String? = nil,
        conversationID: String = "test_conv_1",
        senderID: String = "test_sender_1",
        content: String = "Test message",
        messageType: IMMessageType = .text,
        status: IMMessageStatus = .sent,
        seq: Int64? = nil
    ) -> IMMessage {
        let message = IMMessage()
        message.messageID = messageID ?? "msg_\(UUID().uuidString)"
        message.conversationID = conversationID
        message.senderID = senderID
        message.receiverID = "test_receiver_1"
        message.content = content
        message.messageType = messageType
        message.status = status
        message.direction = .outgoing
        message.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        message.seq = seq ?? Int64.random(in: 1...1000000)
        return message
    }
    
    /// 创建测试会话
    func createTestConversation(
        conversationID: String? = nil,
        conversationType: IMConversationType = .single,
        lastMessageTime: Int64? = nil,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        isMuted: Bool = false
    ) -> IMConversation {
        let conversation = IMConversation()
        conversation.conversationID = conversationID ?? "conv_\(UUID().uuidString)"
        conversation.conversationType = conversationType
        conversation.targetID = "target_\(UUID().uuidString)"
        conversation.lastMessageID = "msg_last"
        conversation.lastMessageTime = lastMessageTime ?? Int64(Date().timeIntervalSince1970 * 1000)
        conversation.lastMessageContent = "Last message"
        conversation.unreadCount = unreadCount
        conversation.isPinned = isPinned
        conversation.isMuted = isMuted
        return conversation
    }
    
    /// 创建测试用户
    func createTestUser(
        userID: String? = nil,
        nickname: String? = nil,
        isOnline: Bool = false
    ) -> IMUser {
        let user = IMUser()
        user.userID = userID ?? "user_\(UUID().uuidString)"
        user.nickname = nickname ?? "User_\(UUID().uuidString.prefix(8))"
        user.avatar = "https://example.com/avatar.jpg"
        user.phone = "138\(Int.random(in: 10000000...99999999))"
        user.email = "\(user.userID)@example.com"
        user.gender = Int.random(in: 0...2)
        user.isOnline = isOnline
        return user
    }
    
    /// 创建测试群组
    func createTestGroup(
        groupID: String? = nil,
        groupName: String? = nil,
        ownerID: String = "test_owner_1",
        memberCount: Int = 0
    ) -> IMGroup {
        let group = IMGroup()
        group.groupID = groupID ?? "group_\(UUID().uuidString)"
        group.groupName = groupName ?? "Group_\(UUID().uuidString.prefix(8))"
        group.groupAvatar = "https://example.com/group.jpg"
        group.ownerID = ownerID
        group.groupType = 0
        group.memberCount = memberCount
        group.introduction = "Test group"
        group.createTime = Int64(Date().timeIntervalSince1970 * 1000)
        return group
    }
    
    /// 创建批量测试消息
    func createTestMessages(
        count: Int,
        conversationID: String = "test_conv_1",
        startSeq: Int64 = 1
    ) -> [IMMessage] {
        var messages: [IMMessage] = []
        for i in 0..<count {
            let message = createTestMessage(
                messageID: "msg_\(i)",
                conversationID: conversationID,
                content: "Test message \(i)",
                seq: startSeq + Int64(i)
            )
            messages.append(message)
        }
        return messages
    }
    
    // MARK: - Assertion Helpers
    
    /// 断言消息相等
    func assertMessagesEqual(
        _ message1: IMMessage?,
        _ message2: IMMessage?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let msg1 = message1, let msg2 = message2 else {
            XCTFail("消息为空", file: file, line: line)
            return
        }
        
        XCTAssertEqual(msg1.messageID, msg2.messageID, "messageID 不匹配", file: file, line: line)
        XCTAssertEqual(msg1.conversationID, msg2.conversationID, "conversationID 不匹配", file: file, line: line)
        XCTAssertEqual(msg1.senderID, msg2.senderID, "senderID 不匹配", file: file, line: line)
        XCTAssertEqual(msg1.content, msg2.content, "content 不匹配", file: file, line: line)
        XCTAssertEqual(msg1.messageType, msg2.messageType, "messageType 不匹配", file: file, line: line)
        XCTAssertEqual(msg1.seq, msg2.seq, "seq 不匹配", file: file, line: line)
    }
    
    /// 断言会话相等
    func assertConversationsEqual(
        _ conv1: IMConversation?,
        _ conv2: IMConversation?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let c1 = conv1, let c2 = conv2 else {
            XCTFail("会话为空", file: file, line: line)
            return
        }
        
        XCTAssertEqual(c1.conversationID, c2.conversationID, "conversationID 不匹配", file: file, line: line)
        XCTAssertEqual(c1.conversationType, c2.conversationType, "conversationType 不匹配", file: file, line: line)
        XCTAssertEqual(c1.targetID, c2.targetID, "targetID 不匹配", file: file, line: line)
        XCTAssertEqual(c1.lastMessageID, c2.lastMessageID, "lastMessageID 不匹配", file: file, line: line)
        XCTAssertEqual(c1.unreadCount, c2.unreadCount, "unreadCount 不匹配", file: file, line: line)
        XCTAssertEqual(c1.isPinned, c2.isPinned, "isPinned 不匹配", file: file, line: line)
        XCTAssertEqual(c1.isMuted, c2.isMuted, "isMuted 不匹配", file: file, line: line)
    }
    
    /// 断言用户相等
    func assertUsersEqual(
        _ user1: IMUser?,
        _ user2: IMUser?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let u1 = user1, let u2 = user2 else {
            XCTFail("用户为空", file: file, line: line)
            return
        }
        
        XCTAssertEqual(u1.userID, u2.userID, "userID 不匹配", file: file, line: line)
        XCTAssertEqual(u1.nickname, u2.nickname, "nickname 不匹配", file: file, line: line)
        XCTAssertEqual(u1.avatar, u2.avatar, "avatar 不匹配", file: file, line: line)
        XCTAssertEqual(u1.phone, u2.phone, "phone 不匹配", file: file, line: line)
        XCTAssertEqual(u1.email, u2.email, "email 不匹配", file: file, line: line)
        XCTAssertEqual(u1.isOnline, u2.isOnline, "isOnline 不匹配", file: file, line: line)
    }
    
    /// 断言群组相等
    func assertGroupsEqual(
        _ group1: IMGroup?,
        _ group2: IMGroup?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let g1 = group1, let g2 = group2 else {
            XCTFail("群组为空", file: file, line: line)
            return
        }
        
        XCTAssertEqual(g1.groupID, g2.groupID, "groupID 不匹配", file: file, line: line)
        XCTAssertEqual(g1.groupName, g2.groupName, "groupName 不匹配", file: file, line: line)
        XCTAssertEqual(g1.ownerID, g2.ownerID, "ownerID 不匹配", file: file, line: line)
        XCTAssertEqual(g1.memberCount, g2.memberCount, "memberCount 不匹配", file: file, line: line)
    }
    
    // MARK: - Performance Helpers
    
    /// 测量执行时间
    func measureExecutionTime(
        _ block: () throws -> Void,
        description: String = "操作"
    ) rethrows -> TimeInterval {
        let startTime = Date()
        try block()
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        IMLogger.shared.info("[性能] \(description): \(String(format: "%.2f", duration * 1000))ms")
        return duration
    }
    
    /// 验证操作在指定时间内完成
    func assertPerformance(
        maxDuration: TimeInterval,
        _ block: () throws -> Void,
        description: String = "操作",
        file: StaticString = #file,
        line: UInt = #line
    ) rethrows {
        let duration = try measureExecutionTime(block, description: description)
        XCTAssertLessThan(
            duration,
            maxDuration,
            "\(description) 超时: \(String(format: "%.2f", duration * 1000))ms > \(String(format: "%.2f", maxDuration * 1000))ms",
            file: file,
            line: line
        )
    }
    
    // MARK: - Database Helpers
    
    /// 获取数据库文件大小（字节）
    func getDatabaseSize() -> Int64 {
        guard let dbPath = testDBPath else { return 0 }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// 获取 WAL 文件大小（字节）
    func getWALSize() -> Int64 {
        guard let dbPath = testDBPath else { return 0 }
        let walPath = dbPath + "-wal"
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: walPath)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// 检查 WAL 文件是否存在
    func walFileExists() -> Bool {
        guard let dbPath = testDBPath else { return false }
        let walPath = dbPath + "-wal"
        return FileManager.default.fileExists(atPath: walPath)
    }
}


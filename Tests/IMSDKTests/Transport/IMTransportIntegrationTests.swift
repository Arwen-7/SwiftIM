//
//  IMTransportIntegrationTests.swift
//  IMSDKTests
//
//  Created by IMSDK on 2025-01-26.
//

import XCTest
@testable import IMSDK

/// 传输层集成测试（测试完整的发送/接收流程）
final class IMTransportIntegrationTests: XCTestCase {
    
    var encoder: IMMessageEncoder!
    var router: IMMessageRouter!
    
    override func setUp() {
        super.setUp()
        encoder = IMMessageEncoder()
        router = IMMessageRouter()
    }
    
    override func tearDown() {
        encoder = nil
        router = nil
        super.tearDown()
    }
    
    // MARK: - 端到端测试
    
    func testCompleteMessageFlow() throws {
        // Given - 模拟完整的消息发送和接收流程
        var sentMessage: IMMessage?
        var receivedMessage: IMMessage?
        let sendExpectation = self.expectation(description: "Message sent")
        let receiveExpectation = self.expectation(description: "Message received")
        
        // 注册接收处理器
        router.register(command: .pushMsg, type: IMPushMessage.self) { pushMsg, _ in
            receivedMessage = pushMsg.toIMMessage()
            receiveExpectation.fulfill()
        }
        
        // When - 发送消息
        let message = IMMessage()
        message.clientMsgID = UUID().uuidString
        message.conversationID = "conv_123"
        message.senderID = "sender_456"
        message.messageType = .text
        message.content = "Integration test message"
        message.sendTime = Int64(Date().timeIntervalSince1970)
        
        let (sendData, sequence) = try encoder.encodeSendMessageRequest(message: message)
        sentMessage = message
        sendExpectation.fulfill()
        
        // 模拟服务器响应（发送成功响应）
        var sendRsp = IMSendMessageResponse()
        sendRsp.errorCode = 0
        sendRsp.messageID = "server_msg_\(sequence)"
        sendRsp.clientMsgID = message.clientMsgID
        sendRsp.sendTime = message.sendTime
        
        let sendRspData = try encoder.encodeMessage(sendRsp, command: .sendMsgRsp, sequence: sequence)
        
        // 模拟消息推送（接收方收到消息）
        var pushMsg = IMPushMessage()
        pushMsg.messageID = sendRsp.messageID
        pushMsg.clientMsgID = message.clientMsgID
        pushMsg.conversationID = message.conversationID
        pushMsg.senderID = message.senderID
        pushMsg.messageType = Int32(message.messageType.rawValue)
        pushMsg.content = message.content
        pushMsg.sendTime = message.sendTime
        pushMsg.seq = Int64(sequence)
        
        let pushData = try encoder.encodeMessage(pushMsg, command: .pushMsg)
        
        // Then - 路由接收数据
        router.route(data: pushData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertNotNil(sentMessage)
        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.content, sentMessage?.content)
        XCTAssertEqual(receivedMessage?.clientMsgID, sentMessage?.clientMsgID)
    }
    
    func testAuthenticationFlow() throws {
        // Given
        var authSucceeded = false
        var maxSeq: Int64 = 0
        let expectation = self.expectation(description: "Authentication")
        
        router.register(command: .authRsp, type: IMAuthResponse.self) { response, _ in
            if response.errorCode == 0 {
                authSucceeded = true
                maxSeq = response.maxSeq
            }
            expectation.fulfill()
        }
        
        // When - 发送认证请求
        let authReqData = try encoder.encodeAuthRequest(userID: "user123", token: "token456")
        
        // 模拟服务器响应
        var authRsp = IMAuthResponse()
        authRsp.errorCode = 0
        authRsp.errorMsg = "Authentication successful"
        authRsp.maxSeq = 5000
        
        let authRspData = try encoder.encodeMessage(authRsp, command: .authRsp)
        
        // Then
        router.route(data: authRspData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(authSucceeded)
        XCTAssertEqual(maxSeq, 5000)
    }
    
    func testHeartbeatFlow() throws {
        // Given
        var heartbeatReceived = false
        let expectation = self.expectation(description: "Heartbeat")
        
        router.register(command: .heartbeatRsp, type: IMHeartbeatResponse.self) { _, _ in
            heartbeatReceived = true
            expectation.fulfill()
        }
        
        // When - 发送心跳请求
        let heartbeatReqData = try encoder.encodeHeartbeatRequest()
        
        // 模拟服务器响应
        var heartbeatRsp = IMHeartbeatResponse()
        heartbeatRsp.serverTime = Int64(Date().timeIntervalSince1970)
        
        let heartbeatRspData = try encoder.encodeMessage(heartbeatRsp, command: .heartbeatRsp)
        
        // Then
        router.route(data: heartbeatRspData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(heartbeatReceived)
    }
    
    func testMessageSyncFlow() throws {
        // Given
        var syncedMessages: [IMMessage] = []
        let expectation = self.expectation(description: "Message sync")
        
        router.register(command: .syncRsp, type: IMSyncResponse.self) { response, _ in
            syncedMessages = response.messages.map { $0.toIMMessage() }
            expectation.fulfill()
        }
        
        // When - 发送同步请求
        let syncReqData = try encoder.encodeSyncRequest(minSeq: 100, maxSeq: 200, limit: 50)
        
        // 模拟服务器响应
        var syncRsp = IMSyncResponse()
        syncRsp.errorCode = 0
        syncRsp.serverMaxSeq = 500
        syncRsp.hasMore = false
        
        for i in 100...105 {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            pushMsg.content = "Synced message \(i)"
            pushMsg.seq = Int64(i)
            syncRsp.messages.append(pushMsg)
        }
        
        let syncRspData = try encoder.encodeMessage(syncRsp, command: .syncRsp)
        
        // Then
        router.route(data: syncRspData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(syncedMessages.count, 6)
        XCTAssertEqual(syncedMessages.first?.content, "Synced message 100")
        XCTAssertEqual(syncedMessages.last?.content, "Synced message 105")
    }
    
    func testMessageRevokeFlow() throws {
        // Given
        var revokedMessageID: String?
        let expectation = self.expectation(description: "Message revoke")
        
        router.register(command: .revokeMsgPush, type: IMRevokeMessagePush.self) { push, _ in
            revokedMessageID = push.messageID
            expectation.fulfill()
        }
        
        // When - 发送撤回请求
        let revokeReqData = try encoder.encodeRevokeMessageRequest(
            messageID: "msg_123",
            conversationID: "conv_456"
        )
        
        // 模拟服务器推送撤回通知
        var revokePush = IMRevokeMessagePush()
        revokePush.messageID = "msg_123"
        revokePush.conversationID = "conv_456"
        revokePush.revokedBy = "user_789"
        revokePush.revokedTime = Int64(Date().timeIntervalSince1970)
        
        let revokePushData = try encoder.encodeMessage(revokePush, command: .revokeMsgPush)
        
        // Then
        router.route(data: revokePushData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(revokedMessageID, "msg_123")
    }
    
    func testReadReceiptFlow() throws {
        // Given
        var readMessageIDs: [String] = []
        let expectation = self.expectation(description: "Read receipt")
        
        router.register(command: .readReceiptPush, type: IMReadReceiptPush.self) { push, _ in
            readMessageIDs = push.messageIDs
            expectation.fulfill()
        }
        
        // When - 发送已读回执请求
        let messageIDs = ["msg_1", "msg_2", "msg_3"]
        let readReqData = try encoder.encodeReadReceiptRequest(
            messageIDs: messageIDs,
            conversationID: "conv_123"
        )
        
        // 模拟服务器推送已读回执
        var readPush = IMReadReceiptPush()
        readPush.messageIDs = messageIDs
        readPush.conversationID = "conv_123"
        readPush.userID = "user_456"
        readPush.readTime = Int64(Date().timeIntervalSince1970)
        
        let readPushData = try encoder.encodeMessage(readPush, command: .readReceiptPush)
        
        // Then
        router.route(data: readPushData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(readMessageIDs, messageIDs)
    }
    
    // MARK: - 批量消息测试
    
    func testBatchMessageReceive() throws {
        // Given
        var receivedMessages: [IMMessage] = []
        let expectation = self.expectation(description: "Batch messages")
        
        router.register(command: .batchMsg, type: IMBatchMessages.self) { batchMsg, _ in
            receivedMessages = batchMsg.messages.map { $0.toIMMessage() }
            expectation.fulfill()
        }
        
        // When - 模拟批量消息推送
        var batchMsg = IMBatchMessages()
        for i in 1...10 {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            pushMsg.content = "Batch message \(i)"
            pushMsg.seq = Int64(i)
            batchMsg.messages.append(pushMsg)
        }
        
        let batchData = try encoder.encodeMessage(batchMsg, command: .batchMsg)
        
        // Then
        router.route(data: batchData)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedMessages.count, 10)
    }
    
    // MARK: - 错误场景测试
    
    func testAuthenticationFailure() throws {
        // Given
        var authFailed = false
        var errorMessage: String?
        let expectation = self.expectation(description: "Auth failure")
        
        router.register(command: .authRsp, type: IMAuthResponse.self) { response, _ in
            if response.errorCode != 0 {
                authFailed = true
                errorMessage = response.errorMsg
            }
            expectation.fulfill()
        }
        
        // When - 模拟认证失败
        var authRsp = IMAuthResponse()
        authRsp.errorCode = 401
        authRsp.errorMsg = "Invalid token"
        
        let authRspData = try encoder.encodeMessage(authRsp, command: .authRsp)
        router.route(data: authRspData)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(authFailed)
        XCTAssertEqual(errorMessage, "Invalid token")
    }
    
    func testMessageSendFailure() throws {
        // Given
        var sendFailed = false
        var errorCode: Int32 = 0
        let expectation = self.expectation(description: "Send failure")
        
        router.register(command: .sendMsgRsp, type: IMSendMessageResponse.self) { response, _ in
            if response.errorCode != 0 {
                sendFailed = true
                errorCode = response.errorCode
            }
            expectation.fulfill()
        }
        
        // When - 模拟发送失败
        var sendRsp = IMSendMessageResponse()
        sendRsp.errorCode = 500
        sendRsp.errorMsg = "Server error"
        
        let sendRspData = try encoder.encodeMessage(sendRsp, command: .sendMsgRsp)
        router.route(data: sendRspData)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(sendFailed)
        XCTAssertEqual(errorCode, 500)
    }
    
    // MARK: - 性能测试
    
    func testHighThroughputMessageFlow() throws {
        // Given - 模拟高吞吐量消息流
        let messageCount = 1000
        var receivedCount = 0
        let lock = NSLock()
        let expectation = self.expectation(description: "High throughput")
        expectation.expectedFulfillmentCount = messageCount
        
        router.register(command: .pushMsg, type: IMPushMessage.self) { _, _ in
            lock.lock()
            receivedCount += 1
            lock.unlock()
            expectation.fulfill()
        }
        
        // When - 发送 1000 条消息
        var data = Data()
        for i in 0..<messageCount {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            pushMsg.content = "Message \(i)"
            data.append(try encoder.encodeMessage(pushMsg, command: .pushMsg))
        }
        
        let startTime = Date()
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 10.0)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(receivedCount, messageCount)
        XCTAssertLessThan(duration, 5.0, "处理 1000 条消息应该在 5 秒内完成")
        
        let messagesPerSecond = Double(messageCount) / duration
        print("✅ 吞吐量：\(Int(messagesPerSecond)) 条/秒")
    }
}


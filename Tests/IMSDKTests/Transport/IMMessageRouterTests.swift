//
//  IMMessageRouterTests.swift
//  IMSDKTests
//
//  Created by IMSDK on 2025-01-26.
//

import XCTest
@testable import IMSDK

/// 测试消息路由器
final class IMMessageRouterTests: XCTestCase {
    
    var router: IMMessageRouter!
    var encoder: IMMessageEncoder!
    
    override func setUp() {
        super.setUp()
        router = IMMessageRouter()
        encoder = IMMessageEncoder()
    }
    
    override func tearDown() {
        router = nil
        encoder = nil
        super.tearDown()
    }
    
    // MARK: - 路由注册测试
    
    func testRegisterHandler() throws {
        // Given
        var receivedMessage: IMHeartbeatResponse?
        var receivedSequence: UInt32?
        let expectation = self.expectation(description: "Handler called")
        
        // When - 注册处理器
        router.register(command: .heartbeatRsp, type: IMHeartbeatResponse.self) { message, sequence in
            receivedMessage = message
            receivedSequence = sequence
            expectation.fulfill()
        }
        
        // 发送消息
        let response = IMHeartbeatResponse()
        response.serverTime = 1234567890
        let data = try encoder.encodeMessage(response, command: .heartbeatRsp)
        
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.serverTime, 1234567890)
        XCTAssertNotNil(receivedSequence)
    }
    
    func testRegisterMultipleHandlers() throws {
        // Given
        var authReceived = false
        var heartbeatReceived = false
        let expectation = self.expectation(description: "Both handlers called")
        expectation.expectedFulfillmentCount = 2
        
        // When - 注册多个处理器
        router.register(command: .authRsp, type: IMAuthResponse.self) { _, _ in
            authReceived = true
            expectation.fulfill()
        }
        
        router.register(command: .heartbeatRsp, type: IMHeartbeatResponse.self) { _, _ in
            heartbeatReceived = true
            expectation.fulfill()
        }
        
        // 发送两种消息
        let authRsp = IMAuthResponse()
        let heartbeatRsp = IMHeartbeatResponse()
        
        var data = Data()
        data.append(try encoder.encodeMessage(authRsp, command: .authRsp))
        data.append(try encoder.encodeMessage(heartbeatRsp, command: .heartbeatRsp))
        
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(authReceived)
        XCTAssertTrue(heartbeatReceived)
    }
    
    func testUnregisteredCommandIgnored() throws {
        // Given - 没有注册处理器
        var handlerCalled = false
        router.register(command: .authRsp, type: IMAuthResponse.self) { _, _ in
            handlerCalled = true
        }
        
        // When - 发送一个未注册的命令
        let heartbeatRsp = IMHeartbeatResponse()
        let data = try encoder.encodeMessage(heartbeatRsp, command: .heartbeatRsp)
        router.route(data: data)
        
        // Then
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(handlerCalled, "未注册的命令不应该触发处理器")
    }
    
    // MARK: - 批量消息路由测试
    
    func testRouteBatchMessages() throws {
        // Given
        var receivedMessages: [IMPushMessage] = []
        let expectation = self.expectation(description: "Multiple messages routed")
        expectation.expectedFulfillmentCount = 3
        
        router.register(command: .pushMsg, type: IMPushMessage.self) { message, _ in
            receivedMessages.append(message)
            expectation.fulfill()
        }
        
        // When - 发送 3 个消息
        var data = Data()
        for i in 1...3 {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            pushMsg.content = "Message \(i)"
            data.append(try encoder.encodeMessage(pushMsg, command: .pushMsg))
        }
        
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedMessages.count, 3)
        XCTAssertEqual(receivedMessages[0].messageID, "msg_1")
        XCTAssertEqual(receivedMessages[2].messageID, "msg_3")
    }
    
    // MARK: - 序列号测试
    
    func testSequenceNumberMatching() throws {
        // Given
        var capturedSequences: [UInt32] = []
        let expectation = self.expectation(description: "Sequences captured")
        expectation.expectedFulfillmentCount = 3
        
        router.register(command: .msgAck, type: IMMessageAck.self) { _, sequence in
            capturedSequences.append(sequence)
            expectation.fulfill()
        }
        
        // When
        var data = Data()
        let sequences: [UInt32] = [100, 200, 300]
        for seq in sequences {
            let ack = IMMessageAck(messageID: "msg_\(seq)", seq: Int64(seq))
            data.append(try encoder.encodeMessage(ack, command: .msgAck, sequence: seq))
        }
        
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(capturedSequences, sequences)
    }
    
    // MARK: - 错误处理测试
    
    func testRouteWithInvalidData() {
        // Given
        var handlerCalled = false
        router.register(command: .authRsp, type: IMAuthResponse.self) { _, _ in
            handlerCalled = true
        }
        
        // When - 发送无效数据
        let invalidData = Data([0xFF, 0xFF, 0xFF, 0xFF])
        router.route(data: invalidData)
        
        // Then
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(handlerCalled, "无效数据不应该触发处理器")
    }
    
    func testRouteWithWrongMessageType() throws {
        // Given - 注册了 AuthResponse，但发送 HeartbeatResponse
        var authReceived = false
        router.register(command: .authRsp, type: IMAuthResponse.self) { _, _ in
            authReceived = true
        }
        
        // When
        let heartbeat = IMHeartbeatResponse()
        let data = try encoder.encodeMessage(heartbeat, command: .heartbeatRsp)
        router.route(data: data)
        
        // Then
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(authReceived, "错误的消息类型不应该触发处理器")
    }
    
    // MARK: - 清理测试
    
    func testClearHandlers() throws {
        // Given
        var handlerCalled = false
        router.register(command: .authRsp, type: IMAuthResponse.self) { _, _ in
            handlerCalled = true
        }
        
        // When - 清除所有处理器
        router.clearHandlers()
        
        let authRsp = IMAuthResponse()
        let data = try encoder.encodeMessage(authRsp, command: .authRsp)
        router.route(data: data)
        
        // Then
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(handlerCalled, "清除后不应该触发处理器")
    }
    
    // MARK: - 并发测试
    
    func testConcurrentRouting() throws {
        // Given
        let count = 100
        var receivedCount = 0
        let lock = NSLock()
        let expectation = self.expectation(description: "Concurrent routing")
        expectation.expectedFulfillmentCount = count
        
        router.register(command: .pushMsg, type: IMPushMessage.self) { _, _ in
            lock.lock()
            receivedCount += 1
            lock.unlock()
            expectation.fulfill()
        }
        
        // When - 并发路由
        for i in 0..<count {
            DispatchQueue.global().async {
                var pushMsg = IMPushMessage()
                pushMsg.messageID = "msg_\(i)"
                if let data = try? self.encoder.encodeMessage(pushMsg, command: .pushMsg) {
                    self.router.route(data: data)
                }
            }
        }
        
        // Then
        waitForExpectations(timeout: 5.0)
        XCTAssertEqual(receivedCount, count)
    }
    
    // MARK: - 实际场景测试
    
    func testAuthFlow() throws {
        // Given
        var authSucceeded = false
        let expectation = self.expectation(description: "Auth flow")
        
        router.register(command: .authRsp, type: IMAuthResponse.self) { response, _ in
            if response.errorCode == 0 {
                authSucceeded = true
            }
            expectation.fulfill()
        }
        
        // When - 模拟认证响应
        var authRsp = IMAuthResponse()
        authRsp.errorCode = 0
        authRsp.errorMsg = "Success"
        authRsp.maxSeq = 1000
        
        let data = try encoder.encodeMessage(authRsp, command: .authRsp)
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(authSucceeded)
    }
    
    func testMessageReceiveFlow() throws {
        // Given
        var receivedMessages: [IMMessage] = []
        let expectation = self.expectation(description: "Message receive")
        expectation.expectedFulfillmentCount = 2
        
        router.register(command: .pushMsg, type: IMPushMessage.self) { pushMsg, _ in
            receivedMessages.append(pushMsg.toIMMessage())
            expectation.fulfill()
        }
        
        // When - 模拟接收两条消息
        var data = Data()
        for i in 1...2 {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            pushMsg.content = "Hello \(i)"
            pushMsg.senderID = "sender_\(i)"
            pushMsg.messageType = 1  // text
            data.append(try encoder.encodeMessage(pushMsg, command: .pushMsg))
        }
        
        router.route(data: data)
        
        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedMessages.count, 2)
        XCTAssertEqual(receivedMessages[0].content, "Hello 1")
        XCTAssertEqual(receivedMessages[1].content, "Hello 2")
    }
    
    // MARK: - 性能测试
    
    func testRoutingPerformance() throws {
        // Given
        router.register(command: .pushMsg, type: IMPushMessage.self) { _, _ in
            // 空处理器
        }
        
        // 准备 100 个消息的数据
        var data = Data()
        for i in 0..<100 {
            var pushMsg = IMPushMessage()
            pushMsg.messageID = "msg_\(i)"
            data.append(try encoder.encodeMessage(pushMsg, command: .pushMsg))
        }
        
        // When & Then
        measure {
            self.router.route(data: data)
        }
    }
}


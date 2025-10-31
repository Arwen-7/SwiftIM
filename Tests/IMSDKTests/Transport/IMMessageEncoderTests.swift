//
//  IMMessageEncoderTests.swift
//  IMSDKTests
//
//  Created by IMSDK on 2025-01-26.
//

import XCTest
@testable import IMSDK

/// 测试完整的消息编码器（协议 + 包头）
final class IMMessageEncoderTests: XCTestCase {
    
    var encoder: IMMessageEncoder!
    
    override func setUp() {
        super.setUp()
        encoder = IMMessageEncoder()
    }
    
    override func tearDown() {
        encoder = nil
        super.tearDown()
    }
    
    // MARK: - 完整编解码测试
    
    func testEncodeAuthRequest() throws {
        // Given
        
        // When
        let data = try encoder.encodeAuthRequest(userID: "user123", token: "token456")
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        
        // 验证可以解码
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .authReq)
    }
    
    func testEncodeSendMessageRequest() throws {
        // Given
        let message = IMMessage()
        message.clientMsgID = UUID().uuidString
        message.conversationID = "conv_123"
        message.senderID = "sender_456"
        message.messageType = .text
        message.content = "Hello, World!"
        
        // When
        let (data, sequence) = try encoder.encodeSendMessageRequest(message: message)
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        XCTAssertGreaterThan(sequence, 0)
        
        // 验证可以解码
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .sendMsgReq)
        XCTAssertEqual(packets[0].sequence, sequence)
    }
    
    func testEncodeHeartbeatRequest() throws {
        // Given
        
        // When
        let data = try encoder.encodeHeartbeatRequest()
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .heartbeatReq)
    }
    
    func testEncodeMessageAck() throws {
        // Given
        let messageID = "msg_123"
        let seq: Int64 = 100
        
        // When
        let data = try encoder.encodeMessageAck(messageID: messageID, seq: seq)
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .msgAck)
    }
    
    // MARK: - 数据流解码测试
    
    func testDecodeDataWithSinglePacket() throws {
        // Given
        let data = try encoder.encodeHeartbeatRequest()
        
        // When
        let packets = try encoder.decodeData(data)
        
        // Then
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .heartbeatReq)
        XCTAssertGreaterThan(packets[0].sequence, 0)
    }
    
    func testDecodeDataWithMultiplePackets() throws {
        // Given - 多个包粘在一起
        var data = Data()
        data.append(try encoder.encodeHeartbeatRequest())
        data.append(try encoder.encodeMessageAck(messageID: "msg_1", seq: 1))
        data.append(try encoder.encodeMessageAck(messageID: "msg_2", seq: 2))
        
        // When
        let packets = try encoder.decodeData(data)
        
        // Then
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(packets[0].command, .heartbeatReq)
        XCTAssertEqual(packets[1].command, .msgAck)
        XCTAssertEqual(packets[2].command, .msgAck)
    }
    
    func testDecodeBodyWithCorrectType() throws {
        // Given
        let authReq = IMAuthRequest(userID: "user123", token: "token456", platform: "iOS")
        let data = try encoder.encodeMessage(authReq, command: .authReq)
        
        let packets = try encoder.decodeData(data)
        let body = packets[0].body
        
        // When
        let decoded = try encoder.decodeBody(IMAuthRequest.self, from: body)
        
        // Then
        XCTAssertEqual(decoded.userID, "user123")
        XCTAssertEqual(decoded.token, "token456")
        XCTAssertEqual(decoded.platform, "iOS")
    }
    
    // MARK: - 便捷方法测试
    
    func testEncodeRevokeMessageRequest() throws {
        // Given
        let messageID = "msg_123"
        let conversationID = "conv_456"
        
        // When
        let data = try encoder.encodeRevokeMessageRequest(
            messageID: messageID,
            conversationID: conversationID
        )
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .revokeMsgReq)
    }
    
    func testEncodeSyncRequest() throws {
        // Given
        let minSeq: Int64 = 100
        let maxSeq: Int64 = 200
        let limit: Int32 = 50
        
        // When
        let data = try encoder.encodeSyncRequest(minSeq: minSeq, maxSeq: maxSeq, limit: limit)
        
        // Then
        XCTAssertGreaterThan(data.count, kPacketHeaderSize)
        
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .syncReq)
        
        // 验证内容
        let decoded = try encoder.decodeBody(IMSyncRequest.self, from: packets[0].body)
        XCTAssertEqual(decoded.minSeq, minSeq)
        XCTAssertEqual(decoded.maxSeq, maxSeq)
        XCTAssertEqual(decoded.limit, limit)
    }
    
    func testEncodeReadReceiptRequest() throws {
        // Given
        let messageIDs = ["msg_1", "msg_2", "msg_3"]
        let conversationID = "conv_123"
        
        // When
        let data = try encoder.encodeReadReceiptRequest(
            messageIDs: messageIDs,
            conversationID: conversationID
        )
        
        // Then
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .readReceiptReq)
        
        let decoded = try encoder.decodeBody(IMReadReceiptRequest.self, from: packets[0].body)
        XCTAssertEqual(decoded.messageIDs.count, 3)
        XCTAssertEqual(decoded.conversationID, conversationID)
    }
    
    func testEncodeTypingStatusRequest() throws {
        // Given
        let conversationID = "conv_123"
        let isTyping = true
        
        // When
        let data = try encoder.encodeTypingStatusRequest(
            conversationID: conversationID,
            isTyping: isTyping
        )
        
        // Then
        let packets = try encoder.decodeData(data)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].command, .typingStatusReq)
        
        let decoded = try encoder.decodeBody(IMTypingStatusRequest.self, from: packets[0].body)
        XCTAssertEqual(decoded.conversationID, conversationID)
        XCTAssertEqual(decoded.status, 1)  // 1 表示正在输入
    }
    
    // MARK: - 统计信息测试
    
    func testCodecStats() throws {
        // Given
        encoder.resetStats()
        
        // When
        _ = try encoder.encodeHeartbeatRequest()
        _ = try encoder.encodeHeartbeatRequest()
        _ = try encoder.encodeMessageAck(messageID: "msg_1", seq: 1)
        
        // Then
        let codecStats = encoder.codecStats
        XCTAssertEqual(codecStats.totalEncoded, 3)
    }
    
    func testPacketStats() throws {
        // Given
        encoder.resetStats()
        
        // When
        let data = try encoder.encodeHeartbeatRequest()
        _ = try encoder.decodeData(data)
        
        // Then
        let packetStats = encoder.packetStats
        XCTAssertEqual(packetStats.totalPacketsEncoded, 1)
        XCTAssertEqual(packetStats.totalPacketsDecoded, 1)
        XCTAssertGreaterThan(packetStats.totalBytesReceived, 0)
    }
    
    func testResetStats() throws {
        // Given
        _ = try encoder.encodeHeartbeatRequest()
        
        // When
        encoder.resetStats()
        
        // Then
        XCTAssertEqual(encoder.codecStats.totalEncoded, 0)
        XCTAssertEqual(encoder.packetStats.totalPacketsEncoded, 0)
    }
    
    func testClearBuffer() throws {
        // Given
        let data = try encoder.encodeHeartbeatRequest()
        let part1 = data.prefix(10)
        _ = try encoder.decodeData(part1)  // 缓冲区有数据
        
        // When
        encoder.clearBuffer()
        
        // Then
        XCTAssertEqual(encoder.packetStats.currentBufferSize, 0)
    }
    
    // MARK: - 错误处理测试
    
    func testDecodeWithInvalidData() {
        // Given
        let invalidData = Data([0xFF, 0xFF, 0xFF, 0xFF])
        
        // When & Then
        XCTAssertThrowsError(try encoder.decodeData(invalidData))
    }
    
    // MARK: - 性能测试
    
    func testEncodePerformance() {
        let message = IMMessage()
        message.clientMsgID = UUID().uuidString
        message.conversationID = "conv_123"
        message.content = "Test message"
        
        measure {
            for _ in 0..<100 {
                _ = try? self.encoder.encodeSendMessageRequest(message: message)
            }
        }
    }
    
    func testDecodePerformance() throws {
        // Given - 100 个粘在一起的包
        var data = Data()
        for _ in 0..<100 {
            data.append(try encoder.encodeHeartbeatRequest())
        }
        
        // When & Then
        measure {
            self.encoder.clearBuffer()
            _ = try? self.encoder.decodeData(data)
        }
    }
    
    func testEndToEndPerformance() {
        let message = IMMessage()
        message.clientMsgID = UUID().uuidString
        message.conversationID = "conv_123"
        message.content = "Performance test message"
        
        measure {
            for _ in 0..<100 {
                if let (data, _) = try? self.encoder.encodeSendMessageRequest(message: message) {
                    _ = try? self.encoder.decodeData(data)
                }
            }
        }
    }
}


/// IMWebSocketMessageTests - WebSocket 消息编解码单元测试

import XCTest
@testable import IMSDK

final class IMWebSocketMessageTests: XCTestCase {
    
    // MARK: - Encoding Tests
    
    func testEncode_SimpleMessage() throws {
        // Arrange
        let body = "Hello WebSocket".data(using: .utf8)!
        let message = IMWebSocketMessage(
            command: .pushMsg,
            sequence: 12345,
            timestamp: 1635724800000,
            body: body
        )
        
        // Act
        let encoded = message.encode()
        
        // Assert
        XCTAssertGreaterThan(encoded.count, 18, "编码后的数据应大于头部长度")
        XCTAssertEqual(encoded.count, 18 + body.count, "编码后的数据长度应等于头部 + body")
        
        // 验证 command (2 bytes)
        let commandBytes = encoded.subdata(in: 0..<2)
        let commandValue = commandBytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        XCTAssertEqual(commandValue, IMCommandType.pushMsg.rawValue)
        
        // 验证 sequence (4 bytes)
        let seqBytes = encoded.subdata(in: 2..<6)
        let seqValue = seqBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(seqValue, 12345)
        
        // 验证 body length (4 bytes, at offset 14)
        let bodyLengthBytes = encoded.subdata(in: 14..<18)
        let bodyLengthValue = bodyLengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(bodyLengthValue, UInt32(body.count))
    }
    
    func testEncode_EmptyBody() throws {
        // Arrange
        let message = IMWebSocketMessage(
            command: .heartbeatReq,
            sequence: 1,
            timestamp: 1635724800000,
            body: Data()
        )
        
        // Act
        let encoded = message.encode()
        
        // Assert
        XCTAssertEqual(encoded.count, 18, "空 body 的消息应该是 18 字节")
    }
    
    func testEncode_LargeSequence() throws {
        // Arrange
        let message = IMWebSocketMessage(
            command: .syncReq,
            sequence: UInt32.max, // 最大序列号
            timestamp: 1635724800000,
            body: Data([0x01, 0x02, 0x03])
        )
        
        // Act
        let encoded = message.encode()
        
        // Assert
        let seqBytes = encoded.subdata(in: 2..<6)
        let seqValue = seqBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(seqValue, UInt32.max)
    }
    
    // MARK: - Decoding Tests
    
    func testDecode_SimpleMessage() throws {
        // Arrange
        let body = "Hello WebSocket".data(using: .utf8)!
        let originalMessage = IMWebSocketMessage(
            command: .pushMsg,
            sequence: 12345,
            timestamp: 1635724800000,
            body: body
        )
        let encoded = originalMessage.encode()
        
        // Act
        let decoded = try IMWebSocketMessage.decode(encoded)
        
        // Assert
        XCTAssertEqual(decoded.command, originalMessage.command)
        XCTAssertEqual(decoded.sequence, originalMessage.sequence)
        XCTAssertEqual(decoded.timestamp, originalMessage.timestamp)
        XCTAssertEqual(decoded.body, originalMessage.body)
    }
    
    func testDecode_EmptyBody() throws {
        // Arrange
        let originalMessage = IMWebSocketMessage(
            command: .heartbeatRsp,
            sequence: 999,
            timestamp: 1635724800000,
            body: Data()
        )
        let encoded = originalMessage.encode()
        
        // Act
        let decoded = try IMWebSocketMessage.decode(encoded)
        
        // Assert
        XCTAssertEqual(decoded.command, .heartbeatRsp)
        XCTAssertEqual(decoded.sequence, 999)
        XCTAssertEqual(decoded.body.count, 0)
    }
    
    func testDecode_AllCommandTypes() throws {
        // Arrange & Act & Assert
        let commands: [IMCommandType] = [
            .connectReq, .connectRsp, .disconnectReq, .disconnectRsp,
            .heartbeatReq, .heartbeatRsp,
            .authReq, .authRsp, .kickOut,
            .sendMsgReq, .sendMsgRsp, .pushMsg, .msgAck, .batchMsg,
            .syncReq, .syncRsp, .syncFinished,
            .revokeMsgReq, .revokeMsgRsp, .revokeMsgPush,
            .readReceiptReq, .readReceiptRsp, .readReceiptPush,
            .typingStatusReq, .typingStatusPush
        ]
        
        for command in commands {
            let message = IMWebSocketMessage(
                command: command,
                sequence: 1,
                timestamp: 1635724800000,
                body: Data([0xAA, 0xBB])
            )
            let encoded = message.encode()
            let decoded = try IMWebSocketMessage.decode(encoded)
            
            XCTAssertEqual(decoded.command, command, "命令类型 \(command) 编解码失败")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDecode_InvalidDataLength() {
        // Arrange
        let shortData = Data([0x01, 0x02, 0x03]) // 只有 3 字节
        
        // Act & Assert
        XCTAssertThrowsError(try IMWebSocketMessage.decode(shortData)) { error in
            guard case IMWebSocketMessageError.invalidDataLength(let length) = error else {
                XCTFail("应该抛出 invalidDataLength 错误")
                return
            }
            XCTAssertEqual(length, 3)
        }
    }
    
    func testDecode_InvalidCommand() {
        // Arrange
        var data = Data()
        
        // Invalid command (0xFFFF)
        var invalidCommand = UInt16(0xFFFF).bigEndian
        data.append(Data(bytes: &invalidCommand, count: 2))
        
        // Sequence
        var seq = UInt32(1).bigEndian
        data.append(Data(bytes: &seq, count: 4))
        
        // Timestamp
        var timestamp = Int64(1635724800000).bigEndian
        data.append(Data(bytes: &timestamp, count: 8))
        
        // Body length
        var bodyLength = UInt32(0).bigEndian
        data.append(Data(bytes: &bodyLength, count: 4))
        
        // Act & Assert
        XCTAssertThrowsError(try IMWebSocketMessage.decode(data)) { error in
            guard case IMWebSocketMessageError.invalidCommand(let value) = error else {
                XCTFail("应该抛出 invalidCommand 错误")
                return
            }
            XCTAssertEqual(value, 0xFFFF)
        }
    }
    
    func testDecode_BodyLengthMismatch() {
        // Arrange
        var data = Data()
        
        // Command
        var command = IMCommandType.pushMsg.rawValue.bigEndian
        data.append(Data(bytes: &command, count: 2))
        
        // Sequence
        var seq = UInt32(1).bigEndian
        data.append(Data(bytes: &seq, count: 4))
        
        // Timestamp
        var timestamp = Int64(1635724800000).bigEndian
        data.append(Data(bytes: &timestamp, count: 8))
        
        // Body length (声称 100 字节)
        var bodyLength = UInt32(100).bigEndian
        data.append(Data(bytes: &bodyLength, count: 4))
        
        // 但实际只有 10 字节
        data.append(Data(repeating: 0xFF, count: 10))
        
        // Act & Assert
        XCTAssertThrowsError(try IMWebSocketMessage.decode(data)) { error in
            guard case IMWebSocketMessageError.bodyLengthMismatch(let expected, let actual) = error else {
                XCTFail("应该抛出 bodyLengthMismatch 错误")
                return
            }
            XCTAssertEqual(expected, 100)
            XCTAssertEqual(actual, 10)
        }
    }
    
    // MARK: - Round-Trip Tests
    
    func testRoundTrip_MultipleMessages() throws {
        // Arrange
        let messages: [(IMCommandType, UInt32, String)] = [
            (.connectReq, 1, "Connect to server"),
            (.authReq, 2, "Authenticate user"),
            (.pushMsg, 3, "New message from Alice"),
            (.heartbeatReq, 4, ""),
            (.syncReq, 5, "Sync messages"),
            (.readReceiptReq, 6, "Mark as read"),
            (.typingStatusReq, 7, "User is typing")
        ]
        
        // Act & Assert
        for (command, sequence, bodyString) in messages {
            let body = bodyString.data(using: .utf8) ?? Data()
            let original = IMWebSocketMessage(
                command: command,
                sequence: sequence,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                body: body
            )
            
            let encoded = original.encode()
            let decoded = try IMWebSocketMessage.decode(encoded)
            
            XCTAssertEqual(decoded.command, original.command, "命令不匹配: \(command)")
            XCTAssertEqual(decoded.sequence, original.sequence, "序列号不匹配")
            XCTAssertEqual(decoded.timestamp, original.timestamp, "时间戳不匹配")
            XCTAssertEqual(decoded.body, original.body, "Body 不匹配")
        }
    }
    
    func testRoundTrip_BinaryBody() throws {
        // Arrange
        let binaryBody = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC])
        let original = IMWebSocketMessage(
            command: .pushMsg,
            sequence: 888,
            timestamp: 1635724800000,
            body: binaryBody
        )
        
        // Act
        let encoded = original.encode()
        let decoded = try IMWebSocketMessage.decode(encoded)
        
        // Assert
        XCTAssertEqual(decoded.body, binaryBody, "二进制数据应完全一致")
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_Encode1000Messages() {
        let body = "Test message".data(using: .utf8)!
        
        measure {
            for i in 0..<1000 {
                let message = IMWebSocketMessage(
                    command: .pushMsg,
                    sequence: UInt32(i),
                    timestamp: 1635724800000,
                    body: body
                )
                _ = message.encode()
            }
        }
    }
    
    func testPerformance_Decode1000Messages() throws {
        let body = "Test message".data(using: .utf8)!
        let message = IMWebSocketMessage(
            command: .pushMsg,
            sequence: 1,
            timestamp: 1635724800000,
            body: body
        )
        let encoded = message.encode()
        
        measure {
            for _ in 0..<1000 {
                _ = try? IMWebSocketMessage.decode(encoded)
            }
        }
    }
}


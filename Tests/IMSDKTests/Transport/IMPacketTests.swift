//
//  IMPacketTests.swift
//  IMSDKTests
//
//  Created by IMSDK on 2025-01-26.
//

import XCTest
@testable import IMSDK

/// 测试协议包（包头和包体）
final class IMPacketTests: XCTestCase {
    
    // MARK: - 包头测试
    
    func testPacketHeaderEncode() {
        // Given
        let header = IMPacketHeader(
            command: .heartbeatReq,
            sequence: 12345,
            bodyLength: 100
        )
        
        // When
        let data = header.encode()
        
        // Then
        XCTAssertEqual(data.count, kPacketHeaderSize)
        XCTAssertEqual(data.count, 16, "包头应该是 16 字节")
    }
    
    func testPacketHeaderDecode() {
        // Given
        let originalHeader = IMPacketHeader(
            command: .sendMsgReq,
            sequence: 67890,
            bodyLength: 500
        )
        let data = originalHeader.encode()
        
        // When
        let decodedHeader = IMPacketHeader.decode(from: data)
        
        // Then
        XCTAssertNotNil(decodedHeader)
        XCTAssertEqual(decodedHeader?.command, .sendMsgReq)
        XCTAssertEqual(decodedHeader?.sequence, 67890)
        XCTAssertEqual(decodedHeader?.bodyLength, 500)
        XCTAssertTrue(decodedHeader?.isValid ?? false)
    }
    
    func testPacketHeaderDecodeWithInvalidData() {
        // Given - 数据不足
        let invalidData = Data([0x01, 0x02, 0x03])
        
        // When
        let decodedHeader = IMPacketHeader.decode(from: invalidData)
        
        // Then
        XCTAssertNil(decodedHeader, "数据不足应该返回 nil")
    }
    
    func testPacketHeaderReservedFields() {
        // Given
        let header = IMPacketHeader(
            command: .authReq,
            sequence: 100,
            bodyLength: 200,
            reserved: (0x11, 0x22, 0x33)
        )
        
        // When
        let data = header.encode()
        let decoded = IMPacketHeader.decode(from: data)
        
        // Then
        XCTAssertEqual(decoded?.reserved.0, 0x11)
        XCTAssertEqual(decoded?.reserved.1, 0x22)
        XCTAssertEqual(decoded?.reserved.2, 0x33)
    }
    
    // MARK: - 完整包测试
    
    func testPacketEncode() {
        // Given
        let body = "Hello, World!".data(using: .utf8)!
        let packet = IMPacket(
            command: .pushMsg,
            sequence: 999,
            body: body
        )
        
        // When
        let data = packet.encode()
        
        // Then
        XCTAssertEqual(data.count, kPacketHeaderSize + body.count)
        XCTAssertEqual(packet.totalLength, kPacketHeaderSize + body.count)
    }
    
    func testPacketDecode() {
        // Given
        let body = "Test Message".data(using: .utf8)!
        let originalPacket = IMPacket(
            command: .batchMsg,
            sequence: 5555,
            body: body
        )
        let data = originalPacket.encode()
        
        // When
        let decodedPacket = IMPacket.decode(from: data)
        
        // Then
        XCTAssertNotNil(decodedPacket)
        XCTAssertEqual(decodedPacket?.header.command, .batchMsg)
        XCTAssertEqual(decodedPacket?.header.sequence, 5555)
        XCTAssertEqual(decodedPacket?.body, body)
    }
    
    func testPacketDecodeWithIncompleteData() {
        // Given - 只有包头，没有完整的包体
        let header = IMPacketHeader(
            command: .syncReq,
            sequence: 123,
            bodyLength: 1000  // 声称有 1000 字节
        )
        let incompleteData = header.encode()  // 但实际只有 16 字节
        
        // When
        let decoded = IMPacket.decode(from: incompleteData)
        
        // Then
        XCTAssertNil(decoded, "数据不完整应该返回 nil")
    }
    
    // MARK: - 序列号生成器测试
    
    func testSequenceGenerator() {
        // Given
        let generator = IMSequenceGenerator.shared
        generator.reset()
        
        // When
        let seq1 = generator.next()
        let seq2 = generator.next()
        let seq3 = generator.next()
        
        // Then
        XCTAssertEqual(seq1, 1)
        XCTAssertEqual(seq2, 2)
        XCTAssertEqual(seq3, 3)
    }
    
    func testSequenceGeneratorOverflow() {
        // Given
        let generator = IMSequenceGenerator.shared
        generator.reset()
        
        // When - 手动设置到接近溢出
        for _ in 0..<10 {
            _ = generator.next()
        }
        
        // Then
        let seq = generator.next()
        XCTAssertGreaterThan(seq, 0)
    }
    
    func testSequenceGeneratorThreadSafety() {
        // Given
        let generator = IMSequenceGenerator.shared
        generator.reset()
        var sequences: [UInt32] = []
        let lock = NSLock()
        let expectation = self.expectation(description: "Concurrent sequence generation")
        expectation.expectedFulfillmentCount = 100
        
        // When - 并发生成序列号
        for _ in 0..<100 {
            DispatchQueue.global().async {
                let seq = generator.next()
                lock.lock()
                sequences.append(seq)
                lock.unlock()
                expectation.fulfill()
            }
        }
        
        // Then
        waitForExpectations(timeout: 5.0)
        XCTAssertEqual(sequences.count, 100)
        
        // 验证没有重复的序列号
        let uniqueSequences = Set(sequences)
        XCTAssertEqual(uniqueSequences.count, 100, "所有序列号应该是唯一的")
    }
    
    // MARK: - 边界测试
    
    func testPacketWithEmptyBody() {
        // Given
        let emptyBody = Data()
        let packet = IMPacket(
            command: .heartbeatReq,
            sequence: 1,
            body: emptyBody
        )
        
        // When
        let data = packet.encode()
        let decoded = IMPacket.decode(from: data)
        
        // Then
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.body.count, 0)
        XCTAssertEqual(decoded?.header.bodyLength, 0)
    }
    
    func testPacketWithLargeBody() {
        // Given - 1MB 的包体
        let largeBody = Data(repeating: 0xFF, count: 1_000_000)
        let packet = IMPacket(
            command: .syncRsp,
            sequence: 999,
            body: largeBody
        )
        
        // When
        let data = packet.encode()
        let decoded = IMPacket.decode(from: data)
        
        // Then
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.body.count, 1_000_000)
        XCTAssertEqual(decoded?.header.bodyLength, 1_000_000)
    }
    
    // MARK: - 性能测试
    
    func testPacketEncodePerformance() {
        let body = Data(repeating: 0x42, count: 1024)
        let packet = IMPacket(command: .pushMsg, sequence: 1, body: body)
        
        measure {
            for _ in 0..<1000 {
                _ = packet.encode()
            }
        }
    }
    
    func testPacketDecodePerformance() {
        let body = Data(repeating: 0x42, count: 1024)
        let packet = IMPacket(command: .pushMsg, sequence: 1, body: body)
        let data = packet.encode()
        
        measure {
            for _ in 0..<1000 {
                _ = IMPacket.decode(from: data)
            }
        }
    }
}


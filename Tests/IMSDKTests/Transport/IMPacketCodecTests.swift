//
//  IMPacketCodecTests.swift
//  IMSDKTests
//
//  Created by IMSDK on 2025-01-26.
//

import XCTest
@testable import IMSDK

/// 测试粘包/拆包处理器
final class IMPacketCodecTests: XCTestCase {
    
    var codec: IMPacketCodec!
    
    override func setUp() {
        super.setUp()
        codec = IMPacketCodec()
    }
    
    override func tearDown() {
        codec = nil
        super.tearDown()
    }
    
    // MARK: - 基础编解码测试
    
    func testEncodePacket() {
        // Given
        let body = "Test".data(using: .utf8)!
        
        // When
        let data = codec.encode(command: .heartbeatReq, sequence: 1, body: body)
        
        // Then
        XCTAssertEqual(data.count, kPacketHeaderSize + body.count)
    }
    
    func testDecodeCompletePacket() throws {
        // Given - 一个完整的包
        let body = "Hello".data(using: .utf8)!
        let packetData = codec.encode(command: .pushMsg, sequence: 100, body: body)
        
        // When
        let packets = try codec.decode(data: packetData)
        
        // Then
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].header.command, .pushMsg)
        XCTAssertEqual(packets[0].header.sequence, 100)
        XCTAssertEqual(packets[0].body, body)
    }
    
    // MARK: - 粘包测试
    
    func testDecodeStickingPackets() throws {
        // Given - 三个包粘在一起
        let body1 = "Packet1".data(using: .utf8)!
        let body2 = "Packet2".data(using: .utf8)!
        let body3 = "Packet3".data(using: .utf8)!
        
        let packet1 = codec.encode(command: .pushMsg, sequence: 1, body: body1)
        let packet2 = codec.encode(command: .pushMsg, sequence: 2, body: body2)
        let packet3 = codec.encode(command: .pushMsg, sequence: 3, body: body3)
        
        var stickedData = Data()
        stickedData.append(packet1)
        stickedData.append(packet2)
        stickedData.append(packet3)
        
        // When
        let packets = try codec.decode(data: stickedData)
        
        // Then
        XCTAssertEqual(packets.count, 3, "应该解析出 3 个包")
        XCTAssertEqual(packets[0].header.sequence, 1)
        XCTAssertEqual(packets[1].header.sequence, 2)
        XCTAssertEqual(packets[2].header.sequence, 3)
        XCTAssertEqual(packets[0].body, body1)
        XCTAssertEqual(packets[1].body, body2)
        XCTAssertEqual(packets[2].body, body3)
    }
    
    // MARK: - 拆包测试
    
    func testDecodeFragmentedPacket() throws {
        // Given - 一个包被拆成两部分
        let body = "FragmentedPacket".data(using: .utf8)!
        let fullPacket = codec.encode(command: .syncReq, sequence: 999, body: body)
        
        let splitPoint = 20  // 在包头之后拆分
        let part1 = fullPacket.prefix(splitPoint)
        let part2 = fullPacket.suffix(from: splitPoint)
        
        // When - 第一部分（不完整）
        let packets1 = try codec.decode(data: part1)
        
        // Then
        XCTAssertEqual(packets1.count, 0, "数据不完整，应该返回空数组")
        
        // When - 第二部分（补全）
        let packets2 = try codec.decode(data: part2)
        
        // Then
        XCTAssertEqual(packets2.count, 1, "数据补全后应该解析出 1 个包")
        XCTAssertEqual(packets2[0].header.sequence, 999)
        XCTAssertEqual(packets2[0].body, body)
    }
    
    func testDecodeFragmentedInHeader() throws {
        // Given - 在包头中间拆分
        let body = "Test".data(using: .utf8)!
        let fullPacket = codec.encode(command: .authReq, sequence: 50, body: body)
        
        let part1 = fullPacket.prefix(10)  // 只有 10 字节（包头不完整）
        let part2 = fullPacket.suffix(from: 10)
        
        // When
        let packets1 = try codec.decode(data: part1)
        XCTAssertEqual(packets1.count, 0)
        
        let packets2 = try codec.decode(data: part2)
        
        // Then
        XCTAssertEqual(packets2.count, 1)
        XCTAssertEqual(packets2[0].body, body)
    }
    
    // MARK: - 混合场景测试
    
    func testDecodeMixedStickingAndFragmentation() throws {
        // Given - 完整包 + 不完整包
        let body1 = "Complete".data(using: .utf8)!
        let body2 = "Incomplete".data(using: .utf8)!
        
        let packet1 = codec.encode(command: .pushMsg, sequence: 1, body: body1)
        let packet2 = codec.encode(command: .pushMsg, sequence: 2, body: body2)
        
        var data = Data()
        data.append(packet1)  // 完整的包
        data.append(packet2.prefix(20))  // 不完整的包
        
        // When - 第一次解码
        let packets1 = try codec.decode(data: data)
        
        // Then
        XCTAssertEqual(packets1.count, 1, "应该解析出 1 个完整的包")
        XCTAssertEqual(packets1[0].body, body1)
        
        // When - 第二次解码（补全数据）
        let remainingData = packet2.suffix(from: 20)
        let packets2 = try codec.decode(data: remainingData)
        
        // Then
        XCTAssertEqual(packets2.count, 1)
        XCTAssertEqual(packets2[0].body, body2)
    }
    
    // MARK: - 错误处理测试
    
    func testDecodeWithInvalidHeader() {
        // Given - 错误的魔数
        var invalidData = Data(repeating: 0xFF, count: 100)
        invalidData[0] = 0x00  // 错误的魔数
        invalidData[1] = 0x00
        
        // When & Then
        XCTAssertThrowsError(try codec.decode(data: invalidData)) { error in
            XCTAssertTrue(error is IMPacketCodecError)
        }
    }
    
    func testDecodeWithBufferOverflow() {
        // Given - 超大的数据（模拟攻击）
        let hugeData = Data(repeating: 0xFF, count: 20_000_000)  // 20MB
        
        // When & Then
        XCTAssertThrowsError(try codec.decode(data: hugeData)) { error in
            guard case IMPacketCodecError.bufferOverflow = error else {
                XCTFail("应该抛出 bufferOverflow 错误")
                return
            }
        }
    }
    
    func testDecodeWithPacketTooLarge() {
        // Given - 声称包体过大（10MB）
        var header = IMPacketHeader(
            command: .syncRsp,
            sequence: 1,
            bodyLength: 10_000_000  // 10MB
        )
        let headerData = header.encode()
        
        // When & Then
        XCTAssertThrowsError(try codec.decode(data: headerData)) { error in
            guard case IMPacketCodecError.packetTooLarge = error else {
                XCTFail("应该抛出 packetTooLarge 错误")
                return
            }
        }
    }
    
    // MARK: - 缓冲区管理测试
    
    func testClearBuffer() throws {
        // Given
        let body = "Test".data(using: .utf8)!
        let packet = codec.encode(command: .pushMsg, sequence: 1, body: body)
        let part1 = packet.prefix(10)
        
        _ = try codec.decode(data: part1)  // 缓冲区有数据
        
        // When
        codec.clearBuffer()
        
        // Then
        XCTAssertEqual(codec.stats.currentBufferSize, 0)
    }
    
    func testBufferSnapshot() throws {
        // Given
        let body = "Test".data(using: .utf8)!
        let packet = codec.encode(command: .pushMsg, sequence: 1, body: body)
        let part1 = packet.prefix(10)
        
        _ = try codec.decode(data: part1)
        
        // When
        let snapshot = codec.bufferSnapshot()
        
        // Then
        XCTAssertEqual(snapshot.count, 10)
    }
    
    // MARK: - 统计信息测试
    
    func testStatistics() throws {
        // Given
        codec.resetStats()
        let body = "Test".data(using: .utf8)!
        
        // When
        _ = codec.encode(command: .pushMsg, sequence: 1, body: body)
        _ = codec.encode(command: .pushMsg, sequence: 2, body: body)
        
        let packet = codec.encode(command: .pushMsg, sequence: 3, body: body)
        _ = try codec.decode(data: packet)
        
        // Then
        XCTAssertEqual(codec.stats.totalPacketsEncoded, 3)
        XCTAssertEqual(codec.stats.totalPacketsDecoded, 1)
        XCTAssertGreaterThan(codec.stats.totalBytesReceived, 0)
    }
    
    // MARK: - 并发测试
    
    func testConcurrentEncode() {
        // Given
        let expectation = self.expectation(description: "Concurrent encode")
        expectation.expectedFulfillmentCount = 100
        let body = "Test".data(using: .utf8)!
        
        // When
        for i in 0..<100 {
            DispatchQueue.global().async {
                _ = self.codec.encode(command: .pushMsg, sequence: UInt32(i), body: body)
                expectation.fulfill()
            }
        }
        
        // Then
        waitForExpectations(timeout: 5.0)
        XCTAssertEqual(codec.stats.totalPacketsEncoded, 100)
    }
    
    // MARK: - 性能测试
    
    func testDecodePerformance() throws {
        // Given - 100 个粘在一起的包
        var data = Data()
        for i in 0..<100 {
            let body = "Message\(i)".data(using: .utf8)!
            data.append(codec.encode(command: .pushMsg, sequence: UInt32(i), body: body))
        }
        
        // When & Then
        measure {
            codec.clearBuffer()
            _ = try? self.codec.decode(data: data)
        }
    }
    
    func testFragmentedPacketPerformance() throws {
        // Given
        let body = Data(repeating: 0x42, count: 1024)
        let packet = codec.encode(command: .pushMsg, sequence: 1, body: body)
        
        // When & Then - 模拟网络拆包（每次接收 100 字节）
        measure {
            self.codec.clearBuffer()
            for i in stride(from: 0, to: packet.count, by: 100) {
                let end = min(i + 100, packet.count)
                let chunk = packet.subdata(in: i..<end)
                _ = try? self.codec.decode(data: chunk)
            }
        }
    }
}


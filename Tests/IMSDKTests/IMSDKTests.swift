/// IMSDKTests - IMSDK 单元测试
/// 测试 SDK 的核心功能

import XCTest
@testable import IMSDK

final class IMSDKTests: XCTestCase {
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        // 在每个测试方法之前调用
    }
    
    override func tearDownWithError() throws {
        // 在每个测试方法之后调用
    }
    
    // MARK: - Logger Tests
    
    func testLoggerInitialization() throws {
        let logger = IMLogger.shared
        XCTAssertNotNil(logger)
        
        // 测试日志输出
        logger.info("This is a test log")
        logger.debug("Debug message")
        logger.error("Error message")
    }
    
    func testLoggerConfiguration() throws {
        let config = IMLoggerConfig(
            minimumLevel: .debug,
            enableConsole: true,
            enableFileOutput: false
        )
        
        IMLogger.shared.configure(config)
        
        IMLogger.shared.debug("Debug should be visible")
        IMLogger.shared.verbose("Verbose should not be visible")
    }
    
    // MARK: - Crypto Tests
    
    func testAESEncryption() throws {
        let crypto = IMCrypto.shared
        let originalData = "Hello, World!".data(using: .utf8)!
        let key = crypto.generateRandomKey()
        let iv = crypto.generateRandomIV()
        
        // 加密
        let encrypted = try crypto.aesEncrypt(data: originalData, key: key, iv: iv)
        XCTAssertNotEqual(encrypted, originalData)
        
        // 解密
        let decrypted = try crypto.aesDecrypt(data: encrypted, key: key, iv: iv)
        XCTAssertEqual(decrypted, originalData)
        
        let decryptedString = String(data: decrypted, encoding: .utf8)
        XCTAssertEqual(decryptedString, "Hello, World!")
    }
    
    func testPasswordEncryption() throws {
        let crypto = IMCrypto.shared
        let originalData = "Secret message".data(using: .utf8)!
        let password = "myPassword123"
        
        // 加密
        let (encrypted, salt, iv) = try crypto.encryptWithPassword(data: originalData, password: password)
        
        // 解密
        let decrypted = try crypto.decryptWithPassword(data: encrypted, password: password, salt: salt, iv: iv)
        
        let decryptedString = String(data: decrypted, encoding: .utf8)
        XCTAssertEqual(decryptedString, "Secret message")
    }
    
    func testHashFunctions() throws {
        let crypto = IMCrypto.shared
        
        // SHA256
        let sha256Hash = crypto.sha256(string: "test")
        XCTAssertFalse(sha256Hash.isEmpty)
        XCTAssertEqual(sha256Hash.count, 64) // SHA256 = 32 bytes = 64 hex characters
        
        // MD5
        let md5Hash = crypto.md5(string: "test")
        XCTAssertFalse(md5Hash.isEmpty)
        XCTAssertEqual(md5Hash.count, 32) // MD5 = 16 bytes = 32 hex characters
    }
    
    // MARK: - Utils Tests
    
    func testUUIDGeneration() throws {
        let uuid1 = IMUtils.generateUUID()
        let uuid2 = IMUtils.generateUUID()
        
        XCTAssertNotEqual(uuid1, uuid2)
        XCTAssertFalse(uuid1.isEmpty)
    }
    
    func testMessageIDGeneration() throws {
        let msgID1 = IMUtils.generateMessageID()
        let msgID2 = IMUtils.generateMessageID()
        
        XCTAssertNotEqual(msgID1, msgID2)
        XCTAssertFalse(msgID1.isEmpty)
    }
    
    func testTimestamp() throws {
        let timestamp = IMUtils.currentTimeMillis()
        XCTAssertGreaterThan(timestamp, 0)
        
        let formatted = IMUtils.formatTimestamp(timestamp)
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testJSONConversion() throws {
        let dict: [String: Any] = [
            "name": "John",
            "age": 30,
            "active": true
        ]
        
        let json = IMUtils.dictToJSON(dict)
        XCTAssertNotNil(json)
        
        let parsedDict = IMUtils.jsonToDict(json!)
        XCTAssertNotNil(parsedDict)
        XCTAssertEqual(parsedDict?["name"] as? String, "John")
        XCTAssertEqual(parsedDict?["age"] as? Int, 30)
    }
    
    func testFileSizeFormatting() throws {
        XCTAssertEqual(IMUtils.formatFileSize(1024), "1.00 KB")
        XCTAssertEqual(IMUtils.formatFileSize(1024 * 1024), "1.00 MB")
        XCTAssertEqual(IMUtils.formatFileSize(1024 * 1024 * 1024), "1.00 GB")
    }
    
    func testValidation() throws {
        // URL 验证
        XCTAssertTrue(IMUtils.isValidURL("https://example.com"))
        XCTAssertTrue(IMUtils.isValidURL("http://example.com/path"))
        XCTAssertFalse(IMUtils.isValidURL("not-a-url"))
        
        // 邮箱验证
        XCTAssertTrue(IMUtils.isValidEmail("test@example.com"))
        XCTAssertTrue(IMUtils.isValidEmail("user.name+tag@example.co.uk"))
        XCTAssertFalse(IMUtils.isValidEmail("invalid-email"))
        
        // 手机号验证（中国大陆）
        XCTAssertTrue(IMUtils.isValidPhoneNumber("13812345678"))
        XCTAssertTrue(IMUtils.isValidPhoneNumber("18900000000"))
        XCTAssertFalse(IMUtils.isValidPhoneNumber("12345678901"))
    }
    
    // MARK: - Cache Tests
    
    func testMemoryCache() throws {
        let cache = IMMemoryCache<String>(countLimit: 10, costLimit: 1000)
        
        // 存储
        cache.set("value1", forKey: "key1")
        cache.set("value2", forKey: "key2")
        
        // 获取
        XCTAssertEqual(cache.get(forKey: "key1"), "value1")
        XCTAssertEqual(cache.get(forKey: "key2"), "value2")
        XCTAssertNil(cache.get(forKey: "key3"))
        
        // 删除
        cache.remove(forKey: "key1")
        XCTAssertNil(cache.get(forKey: "key1"))
        
        // 包含检查
        XCTAssertTrue(cache.contains(forKey: "key2"))
        XCTAssertFalse(cache.contains(forKey: "key1"))
    }
    
    func testMemoryCacheExpiration() throws {
        let cache = IMMemoryCache<String>()
        
        let expirationDate = Date().addingTimeInterval(1) // 1秒后过期
        cache.set("value", forKey: "key", expiration: expirationDate)
        
        // 立即获取应该成功
        XCTAssertEqual(cache.get(forKey: "key"), "value")
        
        // 等待过期
        let expectation = XCTestExpectation(description: "Wait for expiration")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            // 过期后获取应该失败
            XCTAssertNil(cache.get(forKey: "key"))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafeProperty() throws {
        @ThreadSafe var counter: Int = 0
        
        let expectation = XCTestExpectation(description: "Concurrent increments")
        let iterations = 1000
        var completed = 0
        
        for _ in 0..<iterations {
            DispatchQueue.global().async {
                counter += 1
                
                DispatchQueue.main.async {
                    completed += 1
                    if completed == iterations {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(counter, iterations)
    }
    
    // MARK: - Debouncer Tests
    
    func testDebouncer() throws {
        let debouncer = Debouncer(delay: 0.5)
        var executionCount = 0
        
        let expectation = XCTestExpectation(description: "Debounce execution")
        
        // 快速调用多次
        for _ in 0..<10 {
            debouncer.debounce {
                executionCount += 1
            }
        }
        
        // 等待执行
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            // 应该只执行一次
            XCTAssertEqual(executionCount, 1)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Protocol Tests
    
    func testPacketEncoding() throws {
        let packet = IMPacket(type: .message, seq: 123)
        
        // 编码
        let encoded = try packet.encode()
        XCTAssertFalse(encoded.isEmpty)
        
        // 解码
        let decoded = try IMPacket.decode(from: encoded)
        XCTAssertEqual(decoded.type, packet.type)
        XCTAssertEqual(decoded.seq, packet.seq)
    }
    
    // MARK: - Performance Tests
    
    func testEncryptionPerformance() throws {
        let crypto = IMCrypto.shared
        let data = String(repeating: "A", count: 10000).data(using: .utf8)!
        let key = crypto.generateRandomKey()
        let iv = crypto.generateRandomIV()
        
        measure {
            _ = try? crypto.aesEncrypt(data: data, key: key, iv: iv)
        }
    }
    
    func testHashPerformance() throws {
        let crypto = IMCrypto.shared
        let text = String(repeating: "Hello World", count: 1000)
        
        measure {
            _ = crypto.sha256(string: text)
        }
    }
    
    func testCachePerformance() throws {
        let cache = IMMemoryCache<String>(countLimit: 1000)
        
        measure {
            for i in 0..<1000 {
                cache.set("value\(i)", forKey: "key\(i)")
            }
        }
    }
}


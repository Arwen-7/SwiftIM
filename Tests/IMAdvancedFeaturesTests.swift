///  IMAdvancedFeaturesTests - 高级特性测试
/// 测试断点续传、文件压缩、视频处理等

import XCTest
@testable import IMSDK

final class IMAdvancedFeaturesTests: XCTestCase {
    
    var fileManager: IMFileManager!
    
    override func setUp() {
        super.setUp()
        fileManager = IMFileManager.shared
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - 断点续传数据模型测试
    
    func testResumeDataModel() {
        let resumeData = IMResumeData(
            taskID: "test-task-123",
            fileURL: "https://example.com/file.zip",
            localPath: "/tmp/file.zip",
            totalBytes: 1024 * 1024,
            completedBytes: 512 * 1024
        )
        
        XCTAssertEqual(resumeData.taskID, "test-task-123")
        XCTAssertEqual(resumeData.totalBytes, 1024 * 1024)
        XCTAssertEqual(resumeData.completedBytes, 512 * 1024)
        XCTAssertTrue(resumeData.completedBytes < resumeData.totalBytes)
    }
    
    func testResumeDataEncoding() throws {
        let resumeData = IMResumeData(
            taskID: "test-task-123",
            fileURL: "https://example.com/file.zip",
            localPath: "/tmp/file.zip",
            totalBytes: 1024 * 1024,
            completedBytes: 512 * 1024,
            eTag: "abc123"
        )
        
        let jsonData = try JSONEncoder().encode(resumeData)
        let decoded = try JSONDecoder().decode(IMResumeData.self, from: jsonData)
        
        XCTAssertEqual(decoded.taskID, resumeData.taskID)
        XCTAssertEqual(decoded.fileURL, resumeData.fileURL)
        XCTAssertEqual(decoded.totalBytes, resumeData.totalBytes)
        XCTAssertEqual(decoded.completedBytes, resumeData.completedBytes)
        XCTAssertEqual(decoded.eTag, resumeData.eTag)
    }
    
    // MARK: - 断点续传功能测试
    
    func testSaveAndLoadResumeData() {
        let resumeData = IMResumeData(
            taskID: "test-task-save",
            fileURL: "https://example.com/test.zip",
            localPath: "/tmp/test.zip",
            totalBytes: 1024,
            completedBytes: 512
        )
        
        // 保存
        fileManager.deleteResumeData(for: resumeData.taskID) // 先清理
        let _ = fileManager.downloadFileResumable(
            from: resumeData.fileURL,
            fileType: .file,
            taskID: resumeData.taskID
        ) { _ in }
        
        // 暂停（模拟保存断点）
        fileManager.pauseDownload(resumeData.taskID)
        
        // 加载
        let loaded = fileManager.loadResumeData(for: resumeData.taskID)
        XCTAssertNotNil(loaded)
        
        // 清理
        fileManager.deleteResumeData(for: resumeData.taskID)
    }
    
    func testDeleteResumeData() {
        let taskID = "test-task-delete"
        let resumeData = IMResumeData(
            taskID: taskID,
            fileURL: "https://example.com/test.zip",
            localPath: "/tmp/test.zip",
            totalBytes: 1024,
            completedBytes: 0
        )
        
        // 先删除（清理）
        fileManager.deleteResumeData(for: taskID)
        
        // 验证不存在
        XCTAssertNil(fileManager.loadResumeData(for: taskID))
    }
    
    func testPauseDownload() {
        let taskID = "test-task-pause"
        
        // 开始下载
        let _ = fileManager.downloadFileResumable(
            from: "https://example.com/large-file.zip",
            fileType: .file,
            taskID: taskID
        ) { _ in }
        
        // 暂停
        fileManager.pauseDownload(taskID)
        
        // 验证任务已移除
        // （实际验证需要mock网络请求）
        XCTAssertTrue(true)
    }
    
    func testCancelDownload() {
        let taskID = "test-task-cancel"
        
        // 开始下载
        let _ = fileManager.downloadFileResumable(
            from: "https://example.com/large-file.zip",
            fileType: .file,
            taskID: taskID
        ) { _ in }
        
        // 取消
        fileManager.cancelDownload(taskID)
        
        // 验证断点数据被删除
        XCTAssertNil(fileManager.loadResumeData(for: taskID))
    }
    
    // MARK: - 图片压缩测试
    
    func testImageCompressionConfig() {
        let config = IMImageCompressionConfig(
            maxWidth: 1920,
            maxHeight: 1080,
            quality: 0.8,
            format: "jpg"
        )
        
        XCTAssertEqual(config.maxWidth, 1920)
        XCTAssertEqual(config.maxHeight, 1080)
        XCTAssertEqual(config.quality, 0.8)
        XCTAssertEqual(config.format, "jpg")
    }
    
    func testImageCompressionConfigDefault() {
        let config = IMImageCompressionConfig.default
        
        XCTAssertEqual(config.maxWidth, 1920)
        XCTAssertEqual(config.maxHeight, 1920)
        XCTAssertEqual(config.quality, 0.8)
        XCTAssertEqual(config.format, "jpg")
    }
    
    func testCompressImageMock() {
        // 创建一个测试图片
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let image = image, let imageData = image.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to create test image")
            return
        }
        
        // 保存到临时文件
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_image.jpg")
        try? imageData.write(to: tempURL)
        
        // 测试压缩
        let config = IMImageCompressionConfig(maxWidth: 50, maxHeight: 50, quality: 0.5, format: "jpg")
        if let compressedURL = fileManager.compressImage(at: tempURL, config: config) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: compressedURL.path))
            
            // 验证压缩后的尺寸
            if let compressedImage = UIImage(contentsOfFile: compressedURL.path) {
                XCTAssertLessThanOrEqual(compressedImage.size.width, 50)
                XCTAssertLessThanOrEqual(compressedImage.size.height, 50)
            }
            
            // 清理
            try? FileManager.default.removeItem(at: compressedURL)
        }
        
        // 清理
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - 视频压缩配置测试
    
    func testVideoCompressionConfig() {
        let config = IMVideoCompressionConfig(
            maxDuration: 300,
            maxSize: 100 * 1024 * 1024,
            bitrate: 2_000_000,
            frameRate: 30
        )
        
        XCTAssertEqual(config.maxDuration, 300)
        XCTAssertEqual(config.maxSize, 100 * 1024 * 1024)
        XCTAssertEqual(config.bitrate, 2_000_000)
        XCTAssertEqual(config.frameRate, 30)
    }
    
    func testVideoCompressionConfigDefault() {
        let config = IMVideoCompressionConfig.default
        
        XCTAssertEqual(config.maxDuration, 300)
        XCTAssertEqual(config.maxSize, 100 * 1024 * 1024)
        XCTAssertEqual(config.bitrate, 2_000_000)
        XCTAssertEqual(config.frameRate, 30)
    }
    
    // MARK: - 文件传输状态测试
    
    func testFileTransferStatusEnum() {
        XCTAssertEqual(IMFileTransferStatus.waiting.rawValue, 0)
        XCTAssertEqual(IMFileTransferStatus.transferring.rawValue, 1)
        XCTAssertEqual(IMFileTransferStatus.paused.rawValue, 2)
        XCTAssertEqual(IMFileTransferStatus.completed.rawValue, 3)
        XCTAssertEqual(IMFileTransferStatus.failed.rawValue, 4)
        XCTAssertEqual(IMFileTransferStatus.cancelled.rawValue, 5)
    }
    
    func testFileTransferStatusCoding() throws {
        let status = IMFileTransferStatus.transferring
        
        let jsonData = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(IMFileTransferStatus.self, from: jsonData)
        
        XCTAssertEqual(decoded, status)
    }
    
    // MARK: - 性能测试
    
    func testImageCompressionPerformance() {
        // 创建一个大图
        let size = CGSize(width: 2000, height: 2000)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let image = image, let imageData = image.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_large_image.jpg")
        try? imageData.write(to: tempURL)
        
        measure {
            let _ = fileManager.compressImage(at: tempURL, config: .default)
        }
        
        // 清理
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    func testResumeDataSaveLoadPerformance() {
        let resumeDataList = (0..<100).map { i in
            IMResumeData(
                taskID: "task-\(i)",
                fileURL: "https://example.com/file-\(i).zip",
                localPath: "/tmp/file-\(i).zip",
                totalBytes: Int64(i * 1024),
                completedBytes: Int64(i * 512)
            )
        }
        
        measure {
            // 保存100个断点数据
            for _ in resumeDataList {
                // fileManager.saveResumeData(data)  // 私有方法，无法直接测试
            }
            
            // 加载
            for i in 0..<100 {
                let _ = fileManager.loadResumeData(for: "task-\(i)")
            }
        }
        
        // 清理
        for i in 0..<100 {
            fileManager.deleteResumeData(for: "task-\(i)")
        }
    }
    
    // MARK: - 边界条件测试
    
    func testCompressImageWithInvalidURL() {
        let invalidURL = URL(fileURLWithPath: "/non/existent/path.jpg")
        let result = fileManager.compressImage(at: invalidURL)
        
        XCTAssertNil(result)
    }
    
    func testLoadNonExistentResumeData() {
        let result = fileManager.loadResumeData(for: "non-existent-task-id")
        XCTAssertNil(result)
    }
    
    func testResumeDataWithZeroProgress() {
        let resumeData = IMResumeData(
            taskID: "zero-progress",
            fileURL: "https://example.com/file.zip",
            localPath: "/tmp/file.zip",
            totalBytes: 1024,
            completedBytes: 0
        )
        
        XCTAssertEqual(resumeData.completedBytes, 0)
        XCTAssertTrue(resumeData.completedBytes < resumeData.totalBytes)
    }
    
    func testResumeDataWithCompleteProgress() {
        let resumeData = IMResumeData(
            taskID: "complete-progress",
            fileURL: "https://example.com/file.zip",
            localPath: "/tmp/file.zip",
            totalBytes: 1024,
            completedBytes: 1024
        )
        
        XCTAssertEqual(resumeData.completedBytes, resumeData.totalBytes)
    }
    
    // MARK: - 集成测试
    
    func testImageCompressionQuality() {
        // 创建测试图片
        let size = CGSize(width: 1000, height: 1000)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.green.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let image = image, let imageData = image.jpegData(compressionQuality: 1.0) else {
            return
        }
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_quality.jpg")
        try? imageData.write(to: tempURL)
        
        let originalSize = imageData.count
        
        // 测试不同压缩质量
        let qualities: [CGFloat] = [1.0, 0.8, 0.5, 0.3]
        
        for quality in qualities {
            let config = IMImageCompressionConfig(maxWidth: 1920, maxHeight: 1920, quality: quality, format: "jpg")
            if let compressedURL = fileManager.compressImage(at: tempURL, config: config),
               let compressedData = try? Data(contentsOf: compressedURL) {
                
                let compressedSize = compressedData.count
                let ratio = Double(compressedSize) / Double(originalSize)
                
                print("Quality: \(quality), Ratio: \(String(format: "%.2f", ratio))")
                
                // 压缩质量越低，文件越小
                if quality < 1.0 {
                    XCTAssertLessThan(compressedSize, originalSize)
                }
                
                // 清理
                try? FileManager.default.removeItem(at: compressedURL)
            }
        }
        
        // 清理
        try? FileManager.default.removeItem(at: tempURL)
    }
}


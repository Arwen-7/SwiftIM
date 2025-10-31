/// IMRichMediaTests - 富媒体消息测试
/// 测试图片、语音、视频、文件消息的发送和下载

import XCTest
@testable import IMSDK

final class IMRichMediaTests: XCTestCase {
    
    var fileManager: IMFileManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = IMFileManager.shared
        
        // 配置上传下载 URL（测试环境）
        fileManager.uploadBaseURL = "https://test-api.example.com"
        fileManager.downloadBaseURL = "https://test-cdn.example.com"
    }
    
    override func tearDownWithError() throws {
        // 清理测试文件
        try? fileManager.clearCache()
        try super.tearDownWithError()
    }
    
    // MARK: - 数据模型测试
    
    /// 测试 1：图片消息内容编解码
    func testImageMessageContentCoding() throws {
        // Given
        var imageContent = IMImageMessageContent()
        imageContent.url = "https://example.com/image.jpg"
        imageContent.thumbnailUrl = "https://example.com/thumb.jpg"
        imageContent.width = 1920
        imageContent.height = 1080
        imageContent.size = 512000
        imageContent.format = "jpg"
        
        // When: 编码
        let jsonData = try JSONEncoder().encode(imageContent)
        
        // Then: 解码
        let decoded = try JSONDecoder().decode(IMImageMessageContent.self, from: jsonData)
        XCTAssertEqual(decoded.url, imageContent.url)
        XCTAssertEqual(decoded.width, imageContent.width)
        XCTAssertEqual(decoded.height, imageContent.height)
        XCTAssertEqual(decoded.size, imageContent.size)
    }
    
    /// 测试 2：语音消息内容编解码
    func testAudioMessageContentCoding() throws {
        var audioContent = IMAudioMessageContent()
        audioContent.url = "https://example.com/audio.aac"
        audioContent.duration = 60
        audioContent.size = 102400
        audioContent.format = "aac"
        
        let jsonData = try JSONEncoder().encode(audioContent)
        let decoded = try JSONDecoder().decode(IMAudioMessageContent.self, from: jsonData)
        
        XCTAssertEqual(decoded.url, audioContent.url)
        XCTAssertEqual(decoded.duration, audioContent.duration)
        XCTAssertEqual(decoded.size, audioContent.size)
    }
    
    /// 测试 3：视频消息内容编解码
    func testVideoMessageContentCoding() throws {
        var videoContent = IMVideoMessageContent()
        videoContent.url = "https://example.com/video.mp4"
        videoContent.thumbnailUrl = "https://example.com/cover.jpg"
        videoContent.duration = 120
        videoContent.width = 1920
        videoContent.height = 1080
        videoContent.size = 10240000
        videoContent.format = "mp4"
        
        let jsonData = try JSONEncoder().encode(videoContent)
        let decoded = try JSONDecoder().decode(IMVideoMessageContent.self, from: jsonData)
        
        XCTAssertEqual(decoded.url, videoContent.url)
        XCTAssertEqual(decoded.duration, videoContent.duration)
        XCTAssertEqual(decoded.format, videoContent.format)
    }
    
    /// 测试 4：文件消息内容编解码
    func testFileMessageContentCoding() throws {
        var fileContent = IMFileMessageContent()
        fileContent.url = "https://example.com/document.pdf"
        fileContent.fileName = "document.pdf"
        fileContent.size = 2048000
        fileContent.format = "pdf"
        
        let jsonData = try JSONEncoder().encode(fileContent)
        let decoded = try JSONDecoder().decode(IMFileMessageContent.self, from: jsonData)
        
        XCTAssertEqual(decoded.url, fileContent.url)
        XCTAssertEqual(decoded.fileName, fileContent.fileName)
        XCTAssertEqual(decoded.size, fileContent.size)
    }
    
    // MARK: - 文件管理器测试
    
    /// 测试 5：文件目录创建
    func testFileDirectoryCreation() {
        let imageDir = fileManager.getImageDirectory()
        let audioDir = fileManager.getAudioDirectory()
        let videoDir = fileManager.getVideoDirectory()
        let fileDir = fileManager.getFileDirectory()
        let thumbDir = fileManager.getThumbnailDirectory()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbDir.path))
    }
    
    /// 测试 6：文件大小获取
    func testGetFileSize() throws {
        // Given: 创建测试文件
        let testData = Data(count: 1024) // 1KB
        let testURL = fileManager.getFileDirectory().appendingPathComponent("test_size.txt")
        try testData.write(to: testURL)
        
        // When: 获取文件大小
        let fileSize = fileManager.getFileSize(at: testURL)
        
        // Then
        XCTAssertEqual(fileSize, 1024)
        
        // Cleanup
        try? fileManager.deleteFile(at: testURL)
    }
    
    /// 测试 7：文件删除
    func testDeleteFile() throws {
        // Given: 创建测试文件
        let testData = Data(count: 100)
        let testURL = fileManager.getFileDirectory().appendingPathComponent("test_delete.txt")
        try testData.write(to: testURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
        
        // When: 删除文件
        try fileManager.deleteFile(at: testURL)
        
        // Then
        XCTAssertFalse(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    /// 测试 8：缓存大小计算
    func testGetCacheSize() throws {
        // Given: 创建多个测试文件
        let file1Data = Data(count: 1024) // 1KB
        let file2Data = Data(count: 2048) // 2KB
        
        let file1URL = fileManager.getFileDirectory().appendingPathComponent("test1.txt")
        let file2URL = fileManager.getFileDirectory().appendingPathComponent("test2.txt")
        
        try file1Data.write(to: file1URL)
        try file2Data.write(to: file2URL)
        
        // When: 计算缓存大小
        let cacheSize = fileManager.getCacheSize()
        
        // Then: 应该至少包含这两个文件
        XCTAssertGreaterThanOrEqual(cacheSize, 3072) // 3KB
        
        // Cleanup
        try? fileManager.deleteFile(at: file1URL)
        try? fileManager.deleteFile(at: file2URL)
    }
    
    /// 测试 9：清理缓存
    func testClearCache() throws {
        // Given: 创建测试文件
        let testData = Data(count: 1024)
        let testURL = fileManager.getFileDirectory().appendingPathComponent("test_clear.txt")
        try testData.write(to: testURL)
        
        // When: 清理缓存
        try fileManager.clearCache()
        
        // Then: 文件应该被删除
        XCTAssertFalse(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    // MARK: - 图片处理测试
    
    /// 测试 10：缩略图生成
    func testGenerateThumbnail() throws {
        // Given: 创建一个测试图片
        let size = CGSize(width: 800, height: 600)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        // 保存原图
        let imageData = image.jpegData(compressionQuality: 1.0)!
        let imageURL = fileManager.getImageDirectory().appendingPathComponent("test_original.jpg")
        try imageData.write(to: imageURL)
        
        // When: 生成缩略图
        let thumbnailURL = fileManager.generateThumbnail(for: imageURL)
        
        // Then: 缩略图应该存在
        XCTAssertNotNil(thumbnailURL)
        if let thumbURL = thumbnailURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))
            
            // 验证缩略图尺寸应该小于原图
            let thumbSize = fileManager.getFileSize(at: thumbURL)
            let originalSize = fileManager.getFileSize(at: imageURL)
            XCTAssertLessThan(thumbSize, originalSize)
        }
        
        // Cleanup
        try? fileManager.deleteFile(at: imageURL)
        if let thumbURL = thumbnailURL {
            try? fileManager.deleteFile(at: thumbURL)
        }
    }
    
    // MARK: - 文件传输进度测试
    
    /// 测试 11：文件传输进度初始化
    func testFileTransferProgress() {
        let progress = IMFileTransferProgress(
            taskID: "task_001",
            totalBytes: 1000,
            completedBytes: 500,
            status: .transferring
        )
        
        XCTAssertEqual(progress.taskID, "task_001")
        XCTAssertEqual(progress.totalBytes, 1000)
        XCTAssertEqual(progress.completedBytes, 500)
        XCTAssertEqual(progress.progress, 0.5)
        XCTAssertEqual(progress.status, .transferring)
    }
    
    /// 测试 12：文件传输进度计算
    func testFileTransferProgressCalculation() {
        let progress1 = IMFileTransferProgress(taskID: "t1", totalBytes: 100, completedBytes: 0)
        XCTAssertEqual(progress1.progress, 0.0)
        
        let progress2 = IMFileTransferProgress(taskID: "t2", totalBytes: 100, completedBytes: 50)
        XCTAssertEqual(progress2.progress, 0.5)
        
        let progress3 = IMFileTransferProgress(taskID: "t3", totalBytes: 100, completedBytes: 100)
        XCTAssertEqual(progress3.progress, 1.0)
        
        // 边界：总大小为 0
        let progress4 = IMFileTransferProgress(taskID: "t4", totalBytes: 0, completedBytes: 0)
        XCTAssertEqual(progress4.progress, 0.0)
    }
    
    /// 测试 13：文件上传结果
    func testFileUploadResult() {
        let result = IMFileUploadResult(
            url: "https://example.com/file.jpg",
            fileID: "file_123",
            size: 1024,
            format: "jpg"
        )
        
        XCTAssertEqual(result.url, "https://example.com/file.jpg")
        XCTAssertEqual(result.fileID, "file_123")
        XCTAssertEqual(result.size, 1024)
        XCTAssertEqual(result.format, "jpg")
    }
    
    /// 测试 14：文件下载结果
    func testFileDownloadResult() {
        let result = IMFileDownloadResult(
            localPath: "/path/to/file.jpg",
            size: 2048
        )
        
        XCTAssertEqual(result.localPath, "/path/to/file.jpg")
        XCTAssertEqual(result.size, 2048)
    }
    
    // MARK: - 监听器测试
    
    /// 测试 15：添加和移除监听器
    func testAddRemoveListener() {
        let listener = MockFileTransferListener()
        
        // 添加监听器
        fileManager.addListener(listener)
        
        // 移除监听器
        fileManager.removeListener(listener)
        
        // 应该不会崩溃
        XCTAssertTrue(true)
    }
    
    // MARK: - 性能测试
    
    /// 测试 16：大文件处理性能
    func testLargeFilePerformance() throws {
        // 创建一个 1MB 的测试文件
        let largeData = Data(count: 1024 * 1024)
        let largeFileURL = fileManager.getFileDirectory().appendingPathComponent("large_file.dat")
        
        measure {
            try? largeData.write(to: largeFileURL)
            _ = fileManager.getFileSize(at: largeFileURL)
            try? fileManager.deleteFile(at: largeFileURL)
        }
    }
    
    /// 测试 17：并发文件操作
    func testConcurrentFileOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for i in 0..<10 {
            queue.async {
                let data = Data(count: 1024)
                let url = self.fileManager.getFileDirectory().appendingPathComponent("test_\(i).txt")
                try? data.write(to: url)
                _ = self.fileManager.getFileSize(at: url)
                try? self.fileManager.deleteFile(at: url)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Mock Listener

class MockFileTransferListener: IMFileTransferListener {
    func onUploadProgress(_ progress: IMFileTransferProgress) {
        // Mock implementation
    }
    
    func onDownloadProgress(_ progress: IMFileTransferProgress) {
        // Mock implementation
    }
    
    func onTransferCompleted(_ taskID: String) {
        // Mock implementation
    }
    
    func onTransferFailed(_ taskID: String, error: Error) {
        // Mock implementation
    }
}


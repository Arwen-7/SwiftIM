/// IMFileManager - 文件管理器
/// 负责文件的上传、下载、缓存管理

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import AVFoundation

// MARK: - 文件上传/下载监听器

/// 文件传输监听器
public protocol IMFileTransferListener: AnyObject {
    /// 上传进度回调
    func onUploadProgress(_ progress: IMFileTransferProgress)
    
    /// 下载进度回调
    func onDownloadProgress(_ progress: IMFileTransferProgress)
    
    /// 传输完成
    func onTransferCompleted(_ taskID: String)
    
    /// 传输失败
    func onTransferFailed(_ taskID: String, error: Error)
}

// MARK: - 文件管理器

/// 文件管理器
public final class IMFileManager {
    
    // MARK: - Properties
    
    /// 单例
    public static let shared = IMFileManager()
    
    /// 上传基础 URL（需要配置）
    public var uploadBaseURL: String = ""
    
    /// 下载基础 URL（需要配置）
    public var downloadBaseURL: String = ""
    
    /// 文件存储根目录
    private let fileRootDirectory: URL
    
    /// URL Session
    private let session: URLSession
    
    /// 上传任务字典
    private var uploadTasks: [String: URLSessionUploadTask] = [:]
    
    /// 下载任务字典
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    
    /// 断点续传数据字典
    private var resumeDataStore: [String: IMResumeData] = [:]
    
    /// 监听器列表
    private var listeners: [WeakWrapper<IMFileTransferListener>] = []
    
    /// 锁
    private let lock = NSRecursiveLock()
    
    // MARK: - Initialization
    
    private init() {
        // 创建文件存储目录
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileRootDirectory = documentsURL.appendingPathComponent("IMFiles")
        
        // 创建目录
        try? FileManager.default.createDirectory(at: fileRootDirectory, withIntermediateDirectories: true)
        
        // 配置 URL Session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 300.0
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        
        IMLogger.shared.info("IMFileManager initialized, root: \(fileRootDirectory.path)")
    }
    
    // MARK: - 监听器管理
    
    /// 添加监听器
    public func addListener(_ listener: IMFileTransferListener) {
        lock.lock()
        defer { lock.unlock() }
        
        listeners.append(WeakWrapper(value: listener))
        cleanupListeners()
    }
    
    /// 移除监听器
    public func removeListener(_ listener: IMFileTransferListener) {
        lock.lock()
        defer { lock.unlock() }
        
        listeners.removeAll { $0.value === listener }
    }
    
    /// 清理已释放的监听器
    private func cleanupListeners() {
        listeners.removeAll { $0.value == nil }
    }
    
    /// 通知所有监听器
    private func notifyListeners(_ block: (IMFileTransferListener) -> Void) {
        lock.lock()
        let activeListeners = listeners.compactMap { $0.value }
        lock.unlock()
        
        for listener in activeListeners {
            block(listener)
        }
    }
    
    // MARK: - 文件路径管理
    
    /// 获取图片目录
    public func getImageDirectory() -> URL {
        let url = fileRootDirectory.appendingPathComponent("Images")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// 获取语音目录
    public func getAudioDirectory() -> URL {
        let url = fileRootDirectory.appendingPathComponent("Audio")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// 获取视频目录
    public func getVideoDirectory() -> URL {
        let url = fileRootDirectory.appendingPathComponent("Videos")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// 获取文件目录
    public func getFileDirectory() -> URL {
        let url = fileRootDirectory.appendingPathComponent("Files")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// 获取缩略图目录
    public func getThumbnailDirectory() -> URL {
        let url = fileRootDirectory.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    // MARK: - 文件上传
    
    /// 上传文件
    /// - Parameters:
    ///   - fileURL: 本地文件 URL
    ///   - fileType: 文件类型
    ///   - progressHandler: 进度回调
    ///   - completion: 完成回调
    /// - Returns: 任务 ID
    @discardableResult
    public func uploadFile(
        _ fileURL: URL,
        fileType: IMMessageType,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMFileUploadResult, Error>) -> Void
    ) -> String {
        let taskID = UUID().uuidString
        
        // 获取文件信息
        guard let fileData = try? Data(contentsOf: fileURL) else {
            completion(.failure(IMError.fileNotFound))
            return taskID
        }
        
        let fileSize = Int64(fileData.count)
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // 构建上传 URL
        let uploadURL = URL(string: uploadBaseURL + "/upload")!
        
        // 创建请求
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        // 创建上传任务
        let uploadTask = session.uploadTask(with: request, from: fileData) { [weak self] data, response, error in
            guard let self = self else { return }
            
            self.lock.lock()
            self.uploadTasks.removeValue(forKey: taskID)
            self.lock.unlock()
            
            if let error = error {
                IMLogger.shared.error("Upload failed: \(error)")
                completion(.failure(error))
                self.notifyListeners { $0.onTransferFailed(taskID, error: error) }
                return
            }
            
            // 解析响应
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = json["url"] as? String,
                  let fileID = json["file_id"] as? String else {
                let error = IMError.invalidResponse
                completion(.failure(error))
                self.notifyListeners { $0.onTransferFailed(taskID, error: error) }
                return
            }
            
            let result = IMFileUploadResult(
                url: url,
                fileID: fileID,
                size: fileSize,
                format: fileExtension
            )
            
            IMLogger.shared.info("Upload completed: \(taskID), URL: \(url)")
            completion(.success(result))
            self.notifyListeners { $0.onTransferCompleted(taskID) }
        }
        
        // 保存任务
        lock.lock()
        uploadTasks[taskID] = uploadTask
        lock.unlock()
        
        // 启动任务
        uploadTask.resume()
        
        IMLogger.shared.info("Upload started: \(taskID), size: \(fileSize) bytes")
        return taskID
    }
    
    // MARK: - 文件下载
    
    /// 下载文件
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - fileType: 文件类型
    ///   - progressHandler: 进度回调
    ///   - completion: 完成回调
    /// - Returns: 任务 ID
    @discardableResult
    public func downloadFile(
        from url: String,
        fileType: IMMessageType,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMFileDownloadResult, Error>) -> Void
    ) -> String {
        let taskID = UUID().uuidString
        
        guard let downloadURL = URL(string: url) else {
            completion(.failure(IMError.invalidURL))
            return taskID
        }
        
        // 确定保存目录
        let directory: URL
        switch fileType {
        case .image:
            directory = getImageDirectory()
        case .audio:
            directory = getAudioDirectory()
        case .video:
            directory = getVideoDirectory()
        case .file:
            directory = getFileDirectory()
        default:
            directory = getFileDirectory()
        }
        
        // 生成本地文件名
        let fileName = (url as NSString).lastPathComponent
        let localURL = directory.appendingPathComponent(fileName)
        
        // 如果文件已存在，直接返回
        if FileManager.default.fileExists(atPath: localURL.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
            let result = IMFileDownloadResult(localPath: localURL.path, size: fileSize)
            completion(.success(result))
            return taskID
        }
        
        // 创建下载任务
        let downloadTask = session.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            self.lock.lock()
            self.downloadTasks.removeValue(forKey: taskID)
            self.lock.unlock()
            
            if let error = error {
                IMLogger.shared.error("Download failed: \(error)")
                completion(.failure(error))
                self.notifyListeners { $0.onTransferFailed(taskID, error: error) }
                return
            }
            
            guard let tempURL = tempURL else {
                let error = IMError.downloadFailed
                completion(.failure(error))
                self.notifyListeners { $0.onTransferFailed(taskID, error: error) }
                return
            }
            
            do {
                // 移动文件到目标位置
                try FileManager.default.moveItem(at: tempURL, to: localURL)
                
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
                let result = IMFileDownloadResult(localPath: localURL.path, size: fileSize)
                
                IMLogger.shared.info("Download completed: \(taskID), path: \(localURL.path)")
                completion(.success(result))
                self.notifyListeners { $0.onTransferCompleted(taskID) }
            } catch {
                IMLogger.shared.error("Failed to move downloaded file: \(error)")
                completion(.failure(error))
                self.notifyListeners { $0.onTransferFailed(taskID, error: error) }
            }
        }
        
        // 保存任务
        lock.lock()
        downloadTasks[taskID] = downloadTask
        lock.unlock()
        
        // 启动任务
        downloadTask.resume()
        
        IMLogger.shared.info("Download started: \(taskID), URL: \(url)")
        return taskID
    }
    
    // MARK: - 任务控制
    
    /// 取消上传任务
    public func cancelUpload(_ taskID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        uploadTasks[taskID]?.cancel()
        uploadTasks.removeValue(forKey: taskID)
    }
    
    /// 取消下载任务
    public func cancelDownload(_ taskID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        downloadTasks[taskID]?.cancel()
        downloadTasks.removeValue(forKey: taskID)
    }
    
    // MARK: - 图片处理
    
    /// 生成图片缩略图
    /// - Parameters:
    ///   - imageURL: 原图 URL
    ///   - maxSize: 最大尺寸
    /// - Returns: 缩略图 URL
    public func generateThumbnail(for imageURL: URL, maxSize: CGSize = CGSize(width: 200, height: 200)) -> URL? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            return nil
        }
        
        // 计算缩略图尺寸
        let thumbnailSize = calculateThumbnailSize(originalSize: image.size, maxSize: maxSize)
        
        // 生成缩略图
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let thumbnailImage = thumbnail,
              let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        // 保存缩略图
        let fileName = "thumb_" + imageURL.lastPathComponent
        let thumbnailURL = getThumbnailDirectory().appendingPathComponent(fileName)
        
        do {
            try thumbnailData.write(to: thumbnailURL)
            IMLogger.shared.info("Thumbnail generated: \(thumbnailURL.path)")
            return thumbnailURL
        } catch {
            IMLogger.shared.error("Failed to save thumbnail: \(error)")
            return nil
        }
    }
    
    /// 计算缩略图尺寸
    private func calculateThumbnailSize(originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let ratio = min(widthRatio, heightRatio)
        
        return CGSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )
    }
    
    // MARK: - 文件管理
    
    /// 获取文件大小
    public func getFileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return attributes[.size] as? Int64 ?? 0
    }
    
    /// 删除文件
    public func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        IMLogger.shared.info("File deleted: \(url.path)")
    }
    
    /// 清理缓存
    public func clearCache() throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: fileRootDirectory, includingPropertiesForKeys: nil)
        
        for fileURL in contents {
            try fileManager.removeItem(at: fileURL)
        }
        
        IMLogger.shared.info("Cache cleared")
    }
    
    /// 获取缓存大小
    public func getCacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: fileRootDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
}

// MARK: - Weak Wrapper

private class WeakWrapper<T: AnyObject> {
    weak var value: T?
    
    init(value: T) {
        self.value = value
    }
}

// MARK: - Errors

extension IMError {
    static let fileNotFound = IMError.custom("文件不存在")
    static let invalidURL = IMError.custom("无效的 URL")
    static let downloadFailed = IMError.custom("下载失败")
    static let uploadFailed = IMError.custom("上传失败")
    static let invalidResponse = IMError.custom("无效的响应")
}


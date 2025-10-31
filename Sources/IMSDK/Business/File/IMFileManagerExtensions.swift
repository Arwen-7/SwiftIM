/// IMFileManager Extensions - 高级特性
/// 包括断点续传、文件压缩、视频处理等

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import AVFoundation

// MARK: - 断点续传扩展

extension IMFileManager {
    
    /// 保存断点续传数据
    private func saveResumeData(_ resumeData: IMResumeData) {
        lock.lock()
        defer { lock.unlock() }
        
        resumeDataStore[resumeData.taskID] = resumeData
        
        // 持久化到本地
        let resumeDataURL = getResumeDataDirectory().appendingPathComponent("\(resumeData.taskID).json")
        if let jsonData = try? JSONEncoder().encode(resumeData) {
            try? jsonData.write(to: resumeDataURL)
            IMLogger.shared.debug("Saved resume data: \(resumeData.taskID)")
        }
    }
    
    /// 加载断点续传数据
    public func loadResumeData(for taskID: String) -> IMResumeData? {
        lock.lock()
        defer { lock.unlock() }
        
        // 先从内存中查找
        if let resumeData = resumeDataStore[taskID] {
            return resumeData
        }
        
        // 从磁盘加载
        let resumeDataURL = getResumeDataDirectory().appendingPathComponent("\(taskID).json")
        guard let jsonData = try? Data(contentsOf: resumeDataURL),
              let resumeData = try? JSONDecoder().decode(IMResumeData.self, from: jsonData) else {
            return nil
        }
        
        resumeDataStore[taskID] = resumeData
        return resumeData
    }
    
    /// 删除断点续传数据
    public func deleteResumeData(for taskID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        resumeDataStore.removeValue(forKey: taskID)
        
        let resumeDataURL = getResumeDataDirectory().appendingPathComponent("\(taskID).json")
        try? FileManager.default.removeItem(at: resumeDataURL)
        
        IMLogger.shared.debug("Deleted resume data: \(taskID)")
    }
    
    /// 获取断点续传目录
    private func getResumeDataDirectory() -> URL {
        let dir = fileRootDirectory.appendingPathComponent("ResumeData")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// 可断点续传的下载（支持暂停和恢复）
    @discardableResult
    public func downloadFileResumable(
        from urlString: String,
        fileType: IMFileType,
        taskID: String? = nil,
        progressHandler: ((IMFileTransferProgress) -> Void)? = nil,
        completion: @escaping (Result<IMFileDownloadResult, Error>) -> Void
    ) -> String {
        let actualTaskID = taskID ?? UUID().uuidString
        
        // 检查是否有断点数据
        if let resumeData = loadResumeData(for: actualTaskID) {
            IMLogger.shared.info("Resuming download: \(actualTaskID), progress: \(resumeData.completedBytes)/\(resumeData.totalBytes)")
            return resumeDownload(resumeData: resumeData, progressHandler: progressHandler, completion: completion)
        }
        
        // 新建下载任务
        guard let url = URL(string: urlString) else {
            completion(.failure(IMError.invalidURL))
            return actualTaskID
        }
        
        let localPath = getFilePath(for: fileType).appendingPathComponent(url.lastPathComponent).path
        
        // 先获取文件大小
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let headTask = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            let totalBytes = response?.expectedContentLength ?? 0
            
            // 创建断点数据
            let resumeData = IMResumeData(
                taskID: actualTaskID,
                fileURL: urlString,
                localPath: localPath,
                totalBytes: totalBytes,
                completedBytes: 0
            )
            self.saveResumeData(resumeData)
            
            // 开始下载
            _ = self.resumeDownload(resumeData: resumeData, progressHandler: progressHandler, completion: completion)
        }
        
        headTask.resume()
        return actualTaskID
    }
    
    /// 恢复下载
    private func resumeDownload(
        resumeData: IMResumeData,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMFileDownloadResult, Error>) -> Void
    ) -> String {
        guard let url = URL(string: resumeData.fileURL) else {
            completion(.failure(IMError.invalidURL))
            return resumeData.taskID
        }
        
        var request = URLRequest(url: url)
        
        // 设置 Range header 实现断点续传
        if resumeData.completedBytes > 0 {
            request.setValue("bytes=\(resumeData.completedBytes)-", forHTTPHeaderField: "Range")
            IMLogger.shared.debug("Resume download from byte: \(resumeData.completedBytes)")
        }
        
        let localURL = URL(fileURLWithPath: resumeData.localPath)
        let tempURL = localURL.appendingPathExtension("download")
        
        let downloadTask = session.downloadTask(with: request) { [weak self] tempDownloadURL, response, error in
            guard let self = self else { return }
            
            self.lock.lock()
            self.downloadTasks.removeValue(forKey: resumeData.taskID)
            self.lock.unlock()
            
            if let error = error {
                self.notifyListeners { $0.onTransferFailed(resumeData.taskID, error: error) }
                completion(.failure(error))
                return
            }
            
            guard let tempDownloadURL = tempDownloadURL else {
                let error = IMError.downloadFailed
                self.notifyListeners { $0.onTransferFailed(resumeData.taskID, error: error) }
                completion(.failure(error))
                return
            }
            
            do {
                // 如果是续传，需要合并文件
                if resumeData.completedBytes > 0 && FileManager.default.fileExists(atPath: tempURL.path) {
                    // 追加数据
                    let newData = try Data(contentsOf: tempDownloadURL)
                    let fileHandle = try FileHandle(forWritingTo: tempURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(newData)
                    fileHandle.closeFile()
                } else {
                    // 首次下载
                    try FileManager.default.copyItem(at: tempDownloadURL, to: tempURL)
                }
                
                // 检查是否下载完成
                let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
                
                if fileSize >= resumeData.totalBytes {
                    // 下载完成，移动到最终位置
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                    
                    // 删除断点数据
                    self.deleteResumeData(for: resumeData.taskID)
                    
                    let result = IMFileDownloadResult(
                        localPath: localURL.path,
                        size: fileSize
                    )
                    
                    self.notifyListeners { $0.onTransferCompleted(resumeData.taskID) }
                    completion(.success(result))
                    
                    IMLogger.shared.info("Download completed: \(localURL.path), size: \(fileSize)")
                } else {
                    // 更新断点数据
                    var updatedResumeData = resumeData
                    updatedResumeData.completedBytes = fileSize
                    self.saveResumeData(updatedResumeData)
                    
                    IMLogger.shared.debug("Download progress saved: \(fileSize)/\(resumeData.totalBytes)")
                }
                
            } catch {
                self.notifyListeners { $0.onTransferFailed(resumeData.taskID, error: error) }
                completion(.failure(error))
            }
        }
        
        lock.lock()
        downloadTasks[resumeData.taskID] = downloadTask
        lock.unlock()
        
        downloadTask.resume()
        
        IMLogger.shared.info("Download task started: \(resumeData.taskID)")
        return resumeData.taskID
    }
    
    /// 暂停下载
    public func pauseDownload(_ taskID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let task = downloadTasks[taskID] {
            task.cancel()
            downloadTasks.removeValue(forKey: taskID)
            IMLogger.shared.info("Download paused: \(taskID)")
        }
    }
    
    /// 取消下载
    public func cancelDownload(_ taskID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let task = downloadTasks[taskID] {
            task.cancel()
            downloadTasks.removeValue(forKey: taskID)
        }
        
        // 删除断点数据和临时文件
        if let resumeData = resumeDataStore[taskID] {
            let tempURL = URL(fileURLWithPath: resumeData.localPath).appendingPathExtension("download")
            try? FileManager.default.removeItem(at: tempURL)
            deleteResumeData(for: taskID)
        }
        
        IMLogger.shared.info("Download cancelled: \(taskID)")
    }
}

// MARK: - 图片压缩扩展

extension IMFileManager {
    
    /// 压缩图片
    public func compressImage(
        at imageURL: URL,
        config: IMImageCompressionConfig = .default
    ) -> URL? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            IMLogger.shared.error("Failed to load image: \(imageURL.path)")
            return nil
        }
        
        let startTime = Date()
        
        // 计算压缩后的尺寸
        let originalSize = image.size
        let scaledSize = calculateScaledSize(originalSize: originalSize, maxWidth: config.maxWidth, maxHeight: config.maxHeight)
        
        // 重绘图片
        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: scaledSize))
        guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        
        // 压缩
        let imageData: Data?
        if config.format.lowercased() == "png" {
            imageData = scaledImage.pngData()
        } else {
            imageData = scaledImage.jpegData(compressionQuality: config.quality)
        }
        
        guard let data = imageData else {
            IMLogger.shared.error("Failed to compress image")
            return nil
        }
        
        // 保存到临时目录
        let compressedURL = getTempDirectory().appendingPathComponent("compressed_\(imageURL.lastPathComponent)")
        do {
            try data.write(to: compressedURL)
            
            let originalSize = try FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? Int64 ?? 0
            let compressedSize = data.count
            let compressionRatio = Double(compressedSize) / Double(originalSize)
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            IMLogger.shared.info("Image compressed: \(imageURL.lastPathComponent), \(originalSize) -> \(compressedSize) bytes (\(String(format: "%.1f%%", compressionRatio * 100))), time: \(String(format: "%.2f", elapsedTime))s")
            
            return compressedURL
        } catch {
            IMLogger.shared.error("Failed to save compressed image: \(error)")
            return nil
        }
    }
    
    /// 计算缩放后的尺寸
    private func calculateScaledSize(originalSize: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        if originalSize.width <= maxWidth && originalSize.height <= maxHeight {
            return originalSize
        }
        
        let widthRatio = maxWidth / originalSize.width
        let heightRatio = maxHeight / originalSize.height
        let ratio = min(widthRatio, heightRatio)
        
        return CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
    }
}

// MARK: - 视频处理扩展

extension IMFileManager {
    
    /// 提取视频封面（第一帧）
    public func extractVideoThumbnail(
        from videoURL: URL,
        at time: CMTime = .zero,
        size: CGSize = CGSize(width: 200, height: 200)
    ) -> URL? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            
            // 保存缩略图
            guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
                return nil
            }
            
            let thumbnailURL = getThumbnailDirectory().appendingPathComponent("thumb_\(videoURL.lastPathComponent).jpg")
            try thumbnailData.write(to: thumbnailURL)
            
            IMLogger.shared.info("Video thumbnail extracted: \(thumbnailURL.lastPathComponent)")
            return thumbnailURL
            
        } catch {
            IMLogger.shared.error("Failed to extract video thumbnail: \(error)")
            return nil
        }
    }
    
    /// 压缩视频
    public func compressVideo(
        at videoURL: URL,
        config: IMVideoCompressionConfig = .default,
        progressHandler: ((Double) -> Void)? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let asset = AVAsset(url: videoURL)
        
        // 检查视频时长
        let duration = asset.duration.seconds
        if duration > config.maxDuration {
            completion(.failure(IMError.custom("Video duration exceeds maximum: \(duration)s > \(config.maxDuration)s")))
            return
        }
        
        // 配置导出会话
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            completion(.failure(IMError.custom("Failed to create export session")))
            return
        }
        
        let outputURL = getTempDirectory().appendingPathComponent("compressed_\(videoURL.lastPathComponent)")
        
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        let startTime = Date()
        
        // 监听进度
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let progress = Double(exportSession.progress)
            progressHandler?(progress)
        }
        
        // 开始导出
        exportSession.exportAsynchronously { [weak self] in
            timer.invalidate()
            
            guard let self = self else { return }
            
            switch exportSession.status {
            case .completed:
                do {
                    let originalSize = try FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64 ?? 0
                    let compressedSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
                    let compressionRatio = Double(compressedSize) / Double(originalSize)
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    
                    IMLogger.shared.info("Video compressed: \(videoURL.lastPathComponent), \(originalSize) -> \(compressedSize) bytes (\(String(format: "%.1f%%", compressionRatio * 100))), time: \(String(format: "%.2f", elapsedTime))s")
                    
                    completion(.success(outputURL))
                } catch {
                    completion(.failure(error))
                }
                
            case .failed:
                let error = exportSession.error ?? IMError.custom("Video compression failed")
                IMLogger.shared.error("Video compression failed: \(error)")
                completion(.failure(error))
                
            case .cancelled:
                completion(.failure(IMError.custom("Video compression cancelled")))
                
            default:
                completion(.failure(IMError.custom("Unknown export status: \(exportSession.status.rawValue)")))
            }
        }
    }
    
    /// 获取视频信息
    public func getVideoInfo(from videoURL: URL) -> (duration: TimeInterval, size: CGSize, fileSize: Int64)? {
        let asset = AVAsset(url: videoURL)
        let duration = asset.duration.seconds
        
        guard let track = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        
        let size = track.naturalSize.applying(track.preferredTransform)
        let normalizedSize = CGSize(width: abs(size.width), height: abs(size.height))
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64) ?? 0
        
        return (duration, normalizedSize, fileSize)
    }
}


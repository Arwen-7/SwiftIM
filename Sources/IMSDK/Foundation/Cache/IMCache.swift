/// IMCache - 缓存管理
/// 提供内存缓存和磁盘缓存功能

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// 缓存项
private final class CacheItem<T> {
    let key: String
    let value: T
    let cost: Int
    let expiration: Date?
    var accessTime: Date
    
    init(key: String, value: T, cost: Int, expiration: Date?) {
        self.key = key
        self.value = value
        self.cost = cost
        self.expiration = expiration
        self.accessTime = Date()
    }
    
    var isExpired: Bool {
        guard let expiration = expiration else { return false }
        return Date() > expiration
    }
}

/// 内存缓存
public final class IMMemoryCache<T> {
    
    // MARK: - Properties
    
    private var cache: [String: CacheItem<T>] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.imsdk.memory.cache", qos: .utility)
    
    /// 最大缓存数量
    public var countLimit: Int = 100
    
    /// 最大缓存成本
    public var costLimit: Int = 1024 * 1024 * 50 // 50MB
    
    private var currentCost: Int = 0
    
    // MARK: - Initialization
    
    public init(countLimit: Int = 100, costLimit: Int = 1024 * 1024 * 50) {
        self.countLimit = countLimit
        self.costLimit = costLimit
        
        // 监听内存警告（iOS/macOS 兼容）
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// 存储对象
    /// - Parameters:
    ///   - value: 要存储的对象
    ///   - key: 键
    ///   - cost: 成本（默认为0）
    ///   - expiration: 过期时间（可选）
    public func set(_ value: T, forKey key: String, cost: Int = 0, expiration: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        // 移除旧值
        if let oldItem = cache[key] {
            currentCost -= oldItem.cost
        }
        
        // 添加新值
        let item = CacheItem(key: key, value: value, cost: cost, expiration: expiration)
        cache[key] = item
        currentCost += cost
        
        // 检查是否需要清理
        trimIfNeeded()
    }
    
    /// 获取对象
    /// - Parameter key: 键
    /// - Returns: 对象（如果存在且未过期）
    public func get(forKey key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let item = cache[key] else { return nil }
        
        // 检查是否过期
        if item.isExpired {
            cache.removeValue(forKey: key)
            currentCost -= item.cost
            return nil
        }
        
        // 更新访问时间
        item.accessTime = Date()
        return item.value
    }
    
    /// 移除对象
    /// - Parameter key: 键
    public func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let item = cache.removeValue(forKey: key) {
            currentCost -= item.cost
        }
    }
    
    /// 清空缓存
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        currentCost = 0
    }
    
    /// 检查是否包含键
    /// - Parameter key: 键
    /// - Returns: 是否包含
    public func contains(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return cache[key] != nil && !(cache[key]?.isExpired ?? true)
    }
    
    // MARK: - Private Methods
    
    private func trimIfNeeded() {
        // 移除过期项
        cache = cache.filter { !$0.value.isExpired }
        
        // 按数量限制清理
        while cache.count > countLimit {
            if let oldestKey = cache.min(by: { $0.value.accessTime < $1.value.accessTime })?.key {
                if let item = cache.removeValue(forKey: oldestKey) {
                    currentCost -= item.cost
                }
            }
        }
        
        // 按成本限制清理
        while currentCost > costLimit {
            if let oldestKey = cache.min(by: { $0.value.accessTime < $1.value.accessTime })?.key {
                if let item = cache.removeValue(forKey: oldestKey) {
                    currentCost -= item.cost
                }
            } else {
                break
            }
        }
    }
    
    @objc private func handleMemoryWarning() {
        IMLogger.shared.warning("Memory warning received, clearing cache")
        removeAll()
    }
}

/// 磁盘缓存
public final class IMDiskCache {
    
    // MARK: - Properties
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.imsdk.disk.cache", qos: .utility)
    
    /// 最大缓存大小（字节）
    public var sizeLimit: UInt64 = 100 * 1024 * 1024 // 100MB
    
    /// 最大缓存时间（秒）
    public var ageLimit: TimeInterval = 7 * 24 * 60 * 60 // 7天
    
    // MARK: - Initialization
    
    public init(name: String = "IMDiskCache") {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheDir.appendingPathComponent(name)
        
        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 启动后台清理
        queue.async { [weak self] in
            self?.trimCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// 存储数据
    /// - Parameters:
    ///   - data: 要存储的数据
    ///   - key: 键
    ///   - completion: 完成回调
    public func set(_ data: Data, forKey key: String, completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }
            
            let fileURL = self.fileURL(forKey: key)
            let success = (try? data.write(to: fileURL)) != nil
            
            if success {
                IMLogger.shared.debug("Disk cache saved: \(key)")
            } else {
                IMLogger.shared.error("Disk cache save failed: \(key)")
            }
            
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }
    
    /// 获取数据
    /// - Parameters:
    ///   - key: 键
    ///   - completion: 完成回调
    public func get(forKey key: String, completion: @escaping (Data?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let fileURL = self.fileURL(forKey: key)
            
            // 检查文件是否存在
            guard self.fileManager.fileExists(atPath: fileURL.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // 检查是否过期
            if let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
               let modificationDate = attributes[.modificationDate] as? Date {
                let age = Date().timeIntervalSince(modificationDate)
                if age > self.ageLimit {
                    try? self.fileManager.removeItem(at: fileURL)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
            }
            
            // 读取数据
            let data = try? Data(contentsOf: fileURL)
            
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }
    
    /// 移除数据
    /// - Parameters:
    ///   - key: 键
    ///   - completion: 完成回调
    public func remove(forKey key: String, completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }
            
            let fileURL = self.fileURL(forKey: key)
            let success = (try? self.fileManager.removeItem(at: fileURL)) != nil
            
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }
    
    /// 清空缓存
    /// - Parameter completion: 完成回调
    public func removeAll(completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }
            
            var success = false
            
            if let files = try? self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil) {
                success = true
                for fileURL in files {
                    if (try? self.fileManager.removeItem(at: fileURL)) == nil {
                        success = false
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }
    
    /// 获取缓存大小
    /// - Parameter completion: 完成回调（返回字节数）
    public func getCacheSize(completion: @escaping (UInt64) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            
            var totalSize: UInt64 = 0
            
            if let files = try? self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
                for fileURL in files {
                    if let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                       let fileSize = attributes[.size] as? UInt64 {
                        totalSize += fileSize
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(totalSize)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func fileURL(forKey key: String) -> URL {
        let filename = IMCrypto.shared.md5(string: key)
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func trimCache() {
        // 移除过期文件
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let now = Date()
            for fileURL in files {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    let age = now.timeIntervalSince(modificationDate)
                    if age > ageLimit {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
        }
        
        // 按大小限制清理
        getCacheSize { [weak self] currentSize in
            guard let self = self, currentSize > self.sizeLimit else { return }
            
            self.queue.async {
                if let files = try? self.fileManager.contentsOfDirectory(
                    at: self.cacheDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
                ) {
                    // 按修改时间排序
                    let sortedFiles = files.sorted { file1, file2 in
                        let date1 = (try? self.fileManager.attributesOfItem(atPath: file1.path)[.modificationDate] as? Date) ?? Date.distantPast
                        let date2 = (try? self.fileManager.attributesOfItem(atPath: file2.path)[.modificationDate] as? Date) ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    // 删除最旧的文件直到满足大小限制
                    var totalSize = currentSize
                    for fileURL in sortedFiles {
                        guard totalSize > self.sizeLimit else { break }
                        
                        if let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                           let fileSize = attributes[.size] as? UInt64 {
                            try? self.fileManager.removeItem(at: fileURL)
                            totalSize -= fileSize
                        }
                    }
                }
            }
        }
    }
}


/// IMUtils - 通用工具类
/// 提供各种实用工具方法

import Foundation

/// 通用工具类
public final class IMUtils {
    
    private init() {}
    
    // MARK: - UUID Generation
    
    /// 生成唯一 ID
    /// - Returns: UUID 字符串
    public static func generateUUID() -> String {
        return UUID().uuidString.lowercased()
    }
    
    /// 生成消息 ID
    /// - Returns: 消息 ID
    public static func generateMessageID() -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "\(timestamp)\(random)"
    }
    
    // MARK: - Time
    
    /// 获取当前时间戳（毫秒）
    /// - Returns: 时间戳
    public static func currentTimeMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    /// 获取当前时间戳（秒）
    /// - Returns: 时间戳
    public static func currentTimeSeconds() -> Int64 {
        return Int64(Date().timeIntervalSince1970)
    }
    
    /// 格式化时间戳
    /// - Parameters:
    ///   - timestamp: 时间戳（毫秒）
    ///   - format: 日期格式
    /// - Returns: 格式化后的时间字符串
    public static func formatTimestamp(_ timestamp: Int64, format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    // MARK: - JSON
    
    /// 字典转 JSON 字符串
    /// - Parameter dict: 字典
    /// - Returns: JSON 字符串
    public static func dictToJSON(_ dict: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            return nil
        }
        return String(data: jsonData, encoding: .utf8)
    }
    
    /// JSON 字符串转字典
    /// - Parameter json: JSON 字符串
    /// - Returns: 字典
    public static func jsonToDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    // MARK: - Data Conversion
    
    /// 字符串转 Data
    /// - Parameter string: 字符串
    /// - Returns: Data
    public static func stringToData(_ string: String) -> Data? {
        return string.data(using: .utf8)
    }
    
    /// Data 转字符串
    /// - Parameter data: Data
    /// - Returns: 字符串
    public static func dataToString(_ data: Data) -> String? {
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - File Size
    
    /// 格式化文件大小
    /// - Parameter bytes: 字节数
    /// - Returns: 格式化后的大小字符串
    public static func formatFileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.2f %@", size, units[unitIndex])
    }
    
    // MARK: - Network
    
    /// 检查是否为有效的 URL
    /// - Parameter urlString: URL 字符串
    /// - Returns: 是否有效
    public static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    // MARK: - Validation
    
    /// 验证手机号（中国大陆）
    /// - Parameter phone: 手机号
    /// - Returns: 是否有效
    public static func isValidPhoneNumber(_ phone: String) -> Bool {
        let pattern = "^1[3-9]\\d{9}$"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: phone)
    }
    
    /// 验证邮箱
    /// - Parameter email: 邮箱地址
    /// - Returns: 是否有效
    public static func isValidEmail(_ email: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }
}

// MARK: - Thread Safety

/// 线程安全的值包装器
@propertyWrapper
public final class ThreadSafe<T> {
    private var value: T
    private let lock = NSLock()
    
    public init(wrappedValue: T) {
        self.value = wrappedValue
    }
    
    public var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
    
    /// 原子操作
    public func atomicUpdate(_ update: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&value)
    }
}

// MARK: - Debouncer

/// 防抖器
public final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue
    
    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }
    
    /// 执行防抖操作
    public func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }
    
    /// 取消待执行的操作
    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

// MARK: - Throttler

/// 节流器
public final class Throttler {
    private let interval: TimeInterval
    private var lastExecutionTime: Date?
    private let queue: DispatchQueue
    
    public init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }
    
    /// 执行节流操作
    public func throttle(action: @escaping () -> Void) {
        let now = Date()
        
        if let lastTime = lastExecutionTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < interval {
                return
            }
        }
        
        lastExecutionTime = now
        queue.async(execute: action)
    }
}


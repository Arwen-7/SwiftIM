/// IMNetworkMonitor - 网络状态监听器
/// 使用 Network Framework 监听设备网络状态变化

import Foundation
import Network

// MARK: - 网络状态

/// 网络状态
public enum IMNetworkStatus: Int {
    case unknown = 0        // 未知
    case unavailable = 1    // 不可用
    case wifi = 2           // WiFi
    case cellular = 3       // 蜂窝数据（4G/5G）
    
    /// 是否可用
    public var isAvailable: Bool {
        switch self {
        case .wifi, .cellular:
            return true
        case .unknown, .unavailable:
            return false
        }
    }
    
    /// 是否是 WiFi
    public var isWiFi: Bool {
        if case .wifi = self { return true }
        return false
    }
    
    /// 是否是蜂窝数据
    public var isCellular: Bool {
        if case .cellular = self { return true }
        return false
    }
}

// MARK: - CustomStringConvertible

extension IMNetworkStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .unavailable:
            return "Unavailable"
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        }
    }
}

// MARK: - 网络状态监听委托

/// 网络状态监听委托
public protocol IMNetworkMonitorDelegate: AnyObject {
    /// 网络状态改变
    /// - Parameter status: 新的网络状态
    func networkStatusDidChange(_ status: IMNetworkStatus)
    
    /// 网络已连接（从断开到连接）
    func networkDidConnect()
    
    /// 网络已断开
    func networkDidDisconnect()
}

// MARK: - 网络状态监听器

/// 网络状态监听器
/// 使用 Network Framework (iOS 12+) 监听网络状态变化
public class IMNetworkMonitor {
    
    // MARK: - Properties
    
    /// 网络监听器
    private let monitor = NWPathMonitor()
    
    /// 监听队列
    private let queue = DispatchQueue(label: "com.imsdk.network.monitor", qos: .utility)
    
    /// 当前网络状态
    private(set) public var currentStatus: IMNetworkStatus = .unknown {
        didSet {
            IMLogger.shared.verbose("Network status updated: \(oldValue) -> \(currentStatus)")
        }
    }
    
    /// 是否正在监听
    private(set) public var isMonitoring = false
    
    /// 委托
    public weak var delegate: IMNetworkMonitorDelegate?
    
    /// 上次通知时间（用于防抖动）
    private var lastNotificationTime: TimeInterval = 0
    
    /// 通知间隔（秒）- 防止频繁通知
    private let notificationInterval: TimeInterval = 0.5
    
    /// 同步锁
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init() {
        setupMonitor()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Setup
    
    /// 设置监听器
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }
    
    // MARK: - Public Methods
    
    /// 开始监听
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isMonitoring else {
            IMLogger.shared.warning("Network monitor already started")
            return
        }
        
        monitor.start(queue: queue)
        isMonitoring = true
        
        IMLogger.shared.info("📶 Network monitor started")
    }
    
    /// 停止监听
    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isMonitoring else {
            return
        }
        
        monitor.cancel()
        isMonitoring = false
        
        IMLogger.shared.info("📶 Network monitor stopped")
    }
    
    // MARK: - Private Methods
    
    /// 处理网络路径更新
    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = getNetworkStatus(from: path)
        
        lock.lock()
        let oldStatus = currentStatus
        lock.unlock()
        
        // 状态未改变，直接返回
        guard newStatus != oldStatus else {
            return
        }
        
        // 防抖动：检查距离上次通知的时间
        let now = Date().timeIntervalSince1970
        guard now - lastNotificationTime >= notificationInterval else {
            IMLogger.shared.verbose("Network status change ignored due to debounce")
            return
        }
        
        lastNotificationTime = now
        
        // 更新状态
        lock.lock()
        currentStatus = newStatus
        lock.unlock()
        
        IMLogger.shared.info("📶 Network status changed: \(oldStatus) -> \(newStatus)")
        
        // 通知委托（在主线程）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.networkStatusDidChange(newStatus)
            
            // 判断连接/断开事件
            let wasAvailable = oldStatus.isAvailable
            let isAvailable = newStatus.isAvailable
            
            if !wasAvailable && isAvailable {
                // 从断开到连接
                IMLogger.shared.info("📶 Network connected: \(newStatus)")
                self.delegate?.networkDidConnect()
            } else if wasAvailable && !isAvailable {
                // 从连接到断开
                IMLogger.shared.warning("📶 Network disconnected")
                self.delegate?.networkDidDisconnect()
            }
        }
    }
    
    /// 从网络路径获取网络状态
    private func getNetworkStatus(from path: NWPath) -> IMNetworkStatus {
        guard path.status == .satisfied else {
            return .unavailable
        }
        
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            // 有线网络也视为 WiFi（Mac 上）
            return .wifi
        } else {
            return .unknown
        }
    }
}

// MARK: - Convenience Methods

extension IMNetworkMonitor {
    
    /// 网络是否可用
    public var isNetworkAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus.isAvailable
    }
    
    /// 是否是 WiFi
    public var isWiFi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus.isWiFi
    }
    
    /// 是否是蜂窝数据
    public var isCellular: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus.isCellular
    }
}


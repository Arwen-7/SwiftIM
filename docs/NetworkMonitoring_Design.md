# 网络监听技术方案

## 📋 目录
1. [概述](#概述)
2. [核心概念](#核心概念)
3. [技术方案](#技术方案)
4. [实现细节](#实现细节)
5. [使用示例](#使用示例)

---

## 概述

### 什么是网络监听？

**网络监听**是指实时监测设备的网络连接状态变化（WiFi、蜂窝数据、断开等），并在网络状态改变时自动执行相应的操作。

### 为什么需要网络监听？

**场景：用户在地铁中网络频繁切换**

**无网络监听（不好）**：
```
用户进入地铁 → 网络断开
  - WebSocket 连接中断
  - 用户不知道网络状态
  - 需要手动重新连接
  - 用户体验：❌ 差，不智能
```

**有网络监听（好）**：
```
用户进入地铁 → 网络断开
  - 自动检测到网络断开
  - 更新 UI 显示"网络不可用"
  - 停止不必要的网络请求

网络恢复 → 自动重连
  - 检测到网络恢复（WiFi/4G）
  - 自动重连 WebSocket
  - 自动同步离线消息
  - 用户体验：✅ 好，自动化
```

---

## 核心概念

### 1. 网络状态类型

```swift
/// 网络状态
public enum IMNetworkStatus {
    case unknown        // 未知
    case unavailable    // 不可用
    case wifi           // WiFi
    case cellular       // 蜂窝数据（4G/5G）
}
```

### 2. 网络状态变化事件

```swift
/// 网络状态变化回调
public protocol IMNetworkStatusDelegate: AnyObject {
    /// 网络状态改变
    func networkStatusDidChange(_ status: IMNetworkStatus)
    
    /// 网络已连接（从断开到连接）
    func networkDidConnect()
    
    /// 网络已断开
    func networkDidDisconnect()
}
```

### 3. 监听机制

iOS 提供了 **Network Framework** (iOS 12+) 来监听网络状态：

```swift
import Network

let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    if path.status == .satisfied {
        // 网络可用
        if path.usesInterfaceType(.wifi) {
            // WiFi
        } else if path.usesInterfaceType(.cellular) {
            // 蜂窝数据
        }
    } else {
        // 网络不可用
    }
}
```

---

## 技术方案

### 架构设计

```
┌─────────────────────────────────────────────┐
│              Application                    │
│  - 显示网络状态图标                         │
│  - 根据网络状态调整 UI                      │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│            IMClient                        │
│  - 集成 IMNetworkMonitor                    │
│  - 网络恢复时自动重连                       │
│  - 网络断开时更新状态                       │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│        IMNetworkMonitor (新增)              │
│  ┌───────────────────────────────────────┐ │
│  │  - NWPathMonitor                      │ │
│  │  - 监听网络状态变化                   │ │
│  │  - 通知 Delegate                      │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 数据流

```
iOS 系统网络变化
   │
   ▼
NWPathMonitor 检测到变化
   │
   ├─ WiFi 连接
   │   └─► IMNetworkMonitor.currentStatus = .wifi
   │       └─► 通知 Delegate: networkStatusDidChange(.wifi)
   │
   ├─ 蜂窝数据连接
   │   └─► IMNetworkMonitor.currentStatus = .cellular
   │       └─► 通知 Delegate: networkStatusDidChange(.cellular)
   │
   └─ 网络断开
       └─► IMNetworkMonitor.currentStatus = .unavailable
           └─► 通知 Delegate: networkDidDisconnect()
```

---

## 实现细节

### 1. 网络监听器

```swift
// IMNetworkMonitor.swift

import Foundation
import Network

/// 网络状态
public enum IMNetworkStatus {
    case unknown
    case unavailable
    case wifi
    case cellular
    
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

/// 网络状态监听委托
public protocol IMNetworkMonitorDelegate: AnyObject {
    /// 网络状态改变
    func networkStatusDidChange(_ status: IMNetworkStatus)
    
    /// 网络已连接（从断开到连接）
    func networkDidConnect()
    
    /// 网络已断开
    func networkDidDisconnect()
}

/// 网络状态监听器
public class IMNetworkMonitor {
    
    // MARK: - Properties
    
    /// 网络监听器
    private let monitor = NWPathMonitor()
    
    /// 监听队列
    private let queue = DispatchQueue(label: "com.imsdk.network.monitor")
    
    /// 当前网络状态
    private(set) public var currentStatus: IMNetworkStatus = .unknown
    
    /// 是否正在监听
    private(set) public var isMonitoring = false
    
    /// 委托
    public weak var delegate: IMNetworkMonitorDelegate?
    
    // MARK: - Initialization
    
    public init() {
        setupMonitor()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Setup
    
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }
    
    // MARK: - Public Methods
    
    /// 开始监听
    public func startMonitoring() {
        guard !isMonitoring else {
            IMLogger.shared.warning("Network monitor already started")
            return
        }
        
        monitor.start(queue: queue)
        isMonitoring = true
        
        IMLogger.shared.info("Network monitor started")
    }
    
    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else {
            return
        }
        
        monitor.cancel()
        isMonitoring = false
        
        IMLogger.shared.info("Network monitor stopped")
    }
    
    // MARK: - Private Methods
    
    /// 处理网络路径更新
    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = getNetworkStatus(from: path)
        let oldStatus = currentStatus
        
        // 状态未改变，直接返回
        guard newStatus != oldStatus else {
            return
        }
        
        currentStatus = newStatus
        
        IMLogger.shared.info("Network status changed: \(oldStatus) -> \(newStatus)")
        
        // 通知委托
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.networkStatusDidChange(newStatus)
            
            // 判断连接/断开
            let wasAvailable = oldStatus.isAvailable
            let isAvailable = newStatus.isAvailable
            
            if !wasAvailable && isAvailable {
                // 从断开到连接
                self.delegate?.networkDidConnect()
            } else if wasAvailable && !isAvailable {
                // 从连接到断开
                self.delegate?.networkDidDisconnect()
            }
        }
    }
    
    /// 获取网络状态
    private func getNetworkStatus(from path: NWPath) -> IMNetworkStatus {
        guard path.status == .satisfied else {
            return .unavailable
        }
        
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else {
            return .unknown
        }
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
```

### 2. 集成到 IMClient

```swift
// IMClient.swift

public class IMClient {
    
    // 网络监听器
    private let networkMonitor = IMNetworkMonitor()
    
    public func initialize(config: IMConfig) throws {
        // ... existing code ...
        
        // 设置网络监听
        networkMonitor.delegate = self
        networkMonitor.startMonitoring()
    }
    
    public func destroy() {
        networkMonitor.stopMonitoring()
        // ... existing code ...
    }
}

// MARK: - IMNetworkMonitorDelegate

extension IMClient: IMNetworkMonitorDelegate {
    
    public func networkStatusDidChange(_ status: IMNetworkStatus) {
        IMLogger.shared.info("📶 Network status: \(status)")
        
        // 通知监听器
        notifyConnectionListeners { listener in
            if let listener = listener as? IMNetworkStatusListener {
                listener.onNetworkStatusChanged(status)
            }
        }
    }
    
    public func networkDidConnect() {
        IMLogger.shared.info("📶 Network connected")
        
        // 网络恢复，自动重连
        if connectionState == .disconnected {
            IMLogger.shared.info("Auto reconnecting due to network recovery...")
            connect()
        }
    }
    
    public func networkDidDisconnect() {
        IMLogger.shared.warning("📶 Network disconnected")
        
        // 网络断开，更新连接状态
        if connectionState != .disconnected {
            updateConnectionState(.disconnected)
        }
    }
}

/// 网络状态监听器（扩展）
public protocol IMNetworkStatusListener: AnyObject {
    func onNetworkStatusChanged(_ status: IMNetworkStatus)
}
```

### 3. 暴露给应用层

```swift
// IMClient.swift

extension IMClient {
    
    /// 获取当前网络状态
    public var networkStatus: IMNetworkStatus {
        return networkMonitor.currentStatus
    }
    
    /// 网络是否可用
    public var isNetworkAvailable: Bool {
        return networkMonitor.currentStatus.isAvailable
    }
}
```

---

## 使用示例

### Example 1: 基础集成

```swift
import IMSDK

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 初始化 SDK
        let config = IMConfig(
            apiURL: "https://api.example.com",
            wsURL: "wss://ws.example.com"
        )
        
        try? IMClient.shared.initialize(config: config)
        
        // 网络监听已自动启动
        // SDK 会自动处理网络变化
        
        return true
    }
}
```

### Example 2: 监听网络状态变化

```swift
class ChatViewController: UIViewController, IMConnectionListener, IMNetworkStatusListener {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 添加监听器
        IMClient.shared.addConnectionListener(self)
    }
    
    // MARK: - IMNetworkStatusListener
    
    func onNetworkStatusChanged(_ status: IMNetworkStatus) {
        switch status {
        case .wifi:
            updateNetworkIndicator(icon: "wifi", color: .green)
            showToast("已连接到 WiFi")
            
        case .cellular:
            updateNetworkIndicator(icon: "signal", color: .orange)
            showToast("使用蜂窝数据")
            
        case .unavailable:
            updateNetworkIndicator(icon: "wifi.slash", color: .red)
            showToast("网络不可用")
            
        case .unknown:
            updateNetworkIndicator(icon: "questionmark", color: .gray)
        }
    }
}
```

### Example 3: 根据网络状态调整行为

```swift
class MessageSender {
    
    func sendImage(_ image: UIImage) {
        // 检查网络状态
        let networkStatus = IMClient.shared.networkStatus
        
        switch networkStatus {
        case .wifi:
            // WiFi：发送原图
            sendOriginalImage(image)
            
        case .cellular:
            // 蜂窝数据：询问用户
            showAlert("使用蜂窝数据发送原图？") { confirmed in
                if confirmed {
                    self.sendOriginalImage(image)
                } else {
                    self.sendCompressedImage(image)
                }
            }
            
        case .unavailable:
            // 无网络：提示用户
            showError("网络不可用，请稍后重试")
            
        case .unknown:
            // 未知：默认行为
            sendCompressedImage(image)
        }
    }
}
```

### Example 4: 显示网络状态指示器

```swift
class NetworkStatusView: UIView {
    
    private let statusLabel = UILabel()
    private let iconView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        
        // 监听网络状态
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged),
            name: NSNotification.Name("NetworkStatusChanged"),
            object: nil
        )
    }
    
    @objc private func networkStatusChanged() {
        let status = IMClient.shared.networkStatus
        
        UIView.animate(withDuration: 0.3) {
            switch status {
            case .wifi:
                self.iconView.image = UIImage(systemName: "wifi")
                self.iconView.tintColor = .systemGreen
                self.statusLabel.text = "WiFi"
                
            case .cellular:
                self.iconView.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
                self.iconView.tintColor = .systemOrange
                self.statusLabel.text = "蜂窝数据"
                
            case .unavailable:
                self.iconView.image = UIImage(systemName: "wifi.slash")
                self.iconView.tintColor = .systemRed
                self.statusLabel.text = "无网络"
                
            case .unknown:
                self.iconView.image = UIImage(systemName: "questionmark")
                self.iconView.tintColor = .systemGray
                self.statusLabel.text = "未知"
            }
        }
    }
}
```

### Example 5: 禁用/启用功能

```swift
class ChatInputBar: UIView {
    
    func updateNetworkStatus(_ status: IMNetworkStatus) {
        switch status {
        case .wifi, .cellular:
            // 网络可用，启用所有功能
            textField.isEnabled = true
            sendButton.isEnabled = true
            attachButton.isEnabled = true
            
        case .unavailable:
            // 网络不可用，禁用发送功能
            textField.isEnabled = false
            sendButton.isEnabled = false
            attachButton.isEnabled = false
            textField.placeholder = "网络不可用"
            
        case .unknown:
            // 未知状态，谨慎处理
            textField.placeholder = "检查网络连接..."
        }
    }
}
```

---

## 性能优化

### 1. 避免频繁通知

```swift
// 添加防抖动
private var lastNotificationTime: TimeInterval = 0
private let notificationInterval: TimeInterval = 1.0  // 最少间隔 1 秒

private func handlePathUpdate(_ path: NWPath) {
    let now = Date().timeIntervalSince1970
    
    // 如果距离上次通知不到 1 秒，忽略
    guard now - lastNotificationTime >= notificationInterval else {
        return
    }
    
    lastNotificationTime = now
    
    // ... 处理状态变化
}
```

### 2. 减少电量消耗

```swift
// 在 App 进入后台时停止监听
extension IMClient {
    
    func applicationDidEnterBackground() {
        networkMonitor.stopMonitoring()
    }
    
    func applicationWillEnterForeground() {
        networkMonitor.startMonitoring()
    }
}
```

---

## 测试场景

### 1. WiFi 切换到蜂窝数据
```
Given: 设备连接到 WiFi
When: 关闭 WiFi，使用蜂窝数据
Then: 检测到状态变化，从 .wifi 到 .cellular
```

### 2. 开启飞行模式
```
Given: 设备有网络连接
When: 开启飞行模式
Then: 检测到网络断开，状态变为 .unavailable
      触发 networkDidDisconnect() 回调
```

### 3. 关闭飞行模式
```
Given: 飞行模式开启
When: 关闭飞行模式，网络恢复
Then: 检测到网络连接，状态变为 .wifi 或 .cellular
      触发 networkDidConnect() 回调
      自动重连 WebSocket
```

### 4. 进入地铁（信号弱）
```
Given: 在地面有良好的网络
When: 进入地铁，信号变弱或丢失
Then: 检测到网络质量下降或断开
      更新 UI 状态
```

---

## 总结

### 核心要点

1. ✅ **实时监听**：使用 Network Framework 实时监听
2. ✅ **自动重连**：网络恢复时自动重连 WebSocket
3. ✅ **状态更新**：及时更新 UI 和内部状态
4. ✅ **性能优化**：防抖动、后台暂停监听

### 预期效果

| 功能 | 效果 |
|------|------|
| 自动检测 | ✅ 实时检测网络变化 |
| 自动重连 | ✅ 网络恢复后自动重连 |
| 用户体验 | ⭐️⭐️⭐️⭐️⭐️ 无感知 |

---

**文档版本**：v1.0  
**创建时间**：2025-10-24  
**下一步**：开始实现代码


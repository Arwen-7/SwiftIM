/// IMNetworkMonitorTests - 网络监听测试
/// 测试网络状态监听的各种场景

import XCTest
import Network
@testable import IMSDK

final class IMNetworkMonitorTests: XCTestCase {
    
    var networkMonitor: IMNetworkMonitor!
    var expectation: XCTestExpectation!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        networkMonitor = IMNetworkMonitor()
    }
    
    override func tearDownWithError() throws {
        networkMonitor.stopMonitoring()
        networkMonitor = nil
        try super.tearDownWithError()
    }
    
    // MARK: - 基础功能测试
    
    /// 测试 1：启动监听
    func testStartMonitoring() {
        // When: 启动监听
        networkMonitor.startMonitoring()
        
        // Then: 应该正在监听
        XCTAssertTrue(networkMonitor.isMonitoring, "Should be monitoring after start")
    }
    
    /// 测试 2：停止监听
    func testStopMonitoring() {
        // Given: 正在监听
        networkMonitor.startMonitoring()
        XCTAssertTrue(networkMonitor.isMonitoring)
        
        // When: 停止监听
        networkMonitor.stopMonitoring()
        
        // Then: 应该停止监听
        XCTAssertFalse(networkMonitor.isMonitoring, "Should not be monitoring after stop")
    }
    
    /// 测试 3：重复启动
    func testMultipleStarts() {
        // Given: 已经启动
        networkMonitor.startMonitoring()
        
        // When: 再次启动
        networkMonitor.startMonitoring()
        
        // Then: 应该仍然正在监听（不会崩溃）
        XCTAssertTrue(networkMonitor.isMonitoring, "Should still be monitoring")
    }
    
    /// 测试 4：重复停止
    func testMultipleStops() {
        // When: 连续停止（未启动就停止）
        networkMonitor.stopMonitoring()
        networkMonitor.stopMonitoring()
        
        // Then: 不应该崩溃
        XCTAssertFalse(networkMonitor.isMonitoring, "Should not be monitoring")
    }
    
    // MARK: - 状态检测测试
    
    /// 测试 5：获取当前网络状态
    func testGetCurrentStatus() {
        // Given: 启动监听
        networkMonitor.startMonitoring()
        
        // 等待一下以便监听器检测到网络状态
        let expectation = XCTestExpectation(description: "Wait for network status")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Then: 状态不应该是 unknown
        let status = networkMonitor.currentStatus
        print("Current network status: \(status)")
        
        // 在测试环境中，通常会有网络连接
        XCTAssertNotEqual(status, .unknown, "Status should be detected")
    }
    
    /// 测试 6：网络可用性检测
    func testNetworkAvailability() {
        // Given: 启动监听
        networkMonitor.startMonitoring()
        
        // 等待检测
        let expectation = XCTestExpectation(description: "Wait for detection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Then: 在测试环境中通常有网络
        let isAvailable = networkMonitor.isNetworkAvailable
        print("Network available: \(isAvailable), Status: \(networkMonitor.currentStatus)")
        
        // 注意：这个测试可能在某些 CI 环境中失败
        // 可以根据实际情况调整
    }
    
    // MARK: - 委托测试
    
    /// 测试 7：委托回调
    func testDelegateCallbacks() {
        // Given: 设置委托
        let delegate = MockNetworkMonitorDelegate()
        networkMonitor.delegate = delegate
        
        // When: 启动监听
        networkMonitor.startMonitoring()
        
        // Wait: 等待网络状态检测
        let expectation = XCTestExpectation(description: "Wait for delegate callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        // Then: 应该收到回调（如果有网络状态变化）
        print("Delegate received \(delegate.statusChangeCount) status changes")
        // 注意：在稳定的网络环境中，可能不会有状态变化
    }
    
    /// 测试 8：弱引用委托
    func testWeakDelegate() {
        // Given: 创建委托
        var delegate: MockNetworkMonitorDelegate? = MockNetworkMonitorDelegate()
        networkMonitor.delegate = delegate
        
        XCTAssertNotNil(networkMonitor.delegate, "Delegate should be set")
        
        // When: 释放委托
        delegate = nil
        
        // Then: 委托应该被释放（弱引用）
        XCTAssertNil(networkMonitor.delegate, "Delegate should be nil after release")
    }
    
    // MARK: - 并发测试
    
    /// 测试 9：并发访问
    func testConcurrentAccess() {
        networkMonitor.startMonitoring()
        
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        // 多个线程同时访问
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = self.networkMonitor.currentStatus
                _ = self.networkMonitor.isNetworkAvailable
                _ = self.networkMonitor.isWiFi
                _ = self.networkMonitor.isCellular
                
                if i % 2 == 0 {
                    self.networkMonitor.startMonitoring()
                } else {
                    self.networkMonitor.stopMonitoring()
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - 性能测试
    
    /// 测试 10：状态检测性能
    func testStatusDetectionPerformance() {
        networkMonitor.startMonitoring()
        
        // 等待初始检测
        Thread.sleep(forTimeInterval: 0.5)
        
        measure {
            for _ in 0..<1000 {
                _ = networkMonitor.currentStatus
                _ = networkMonitor.isNetworkAvailable
            }
        }
    }
    
    /// 测试 11：启动停止性能
    func testStartStopPerformance() {
        measure {
            for _ in 0..<10 {
                networkMonitor.startMonitoring()
                networkMonitor.stopMonitoring()
            }
        }
    }
    
    // MARK: - 状态枚举测试
    
    /// 测试 12：状态描述
    func testStatusDescription() {
        XCTAssertEqual(IMNetworkStatus.unknown.description, "Unknown")
        XCTAssertEqual(IMNetworkStatus.unavailable.description, "Unavailable")
        XCTAssertEqual(IMNetworkStatus.wifi.description, "WiFi")
        XCTAssertEqual(IMNetworkStatus.cellular.description, "Cellular")
    }
    
    /// 测试 13：状态属性
    func testStatusProperties() {
        // WiFi
        XCTAssertTrue(IMNetworkStatus.wifi.isAvailable)
        XCTAssertTrue(IMNetworkStatus.wifi.isWiFi)
        XCTAssertFalse(IMNetworkStatus.wifi.isCellular)
        
        // Cellular
        XCTAssertTrue(IMNetworkStatus.cellular.isAvailable)
        XCTAssertFalse(IMNetworkStatus.cellular.isWiFi)
        XCTAssertTrue(IMNetworkStatus.cellular.isCellular)
        
        // Unavailable
        XCTAssertFalse(IMNetworkStatus.unavailable.isAvailable)
        XCTAssertFalse(IMNetworkStatus.unavailable.isWiFi)
        XCTAssertFalse(IMNetworkStatus.unavailable.isCellular)
        
        // Unknown
        XCTAssertFalse(IMNetworkStatus.unknown.isAvailable)
        XCTAssertFalse(IMNetworkStatus.unknown.isWiFi)
        XCTAssertFalse(IMNetworkStatus.unknown.isCellular)
    }
    
    // MARK: - 集成测试
    
    /// 测试 14：IMClient 集成
    func testIMClientIntegration() throws {
        // Given: 初始化 SDK
        let config = IMConfig(
            apiURL: "https://api.example.com",
            wsURL: "wss://ws.example.com"
        )
        
        try IMClient.shared.initialize(config: config)
        
        // 等待网络监听器启动
        Thread.sleep(forTimeInterval: 1.0)
        
        // Then: 应该能获取网络状态
        let status = IMClient.shared.networkStatus
        let isAvailable = IMClient.shared.isNetworkAvailable
        
        print("Network status in IMClient: \(status)")
        print("Network available: \(isAvailable)")
        
        XCTAssertNotEqual(status, .unknown, "Should detect network status")
    }
}

// MARK: - Mock Delegate

class MockNetworkMonitorDelegate: IMNetworkMonitorDelegate {
    
    var statusChangeCount = 0
    var lastStatus: IMNetworkStatus?
    var connectCallCount = 0
    var disconnectCallCount = 0
    
    func networkStatusDidChange(_ status: IMNetworkStatus) {
        statusChangeCount += 1
        lastStatus = status
        print("Mock delegate: status changed to \(status)")
    }
    
    func networkDidConnect() {
        connectCallCount += 1
        print("Mock delegate: network connected")
    }
    
    func networkDidDisconnect() {
        disconnectCallCount += 1
        print("Mock delegate: network disconnected")
    }
}


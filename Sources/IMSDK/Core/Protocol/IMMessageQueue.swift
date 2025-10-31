//
//  IMMessageQueue.swift
//  IMSDK
//
//  Created by Arwen on 2025/10/27.
//

import Foundation

// MARK: - Message Queue

/// 消息队列（保证消息可靠发送）
///
/// **设计说明：**
/// - 消息加入队列后，会尝试发送到 WebSocket
/// - 发送到 WebSocket 后，消息**仍保留在队列中**，等待服务器 ACK
/// - 收到 ACK 后，通过 `dequeue()` 从队列移除
/// - 如果发送失败（网络断开等），会自动重试
/// - 重试次数超限后，消息标记为失败并从队列移除
public final class IMMessageQueue {
    
    // MARK: - Queue Item
    
    private struct QueueItem {
        let message: IMMessage
        var retryCount: Int  // 重试次数（可变）
        let timestamp: Int64  // 消息创建时间
        var isSending: Bool  // 是否正在发送（避免重复发送）
        var lastSendTime: Int64  // 最后一次发送时间（用于 ACK 超时检测）
    }
    
    // MARK: - Properties
    
    private var queue: [QueueItem] = []
    private let lock = NSRecursiveLock()  // 使用递归锁，支持同一线程重复获取
    private let maxRetryCount = 3
    private let ackTimeout: Int64 = 5_000  // ACK 超时时间（5 秒，快速失败，参考微信）
    private var timeoutCheckTimer: Timer?
    
    // 回调
    public var onSendMessage: ((IMMessage) -> Bool)?  // 同步返回：true=成功提交，false=失败
    public var onMessageFailed: ((IMMessage) -> Void)?  // 消息发送失败回调
    
    // MARK: - Public Methods
    
    // MARK: - Lifecycle
    
    public init() {
        startTimeoutCheckTimer()
    }
    
    deinit {
        stopTimeoutCheckTimer()
    }
    
    /// 添加消息到队列
    public func enqueue(_ message: IMMessage) {
        lock.lock()
        defer { lock.unlock() }
        
        let item = QueueItem(
            message: message,
            retryCount: 0,
            timestamp: IMUtils.currentTimeMillis(),
            isSending: false,
            lastSendTime: 0
        )
        queue.append(item)
        
        IMLogger.shared.debug("Message enqueued: \(message.messageID), queue size: \(queue.count)")
        
        // 尝试发送
        tryProcessQueue()
    }
    
    /// 从队列中移除消息
    ///
    /// **重要：** 这个方法由 `handleMessageAck` 调用，收到服务器 ACK 后才移除
    public func dequeue(messageID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        queue.removeAll { $0.message.messageID == messageID }
        IMLogger.shared.debug("Message dequeued: \(messageID), queue size: \(queue.count)")
        
        // 移除后，继续处理队列中的其他消息
        tryProcessQueue()
    }
    
    /// 处理队列
    ///
    /// **逻辑说明：**
    /// - 遍历队列，找到未发送的消息
    /// - 调用 `onSendMessage` 提交到 WebSocket
    /// - 成功提交后，标记为 isSending，记录发送时间，**但不移除**
    /// - 等待服务器 ACK，收到后通过 `dequeue()` 移除
    /// - 如果提交失败（网络断开），重置 isSending，等待下次尝试
    /// - ACK 超时由 `checkTimeout()` 处理，超时后重新发送
    ///
    /// **并发安全：**
    /// - 使用 NSRecursiveLock 保证线程安全
    /// - 循环处理避免递归调用和栈溢出
    private func tryProcessQueue() {
        lock.lock()
        defer { lock.unlock() }
        
        // 循环处理队列中的消息，避免递归
        while true {
            // 找到第一个未发送的消息
            guard let index = queue.firstIndex(where: { !$0.isSending }) else {
                // 所有消息都在等待 ACK
                break
            }
            
            var item = queue[index]
            
            // 标记为正在发送
            item.isSending = true
            item.lastSendTime = IMUtils.currentTimeMillis()
            queue[index] = item
            
            IMLogger.shared.debug("Processing message: \(item.message.messageID), retry: \(item.retryCount)")
            
            // 发送消息（同步调用）
            let success = onSendMessage?(item.message) ?? false
            
            // 重新查找消息（可能已被移除）
            guard let currentIndex = queue.firstIndex(where: { $0.message.messageID == item.message.messageID }) else {
                // 消息已被移除（收到 ACK 了）
                continue  // 继续处理下一条
            }
            
            if success {
                // ✅ 成功提交到 WebSocket
                // ⚠️ 注意：不移除！等待服务器 ACK
                // 消息保持在队列中，isSending=true
                // 如果超时未收到 ACK，checkTimeout() 会处理重试
                IMLogger.shared.debug("Message submitted to WebSocket: \(item.message.messageID), waiting for ACK...")
                
                // 继续循环处理下一条
                continue
                
            } else {
                // ❌ 提交失败（网络断开等）
                // 不立即重试，而是重置状态，等待网络恢复或下次 tryProcessQueue 调用
                var currentItem = queue[currentIndex]
                currentItem.isSending = false  // 重置状态
                queue[currentIndex] = currentItem
                
                IMLogger.shared.warning("Message send failed (network issue): \(item.message.messageID), will retry when network recovers")
                
                // 提交失败，停止处理后续消息
                break
            }
        }
    }
    
    /// 启动超时检查定时器
    private func startTimeoutCheckTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.timeoutCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkTimeout()
            }
        }
    }
    
    /// 停止超时检查定时器
    private func stopTimeoutCheckTimer() {
        timeoutCheckTimer?.invalidate()
        timeoutCheckTimer = nil
    }
    
    /// 检查 ACK 超时
    ///
    /// **逻辑：**
    /// - 遍历队列中 isSending=true 的消息
    /// - 检查是否超过 ACK 超时时间（5 秒）
    /// - 超时的消息重置为 isSending=false，允许重新发送
    /// - 达到最大重试次数的消息标记为失败
    private func checkTimeout() {
        lock.lock()
        defer { lock.unlock() }
        
        let now = IMUtils.currentTimeMillis()
        var hasTimeout = false
        
        for i in 0..<queue.count {
            var item = queue[i]
            
            // 只检查正在等待 ACK 的消息
            guard item.isSending else { continue }
            
            let elapsed = now - item.lastSendTime
            
            if elapsed > ackTimeout {
                // ⏰ ACK 超时
                IMLogger.shared.warning("Message ACK timeout: \(item.message.messageID), elapsed: \(elapsed)ms, retry: \(item.retryCount)/\(maxRetryCount)")
                
                if item.retryCount < maxRetryCount {
                    // 重置状态，允许重新发送
                    item.isSending = false
                    item.retryCount += 1
                    queue[i] = item
                    hasTimeout = true
                    
                    IMLogger.shared.info("Will retry message: \(item.message.messageID)")
                } else {
                    // 达到最大重试次数，标记为失败
                    IMLogger.shared.error("Message failed after \(maxRetryCount) retries: \(item.message.messageID)")
                    
                    let failedMessage = item.message
                    queue.remove(at: i)
                    
                    // 通知上层消息发送失败
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessageFailed?(failedMessage)
                    }
                    
                    // 移除后索引变化，需要重新检查
                    return self.checkTimeout()
                }
            }
        }
        
        // 如果有超时的消息，尝试重新发送
        if hasTimeout {
            tryProcessQueue()
        }
    }
    
    /// WebSocket 重连后调用，重新发送队列中的消息
    public func onWebSocketReconnected() {
        lock.lock()
        defer { lock.unlock() }
        
        IMLogger.shared.info("WebSocket reconnected, resending messages in queue...")
        
        // 重置所有消息的 isSending 状态
        for i in 0..<queue.count {
            var item = queue[i]
            if item.isSending {
                item.isSending = false
                queue[i] = item
            }
        }
        
        // 重新发送
        tryProcessQueue()
    }
    
    /// 获取队列大小
    public var size: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count
    }
    
    /// 清空队列
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        queue.removeAll()
        IMLogger.shared.info("Message queue cleared")
    }
}

//
//  MessageLossDetectionExample.swift
//  IMSDK
//
//  消息丢失检测与恢复 - 使用示例
//

import Foundation

/// 示例 1：基本使用（自动检测，无需额外代码）
class BasicUsageExample {
    
    func example() {
        // ✅ 无需任何代码！
        // SDK 默认在以下时机自动检测消息丢失：
        // 1. 收到单条消息时
        // 2. 批量同步消息时
        
        // 检测到丢失后，SDK 会：
        // 1. 记录日志
        // 2. 自动触发补拉
        // 3. 重试机制（最多 3 次）
    }
}

/// 示例 2：自定义配置
class CustomConfigExample {
    
    let messageManager: IMMessageManager
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    func configureDetection() {
        // 创建自定义配置
        var config = IMMessageLossConfig()
        
        // 启用检测（默认已启用）
        config.enabled = true
        
        // 允许的最大 gap
        // gap = 1：连续（不丢失）
        // gap = 2：丢失 1 条消息
        // gap > maxAllowedGap 时才触发补拉
        config.maxAllowedGap = 1  // 推荐值
        
        // 单次补拉的最大消息数量
        config.maxPullCount = 100
        
        // 补拉失败后的重试次数
        config.maxRetryCount = 3
        
        // 重试间隔（秒）
        config.retryInterval = 2.0
        
        // 应用配置
        messageManager.configureLossDetection(config)
        
        print("✅ 消息丢失检测已配置")
    }
}

/// 示例 3：手动检测（高级用法）
class ManualDetectionExample {
    
    let messageManager: IMMessageManager
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    /// 手动检测单条消息
    func detectSingleMessage(_ message: IMMessage) {
        messageManager.checkMessageLoss(for: message) { lossInfo in
            if let lossInfo = lossInfo {
                // ⚠️ 检测到消息丢失
                print("""
                    消息丢失检测：
                    - 会话 ID: \(lossInfo.conversationID)
                    - 期望 seq: \(lossInfo.expectedSeq)
                    - 实际 seq: \(lossInfo.actualSeq)
                    - 丢失数量: \(lossInfo.lossCount)
                    - 丢失范围: \(lossInfo.missingRange)
                    """)
                
                // SDK 已自动触发补拉，这里可以做额外的 UI 提示
                self.showLossWarning(lossInfo: lossInfo)
            } else {
                // ✅ 消息连续，无丢失
                print("消息连续，seq: \(message.seq)")
            }
        }
    }
    
    /// 手动检测批量消息
    func detectBatchMessages(_ messages: [IMMessage]) {
        let lossInfoList = messageManager.checkBatchMessageLoss(messages: messages)
        
        if lossInfoList.isEmpty {
            // ✅ 批量消息连续，无丢失
            print("批量消息连续，共 \(messages.count) 条")
        } else {
            // ⚠️ 检测到丢失
            print("检测到 \(lossInfoList.count) 个会话的消息丢失：")
            
            for lossInfo in lossInfoList {
                print("""
                      - 会话: \(lossInfo.conversationID)
                      - 丢失数量: \(lossInfo.lossCount)
                      - 丢失范围: \(lossInfo.missingRange)
                    """)
            }
        }
    }
    
    private func showLossWarning(lossInfo: IMMessageLossInfo) {
        // 在 UI 上显示警告
        // 例如：Toast、Banner、状态栏提示等
    }
}

/// 示例 4：监控和统计
class MonitoringExample {
    
    let messageManager: IMMessageManager
    
    // 统计数据
    private var totalMessagesReceived: Int = 0
    private var totalLossDetected: Int = 0
    private var lossDetails: [IMMessageLossInfo] = []
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    /// 监控收到的消息
    func monitorIncomingMessage(_ message: IMMessage) {
        totalMessagesReceived += 1
        
        messageManager.checkMessageLoss(for: message) { [weak self] lossInfo in
            guard let self = self else { return }
            
            if let lossInfo = lossInfo {
                // 记录丢失
                self.totalLossDetected += Int(lossInfo.lossCount)
                self.lossDetails.append(lossInfo)
                
                // 上报到监控平台
                self.reportToMonitoring(lossInfo: lossInfo)
            }
        }
    }
    
    /// 获取统计报告
    func getStatistics() -> String {
        let lossRate = totalMessagesReceived > 0
            ? Double(totalLossDetected) / Double(totalMessagesReceived) * 100
            : 0
        
        return """
            消息丢失统计：
            - 总接收消息数: \(totalMessagesReceived)
            - 检测到丢失: \(totalLossDetected) 条
            - 丢失率: \(String(format: "%.2f", lossRate))%
            - 丢失事件: \(lossDetails.count) 次
            """
    }
    
    /// 获取最近的丢失详情
    func getRecentLossDetails(limit: Int = 10) -> [IMMessageLossInfo] {
        return Array(lossDetails.suffix(limit))
    }
    
    /// 重置统计
    func resetStatistics() {
        totalMessagesReceived = 0
        totalLossDetected = 0
        lossDetails.removeAll()
    }
    
    private func reportToMonitoring(lossInfo: IMMessageLossInfo) {
        // 上报到监控平台（如：Firebase、Sentry 等）
        // 示例：
        // Analytics.logEvent("message_loss_detected", parameters: [
        //     "conversation_id": lossInfo.conversationID,
        //     "loss_count": lossInfo.lossCount,
        //     "expected_seq": lossInfo.expectedSeq,
        //     "actual_seq": lossInfo.actualSeq
        // ])
    }
}

/// 示例 5：临时禁用检测（特殊场景）
class DisableDetectionExample {
    
    let messageManager: IMMessageManager
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    /// 在数据迁移时临时禁用检测
    func performDataMigration() {
        // 禁用检测
        var config = IMMessageLossConfig()
        config.enabled = false
        messageManager.configureLossDetection(config)
        
        print("⏸️ 消息丢失检测已禁用")
        
        // 执行数据迁移
        migrateHistoricalData()
        
        // 重新启用检测
        config.enabled = true
        messageManager.configureLossDetection(config)
        
        print("▶️ 消息丢失检测已恢复")
    }
    
    private func migrateHistoricalData() {
        // 迁移历史数据（可能导致 seq 不连续）
    }
}

/// 示例 6：处理不同会话的丢失
class MultiConversationExample {
    
    let messageManager: IMMessageManager
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    /// 同时监控多个会话
    func monitorMultipleConversations(messages: [IMMessage]) {
        // 按会话分组
        let grouped = Dictionary(grouping: messages) { $0.conversationID }
        
        print("监控 \(grouped.count) 个会话的消息：")
        
        for (conversationID, msgs) in grouped {
            print("- 会话 \(conversationID): \(msgs.count) 条消息")
            
            // 检测每个会话的丢失情况
            let lossInfoList = messageManager.checkBatchMessageLoss(messages: msgs)
            
            if !lossInfoList.isEmpty {
                for lossInfo in lossInfoList {
                    print("  ⚠️ 检测到丢失 \(lossInfo.lossCount) 条消息")
                }
            } else {
                print("  ✅ 消息连续")
            }
        }
    }
}

/// 示例 7：UI 集成
class UIIntegrationExample {
    
    let messageManager: IMMessageManager
    
    init(messageManager: IMMessageManager) {
        self.messageManager = messageManager
    }
    
    /// 在聊天界面显示丢失提示
    func handleIncomingMessage(_ message: IMMessage, in chatViewController: Any) {
        messageManager.checkMessageLoss(for: message) { [weak self] lossInfo in
            guard let self = self else { return }
            
            if let lossInfo = lossInfo {
                // 在主线程更新 UI
                DispatchQueue.main.async {
                    // 1. 显示系统提示消息
                    self.insertSystemMessage(
                        text: "检测到 \(lossInfo.lossCount) 条消息丢失，正在恢复...",
                        in: chatViewController
                    )
                    
                    // 2. 显示加载指示器
                    self.showLoadingIndicator(in: chatViewController)
                    
                    // 3. 等待补拉完成后刷新界面
                    self.waitForMessageRecovery(lossInfo: lossInfo) {
                        self.hideLoadingIndicator(in: chatViewController)
                        self.reloadMessages(in: chatViewController)
                        
                        // 显示成功提示
                        self.showToast(message: "✅ 消息已恢复")
                    }
                }
            }
        }
    }
    
    private func insertSystemMessage(text: String, in viewController: Any) {
        // 插入系统提示消息到聊天界面
    }
    
    private func showLoadingIndicator(in viewController: Any) {
        // 显示加载指示器
    }
    
    private func hideLoadingIndicator(in viewController: Any) {
        // 隐藏加载指示器
    }
    
    private func reloadMessages(in viewController: Any) {
        // 重新加载消息列表
    }
    
    private func showToast(message: String) {
        // 显示 Toast 提示
    }
    
    private func waitForMessageRecovery(lossInfo: IMMessageLossInfo, completion: @escaping () -> Void) {
        // 监听消息恢复完成
        // 可以通过消息监听器或轮询数据库实现
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            completion()
        }
    }
}

/// 示例 8：调试和日志
class DebuggingExample {
    
    func setupLogging() {
        // SDK 内部已经有详细的日志输出
        // 可以通过配置日志级别来控制输出
        
        // 示例日志输出：
        /*
         ⚠️ 消息丢失检测：
         - 会话: chat_123
         - 期望 seq: 101
         - 实际 seq: 105
         - 丢失数量: 4
         - 丢失范围: 101...104
         
         🔄 开始补拉丢失消息：
         - 会话: chat_123
         - seq 范围: 101...104
         - 数量: 4
         - 重试次数: 0
         
         ✅ 补拉成功：
         - 会话: chat_123
         - seq 范围: 101...104
         - 补拉数量: 4
         */
        
        // 如果需要自定义日志处理，可以：
        // 1. 在 checkMessageLoss 的回调中记录
        // 2. 实现自己的监控系统
        // 3. 上报到远程日志平台
    }
}


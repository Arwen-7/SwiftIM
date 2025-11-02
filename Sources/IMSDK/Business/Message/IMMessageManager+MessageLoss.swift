//
//  IMMessageManager+MessageLoss.swift
//  IMSDK
//
//  消息丢失检测与恢复
//  职责：
//  1. 检测消息 seq 的连续性
//  2. 发现 gap 时触发补拉
//  3. 统计和上报丢失率
//

import Foundation
import Alamofire

// MARK: - 消息丢失检测配置
public struct IMMessageLossConfig {
    /// 是否启用消息丢失检测
    public var enabled: Bool = true
    
    /// 允许的最大 gap（超过此值才补拉，避免频繁请求）
    /// 例如：gap = 1 表示丢了 0 条消息（连续），gap = 2 表示丢了 1 条消息
    public var maxAllowedGap: Int64 = 1
    
    /// 单次补拉的最大消息数量
    public var maxPullCount: Int = 100
    
    /// 补拉失败后的重试次数
    public var maxRetryCount: Int = 3
    
    /// 重试间隔（秒）
    public var retryInterval: TimeInterval = 2.0
    
    public init() {}
}

// MARK: - 消息丢失信息
public struct IMMessageLossInfo {
    /// 会话 ID
    public let conversationID: String
    
    /// 期望的 seq（本地最新 seq + 1）
    public let expectedSeq: Int64
    
    /// 实际收到的 seq
    public let actualSeq: Int64
    
    /// 丢失的消息数量
    public var lossCount: Int64 {
        return actualSeq - expectedSeq
    }
    
    /// 丢失的 seq 范围（闭区间）
    public var missingRange: ClosedRange<Int64> {
        return expectedSeq...actualSeq - 1
    }
}

// MARK: - 消息丢失检测
extension IMMessageManager {
    
    /// 消息丢失检测配置
    private static var lossConfig = IMMessageLossConfig()
    
    /// 配置消息丢失检测
    public func configureLossDetection(_ config: IMMessageLossConfig) {
        IMMessageManager.lossConfig = config
    }
    
    // MARK: - 检测单条消息的 seq 连续性
    
    /// 检测收到的消息是否有丢失
    /// - Parameters:
    ///   - message: 新收到的消息
    ///   - completion: 检测结果回调
    /// - Returns: 如果检测到丢失，返回丢失信息；否则返回 nil
    func checkMessageLoss(for message: IMMessage, completion: ((IMMessageLossInfo?) -> Void)? = nil) {
        guard IMMessageManager.lossConfig.enabled else {
            completion?(nil)
            return
        }
        
        // 在后台队列检测
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 获取该会话的本地最新消息
                guard let latestMessage = try self.database.getLatestMessage(conversationID: message.conversationID),
                      latestMessage.seq > 0 else {
                    // 本地没有消息，或者 seq 无效，无法检测
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                    return
                }
                
                let expectedSeq = latestMessage.seq + 1
                let actualSeq = message.seq
                let gap = actualSeq - expectedSeq
                
                // 检查是否有 gap
                if gap > IMMessageManager.lossConfig.maxAllowedGap {
                    let lossInfo = IMMessageLossInfo(
                        conversationID: message.conversationID,
                        expectedSeq: expectedSeq,
                        actualSeq: actualSeq
                    )
                    
                    IMLogger.shared.warning("""
                        ⚠️ 消息丢失检测：
                        - 会话: \(message.conversationID)
                        - 期望 seq: \(expectedSeq)
                        - 实际 seq: \(actualSeq)
                        - 丢失数量: \(lossInfo.lossCount)
                        - 丢失范围: \(lossInfo.missingRange)
                        """)
                    
                    // 回调通知
                    DispatchQueue.main.async {
                        completion?(lossInfo)
                    }
                    
                    // 触发补拉
                    self.requestMissingMessages(lossInfo: lossInfo)
                    
                } else if gap > 0 {
                    // gap 在允许范围内，但仍有丢失（例如 gap = 1，丢了 0 条）
                    IMLogger.shared.debug("""
                        ℹ️ 消息 seq 正常：
                        - 会话: \(message.conversationID)
                        - 期望 seq: \(expectedSeq)
                        - 实际 seq: \(actualSeq)
                        - gap: \(gap)（在允许范围内）
                        """)
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                    
                } else if gap < 0 {
                    // 收到的 seq 比本地更小，可能是乱序或重复消息
                    IMLogger.shared.warning("""
                        ⚠️ 收到乱序/重复消息：
                        - 会话: \(message.conversationID)
                        - 期望 seq: \(expectedSeq)
                        - 实际 seq: \(actualSeq)
                        - gap: \(gap)（负数）
                        """)
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                    
                } else {
                    // gap == 0，说明 seq 完全连续
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                }
                
            } catch {
                IMLogger.shared.error("消息丢失检测失败: \(error)")
                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }
    
    // MARK: - 检测批量消息的 seq 连续性
    
    /// 检测批量消息中的 seq gap
    /// - Parameter messages: 消息列表（需要按 seq 升序排列）
    /// - Returns: 所有检测到的 gap 信息
    func checkBatchMessageLoss(messages: [IMMessage]) -> [IMMessageLossInfo] {
        guard IMMessageManager.lossConfig.enabled else {
            return []
        }
        
        guard messages.count > 1 else {
            return []
        }
        
        // 按 conversationID 分组
        let grouped = Dictionary(grouping: messages) { $0.conversationID }
        
        var allLosses: [IMMessageLossInfo] = []
        
        for (conversationID, msgs) in grouped {
            // 按 seq 排序
            let sortedMsgs = msgs.sorted { $0.seq < $1.seq }
            
            // 检查相邻消息的 seq 连续性
            for i in 1..<sortedMsgs.count {
                let prevSeq = sortedMsgs[i - 1].seq
                let currentSeq = sortedMsgs[i].seq
                let gap = currentSeq - prevSeq
                
                if gap > 1 {
                    // 检测到 gap
                    let lossInfo = IMMessageLossInfo(
                        conversationID: conversationID,
                        expectedSeq: prevSeq + 1,
                        actualSeq: currentSeq
                    )
                    
                    IMLogger.shared.warning("""
                        ⚠️ 批量消息中检测到丢失：
                        - 会话: \(conversationID)
                        - 前一条 seq: \(prevSeq)
                        - 当前 seq: \(currentSeq)
                        - 丢失数量: \(lossInfo.lossCount)
                        """)
                    
                    allLosses.append(lossInfo)
                }
            }
        }
        
        return allLosses
    }
    
    // MARK: - 补拉丢失的消息
    
    /// 请求补拉丢失的消息
    /// - Parameters:
    ///   - lossInfo: 丢失信息
    ///   - retryCount: 当前重试次数（内部使用）
    private func requestMissingMessages(lossInfo: IMMessageLossInfo, retryCount: Int = 0) {
        IMLogger.shared.info("""
            🔄 开始补拉丢失消息：
            - 会话: \(lossInfo.conversationID)
            - seq 范围: \(lossInfo.missingRange)
            - 数量: \(lossInfo.lossCount)
            - 重试次数: \(retryCount)
            """)
        
        // 检查是否超过重试次数
        guard retryCount < IMMessageManager.lossConfig.maxRetryCount else {
            IMLogger.shared.error("""
                ❌ 补拉失败：超过最大重试次数
                - 会话: \(lossInfo.conversationID)
                - seq 范围: \(lossInfo.missingRange)
                """)
            return
        }
        
        // 调用增量同步接口补拉指定范围的消息
        guard let syncManager = IMClient.shared.messageSyncManager else {
            IMLogger.shared.error("❌ 补拉失败：IMMessageSyncManager 未初始化")
            return
        }
        
        // 使用增量同步接口，传入起始和结束 seq
        syncManager.syncMessagesInRange(
            conversationID: lossInfo.conversationID,
            startSeq: lossInfo.expectedSeq,
            endSeq: lossInfo.actualSeq - 1
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let pulledCount):
                IMLogger.shared.info("""
                    ✅ 补拉成功：
                    - 会话: \(lossInfo.conversationID)
                    - seq 范围: \(lossInfo.missingRange)
                    - 补拉数量: \(pulledCount)
                    """)
                
            case .failure(let error):
                IMLogger.shared.error("""
                    ❌ 补拉失败：
                    - 会话: \(lossInfo.conversationID)
                    - seq 范围: \(lossInfo.missingRange)
                    - 错误: \(error)
                    """)
                
                // 重试
                let nextRetryCount = retryCount + 1
                DispatchQueue.main.asyncAfter(deadline: .now() + IMMessageManager.lossConfig.retryInterval) {
                    self.requestMissingMessages(lossInfo: lossInfo, retryCount: nextRetryCount)
                }
            }
        }
    }
}

// MARK: - IMMessageSyncManager 扩展：范围同步
extension IMMessageSyncManager {
    
    /// 同步指定 seq 范围的消息（用于补拉丢失的消息）
    /// - Parameters:
    ///   - conversationID: 会话 ID（可选，如果指定则只同步该会话）
    ///   - startSeq: 起始 seq（包含）
    ///   - endSeq: 结束 seq（包含）
    ///   - completion: 完成回调，返回成功拉取的消息数量
    func syncMessagesInRange(
        conversationID: String? = nil,
        startSeq: Int64,
        endSeq: Int64,
        completion: @escaping (Result<Int, IMError>) -> Void
    ) {
        IMLogger.shared.info("""
            🔄 范围同步消息：
            - 会话: \(conversationID ?? "全局")
            - seq 范围: [\(startSeq), \(endSeq)]
            - 预计数量: \(endSeq - startSeq + 1)
            """)
        
        // 构造同步请求参数
        var params: [String: Any] = [
            "start_seq": startSeq,
            "end_seq": endSeq,
            "count": min(endSeq - startSeq + 1, 100)  // 限制单次拉取数量
        ]
        
        if let conversationID = conversationID {
            params["conversation_id"] = conversationID
        }
        
        // 创建请求对象
        struct SyncRangeRequest: IMRequest {
            let path: String
            let method: HTTPMethod
            let parameters: [String: Any]?
            let headers: HTTPHeaders?
        }
        
        let request = SyncRangeRequest(
            path: "/messages/sync_range",
            method: .post,
            parameters: params,
            headers: nil
        )
        
        // 定义响应数据结构
        struct SyncRangeData: Codable {
            struct MessageItem: Codable {
                let messageID: String?
                let conversationID: String?
                let senderID: String?
                let seq: Int64?
                let messageType: Int?
                let content: String?
                let createTime: Int64?
                let serverTime: Int64?
                let status: Int?
            }
            
            let messages: [MessageItem]
        }
        
        // 发送请求
        httpManager.request(request, responseType: SyncRangeData.self) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                guard response.isSuccess, let data = response.data else {
                    completion(.failure(.networkError(response.message)))
                    return
                }
                
                // 转换为 IMMessage 对象
                var messages: [IMMessage] = []
                for msgData in data.messages {
                    guard let messageID = msgData.messageID,
                          let conversationID = msgData.conversationID,
                          let senderID = msgData.senderID else {
                        continue
                    }
                    
                    let message = IMMessage()
                    message.messageID = messageID
                    message.conversationID = conversationID
                    message.senderID = senderID
                    message.seq = msgData.seq ?? 0
                    message.messageType = IMMessageType(rawValue: msgData.messageType ?? 1) ?? .text
                    message.content = msgData.content ?? ""
                    message.createTime = msgData.createTime ?? 0
                    message.serverTime = msgData.serverTime ?? 0
                    message.status = IMMessageStatus(rawValue: msgData.status ?? 1) ?? .sent
                    message.direction = .receive
                    
                    messages.append(message)
                }
                
                // 保存到数据库
                if !messages.isEmpty {
                    _ = try? self.database.saveMessages(messages)
                }
                
                IMLogger.shared.info("""
                    ✅ 范围同步成功：
                    - 请求范围: [\(startSeq), \(endSeq)]
                    - 实际拉取: \(messages.count) 条
                    """)
                
                completion(.success(messages.count))
                
            case .failure(let error):
                IMLogger.shared.error("范围同步请求失败: \(error)")
                completion(.failure(.networkError(error.localizedDescription)))
            }
        }
    }
}


/// IMMessageSyncManager - 消息增量同步管理器
/// 负责消息的增量同步、分批拉取、去重和进度管理

import Foundation
import Alamofire

/// 同步进度回调
public typealias IMSyncProgressHandler = (IMSyncProgress) -> Void

/// 同步完成回调
public typealias IMSyncCompletionHandler = (Result<Void, Error>) -> Void

/// 消息增量同步管理器
public final class IMMessageSyncManager {
    
    // MARK: - Properties
    
    internal let database: IMDatabaseProtocol
    internal let httpManager: IMHTTPManager
    private let messageManager: IMMessageManager
    private let userID: String
    
    /// 同步状态
    private var state: IMSyncState = .idle
    private let stateLock = NSLock()
    
    /// 同步配置
    private let batchSize: Int = 500  // 每批拉取数量
    private let maxRetryCount = 3     // 最大重试次数
    
    /// 同步回调
    public var onProgress: IMSyncProgressHandler?
    public var onStateChanged: ((IMSyncState) -> Void)?
    
    /// 当前同步任务
    private var currentSyncTask: DispatchWorkItem?
    
    // MARK: - Initialization
    
    public init(
        database: IMDatabaseProtocol,
        httpManager: IMHTTPManager,
        messageManager: IMMessageManager,
        userID: String
    ) {
        self.database = database
        self.httpManager = httpManager
        self.messageManager = messageManager
        self.userID = userID
    }
    
    // MARK: - Public Methods
    
    /// 开始增量同步
    /// - Parameters:
    ///   - force: 是否强制同步（即使正在同步中）
    ///   - completion: 完成回调
    public func startSync(force: Bool = false, completion: IMSyncCompletionHandler? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // 检查是否已在同步中
        if case .syncing = state, !force {
            IMLogger.shared.warning("Sync already in progress, skip")
            completion?(.success(()))
            return
        }
        
        // 更新状态
        updateState(.syncing)
        
        // 在后台线程执行同步
        let syncTask = DispatchWorkItem { [weak self] in
            self?.performSync(completion: completion)
        }
        
        currentSyncTask = syncTask
        DispatchQueue.global(qos: .userInitiated).async(execute: syncTask)
        
        IMLogger.shared.info("🔄 Sync started for user: \(userID)")
    }
    
    /// 停止同步
    public func stopSync() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        currentSyncTask?.cancel()
        currentSyncTask = nil
        
        updateState(.idle)
        
        // 更新数据库同步状态
        try? database.setSyncingState(userID: userID, isSyncing: false)
        
        IMLogger.shared.info("⏸️ Sync stopped for user: \(userID)")
    }
    
    /// 从指定序列号开始增量同步（重连后使用）
    /// - Parameters:
    ///   - fromSeq: 起始序列号
    ///   - completion: 完成回调
    public func sync(fromSeq: Int64, completion: IMSyncCompletionHandler? = nil) {
        stateLock.lock()
        
        // 检查是否已在同步中
        if case .syncing = state {
            stateLock.unlock()
            IMLogger.shared.warning("Sync already in progress, skip")
            completion?(.success(()))
            return
        }
        
        // 更新状态
        updateState(.syncing)
        stateLock.unlock()
        
        IMLogger.shared.info("🔄 Starting incremental sync from seq: \(fromSeq)")
        
        // 在后台线程执行同步
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.performIncrementalSync(fromSeq: fromSeq, completion: completion)
        }
    }
    
    /// 重置同步（清空本地 seq，重新全量同步）
    /// - Parameter completion: 完成回调
    public func resetSync(completion: IMSyncCompletionHandler? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // 停止当前同步
        currentSyncTask?.cancel()
        currentSyncTask = nil
        
        do {
            // 重置同步配置
            try database.resetSyncConfig(userID: userID)
            
            IMLogger.shared.info("♻️ Sync reset for user: \(userID)")
            
            // 开始全量同步
            startSync(force: true, completion: completion)
        } catch {
            IMLogger.shared.error("Failed to reset sync: \(error)")
            completion?(.failure(error))
        }
    }
    
    /// 获取同步状态
    public func getSyncState() -> IMSyncState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }
    
    // MARK: - Private Methods
    
    /// 执行增量同步（从指定 seq 开始）
    private func performIncrementalSync(fromSeq: Int64, completion: IMSyncCompletionHandler?) {
        let startTime = Date()
        
        IMLogger.shared.info("📊 Starting incremental sync from seq: \(fromSeq)")
        
        // 设置同步状态
        do {
            try database.setSyncingState(userID: userID, isSyncing: true)
        } catch {
            IMLogger.shared.error("Failed to set syncing state: \(error)")
        }
        
        // 开始分批同步（从指定 seq 开始）
        syncBatch(
            lastSeq: fromSeq,
            totalFetched: 0,
            totalCount: 0,
            currentBatch: 1,
            retryCount: 0,
            startTime: startTime,
            completion: completion
        )
    }
    
    /// 执行同步
    private func performSync(completion: IMSyncCompletionHandler?) {
        let startTime = Date()
        
        // 获取本地最后同步的 seq
        let syncConfig = database.getSyncConfig(userID: userID)
        let lastSeq = syncConfig?.lastSyncSeq ?? 0
        
        IMLogger.shared.info("📊 Starting sync from seq: \(lastSeq)")
        
        // 设置同步状态
        do {
            try database.setSyncingState(userID: userID, isSyncing: true)
        } catch {
            IMLogger.shared.error("Failed to set syncing state: \(error)")
        }
        
        // 开始分批同步
        syncBatch(
            lastSeq: lastSeq,
            totalFetched: 0,
            totalCount: 0,
            currentBatch: 1,
            retryCount: 0,
            startTime: startTime,
            completion: completion
        )
    }
    
    /// 同步一批消息
    private func syncBatch(
        lastSeq: Int64,
        totalFetched: Int,
        totalCount: Int64,
        currentBatch: Int,
        retryCount: Int,
        startTime: Date,
        completion: IMSyncCompletionHandler?
    ) {
        // 检查是否已取消
        guard currentSyncTask?.isCancelled == false else {
            IMLogger.shared.warning("Sync task cancelled")
            completion?(.success(()))
            return
        }
        
        IMLogger.shared.debug("📦 Fetching batch \(currentBatch), lastSeq: \(lastSeq), count: \(batchSize)")
        
        // 请求服务器
        self.syncMessages(lastSeq: lastSeq, count: batchSize) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                // 处理成功响应
                self.handleSyncSuccess(
                    response: response,
                    totalFetched: totalFetched,
                    totalCount: totalCount > 0 ? totalCount : response.totalCount,
                    currentBatch: currentBatch,
                    startTime: startTime,
                    completion: completion
                )
                
            case .failure(let error):
                // 处理错误
                self.handleSyncError(
                    error: error,
                    lastSeq: lastSeq,
                    totalFetched: totalFetched,
                    totalCount: totalCount,
                    currentBatch: currentBatch,
                    retryCount: retryCount,
                    startTime: startTime,
                    completion: completion
                )
            }
        }
    }
    
    /// 处理同步成功
    private func handleSyncSuccess(
        response: IMSyncResponse,
        totalFetched: Int,
        totalCount: Int64,
        currentBatch: Int,
        startTime: Date,
        completion: IMSyncCompletionHandler?
    ) {
        do {
            // 1. 检测批量消息中的 seq 丢失
            if !response.messages.isEmpty {
                let lossInfoList = messageManager.checkBatchMessageLoss(messages: response.messages)
                
                if !lossInfoList.isEmpty {
                    IMLogger.shared.warning("""
                        ⚠️ 批量同步中检测到 \(lossInfoList.count) 个会话的消息丢失：
                        \(lossInfoList.map { "[\($0.conversationID): gap=\($0.lossCount)]" }.joined(separator: ", "))
                        """)
                    // 注：批量同步中检测到的 gap 通常是服务器侧问题，记录日志即可
                    // 不需要触发补拉，因为补拉也可能返回同样的结果
                }
            }
            
            // 2. 保存消息到数据库（去重）
            if !response.messages.isEmpty {
                try database.saveMessages(response.messages)
                
                IMLogger.shared.info("💾 Batch \(currentBatch) saved: \(response.messages.count) messages")
            }
            
            // 3. 更新 lastSyncSeq
            if response.maxSeq > 0 {
                try database.updateLastSyncSeq(userID: userID, seq: response.maxSeq)
            }
            
            // 3. 计算进度
            let newTotalFetched = totalFetched + response.messages.count
            let progress = IMSyncProgress(
                currentCount: newTotalFetched,
                totalCount: totalCount,
                currentBatch: currentBatch
            )
            
            // 4. 通知进度
            DispatchQueue.main.async {
                self.onProgress?(progress)
            }
            
            IMLogger.shared.debug("📈 Progress: \(Int(progress.progress * 100))% (\(newTotalFetched)/\(totalCount))")
            
            // 5. 检查是否还有更多
            if response.hasMore {
                // 继续拉取下一批
                syncBatch(
                    lastSeq: response.maxSeq,
                    totalFetched: newTotalFetched,
                    totalCount: totalCount,
                    currentBatch: currentBatch + 1,
                    retryCount: 0,  // 重置重试次数
                    startTime: startTime,
                    completion: completion
                )
            } else {
                // 同步完成
                handleSyncCompleted(
                    totalFetched: newTotalFetched,
                    totalBatches: currentBatch,
                    startTime: startTime,
                    completion: completion
                )
            }
            
        } catch {
            IMLogger.shared.error("Failed to save sync data: \(error)")
            handleSyncError(
                error: error,
                lastSeq: response.maxSeq,
                totalFetched: totalFetched,
                totalCount: totalCount,
                currentBatch: currentBatch,
                retryCount: 0,
                startTime: startTime,
                completion: completion
            )
        }
    }
    
    /// 处理同步错误
    private func handleSyncError(
        error: Error,
        lastSeq: Int64,
        totalFetched: Int,
        totalCount: Int64,
        currentBatch: Int,
        retryCount: Int,
        startTime: Date,
        completion: IMSyncCompletionHandler?
    ) {
        IMLogger.shared.error("❌ Sync batch \(currentBatch) failed: \(error)")
        
        // 判断是否需要重试
        if retryCount < maxRetryCount {
            let delay = Double(retryCount + 1) * 2.0  // 2s, 4s, 6s
            
            IMLogger.shared.warning("⏳ Retrying in \(delay) seconds... (attempt \(retryCount + 1)/\(maxRetryCount))")
            
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncBatch(
                    lastSeq: lastSeq,
                    totalFetched: totalFetched,
                    totalCount: totalCount,
                    currentBatch: currentBatch,
                    retryCount: retryCount + 1,
                    startTime: startTime,
                    completion: completion
                )
            }
        } else {
            // 重试次数耗尽，同步失败
            updateState(.failed(error))
            
            // 更新数据库同步状态
            try? database.setSyncingState(userID: userID, isSyncing: false)
            
            IMLogger.shared.error("💔 Sync failed after \(maxRetryCount) retries: \(error)")
            
            DispatchQueue.main.async {
                completion?(.failure(error))
            }
        }
    }
    
    /// 处理同步完成
    private func handleSyncCompleted(
        totalFetched: Int,
        totalBatches: Int,
        startTime: Date,
        completion: IMSyncCompletionHandler?
    ) {
        let duration = Date().timeIntervalSince(startTime)
        
        // 更新状态
        updateState(.completed)
        
        // 更新数据库同步状态
        do {
            try database.setSyncingState(userID: userID, isSyncing: false)
        } catch {
            IMLogger.shared.error("Failed to update syncing state: \(error)")
        }
        
        // 记录性能指标
        let throughput = duration > 0 ? Double(totalFetched) / duration : 0
        IMLogger.shared.info("✅ Sync completed: \(totalFetched) messages, \(totalBatches) batches, \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) msg/s")
        
        // 性能监控（暂未实现）
        // IMLogger.performanceMonitor.recordAPILatency("syncMessages", duration: duration)
        
        // 通知完成
        DispatchQueue.main.async {
            completion?(.success(()))
        }
    }
    
    /// 更新状态
    private func updateState(_ newState: IMSyncState) {
        state = newState
        
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(newState)
        }
    }
}

// MARK: - Private Helper Methods

private extension IMMessageSyncManager {
    
    /// 增量同步消息
    /// - Parameters:
    ///   - lastSeq: 上次同步的最大 seq
    ///   - count: 本次拉取数量
    ///   - completion: 完成回调
    func syncMessages(
        lastSeq: Int64,
        count: Int,
        completion: @escaping (Result<IMSyncResponse, Error>) -> Void
    ) {
        // 创建请求对象
        struct SyncRequest: IMRequest {
            let path: String
            let method: HTTPMethod
            let parameters: [String: Any]?
            let headers: HTTPHeaders?
        }
        
        let request = SyncRequest(
            path: "/api/v1/messages/sync",
            method: .post,
            parameters: [
                "lastSeq": lastSeq,
                "count": count,
                "timestamp": IMUtils.currentTimeMillis()
            ],
            headers: nil
        )
        
        // 定义响应数据结构（使用 Codable）
        struct SyncData: Codable {
            struct MessageDict: Codable {
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
            
            let messages: [MessageDict]
            let maxSeq: Int64
            let hasMore: Bool
            let totalCount: Int64
        }
        
        // 发送请求
        httpManager.request(request, responseType: SyncData.self) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                guard response.isSuccess, let data = response.data else {
                    completion(.failure(IMError.unknown(response.message)))
                    return
                }
                
                // 转换为 IMMessage 对象
                let messages = data.messages.compactMap { msgData -> IMMessage? in
                    guard let messageID = msgData.messageID,
                          let conversationID = msgData.conversationID,
                          let senderID = msgData.senderID else {
                        return nil
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
                    
                    return message
                }
                
                let syncResponse = IMSyncResponse(
                    messages: messages,
                    maxSeq: data.maxSeq,
                    hasMore: data.hasMore,
                    totalCount: data.totalCount
                )
                
                completion(.success(syncResponse))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 解析消息（从 JSON）
    private func parseMessage(from dict: [String: Any]) -> IMMessage? {
        guard
            let messageID = dict["messageID"] as? String,
            let conversationID = dict["conversationID"] as? String,
            let senderID = dict["senderID"] as? String
        else {
            return nil
        }
        
        let message = IMMessage()
        message.messageID = messageID
        message.conversationID = conversationID
        message.senderID = senderID
        message.seq = dict["seq"] as? Int64 ?? 0
        message.messageType = IMMessageType(rawValue: dict["messageType"] as? Int ?? 1) ?? .text
        message.content = dict["content"] as? String ?? ""
        message.createTime = dict["createTime"] as? Int64 ?? 0
        message.serverTime = dict["serverTime"] as? Int64 ?? 0
        message.status = IMMessageStatus(rawValue: dict["status"] as? Int ?? 1) ?? .sent
        message.direction = .receive
        
        return message
    }
}



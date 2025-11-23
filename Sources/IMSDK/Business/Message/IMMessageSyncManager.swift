/// IMMessageSyncManager - 消息增量同步管理器（长连接版本）
/// 负责消息的增量同步、分批拉取、去重和进度管理
/// 通过 WebSocket/TCP 长连接实现实时同步

import Foundation

/// 同步进度回调
public typealias IMSyncProgressHandler = (IMSyncProgress) -> Void

/// 消息增量同步管理器
public final class IMMessageSyncManager {
    
    // MARK: - Properties
    
    internal let database: IMDatabaseProtocol
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
    
    /// 发送数据闭包（由 IMClient 设置）
    public var onSendData: ((Data, IMCommandType, @escaping (Result<Void, Error>) -> Void) -> Void)?
    
    /// 检查连接状态闭包（由 IMClient 设置）
    public var isConnected: (() -> Bool)?
    
    /// 当前同步任务
    private var currentSyncTask: DispatchWorkItem?
    
    /// 当前同步批次上下文（保护并发，一次只能有一个待处理的同步请求）
    private var currentBatchContext: SyncBatchContext?
    private let batchContextLock = NSLock()
    
    /// 同步批次上下文
    internal class SyncBatchContext {
        let id: UUID  // 唯一标识，用于超时判断
        let lastSeq: Int64
        let totalFetched: Int
        let totalCount: Int64
        let currentBatch: Int
        let retryCount: Int
        let startTime: Date
        var timeoutTimer: Timer?  // 超时定时器
        
        init(id: UUID, lastSeq: Int64, totalFetched: Int, totalCount: Int64, currentBatch: Int, retryCount: Int, startTime: Date) {
            self.id = id
            self.lastSeq = lastSeq
            self.totalFetched = totalFetched
            self.totalCount = totalCount
            self.currentBatch = currentBatch
            self.retryCount = retryCount
            self.startTime = startTime
        }
        
        /// 取消定时器
        func cancelTimer() {
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
        
        deinit {
            cancelTimer()
        }
    }
    
    /// 范围同步上下文（用于重试）
    private class SyncRangeContext {
        let requestId: String        // 请求唯一标识
        let conversationID: String?
        let startSeq: Int64
        let endSeq: Int64
        let retryCount: Int
        let retryHandler: (() -> Void)?  // 重试回调
        
        init(requestId: String, conversationID: String?, startSeq: Int64, endSeq: Int64, retryCount: Int, retryHandler: (() -> Void)?) {
            self.requestId = requestId
            self.conversationID = conversationID
            self.startSeq = startSeq
            self.endSeq = endSeq
            self.retryCount = retryCount
            self.retryHandler = retryHandler
        }
    }
    
    /// 保存正在进行的范围同步请求（key: requestId）
    private var syncRangeContexts = [String: SyncRangeContext]()
    private let rangeContextLock = NSLock()
    
    // MARK: - Initialization
    
    public init(
        database: IMDatabaseProtocol,
        messageManager: IMMessageManager,
        userID: String
    ) {
        self.database = database
        self.messageManager = messageManager
        self.userID = userID
    }
    
    // MARK: - Public Methods
    
    /// 开始增量同步
    /// - Parameter force: 是否强制同步（即使正在同步中）
    public func startSync(force: Bool = false) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // 检查是否已在同步中
        if case .syncing = state, !force {
            IMLogger.shared.warning("Sync already in progress, skip")
            return
        }
        
        // 如果 force=true 且正在同步，先停止旧的同步
        if force, case .syncing = state {
            IMLogger.shared.warning("⚠️ Force sync: stopping current sync task")
            
            // 取消旧任务
            currentSyncTask?.cancel()
            currentSyncTask = nil
            
            // 清理旧的 context（包括取消定时器），避免旧响应被处理
            batchContextLock.lock()
            currentBatchContext?.cancelTimer()
            currentBatchContext = nil
            batchContextLock.unlock()
        }
        
        // 更新状态
        updateState(.syncing)
        
        // 在后台线程执行同步
        let syncTask = DispatchWorkItem { [weak self] in
            self?.performSync()
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
        
        // 清理同步上下文（包括取消定时器）
        batchContextLock.lock()
        currentBatchContext?.cancelTimer()
        currentBatchContext = nil
        batchContextLock.unlock()
        
        updateState(.idle)
        
        // 更新数据库同步状态
        try? database.setSyncingState(userID: userID, isSyncing: false)
        
        IMLogger.shared.info("⏸️ Sync stopped for user: \(userID)")
    }
    
    /// 从指定序列号开始增量同步（重连后使用）
    /// - Parameter fromSeq: 起始序列号
    public func sync(fromSeq: Int64) {
        stateLock.lock()
        
        // 检查是否已在同步中
        if case .syncing = state {
            stateLock.unlock()
            IMLogger.shared.warning("Sync already in progress, skip")
            return
        }
        
        // 更新状态
        updateState(.syncing)
        stateLock.unlock()
        
        IMLogger.shared.info("🔄 Starting incremental sync from seq: \(fromSeq)")
        
        // 在后台线程执行同步
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.performIncrementalSync(fromSeq: fromSeq)
        }
    }
    
    /// 重置同步（清空本地 seq，重新全量同步）
    public func resetSync() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // 停止当前同步
        currentSyncTask?.cancel()
        currentSyncTask = nil
        
        // 清理同步上下文（包括取消定时器）
        batchContextLock.lock()
        currentBatchContext?.cancelTimer()
        currentBatchContext = nil
        batchContextLock.unlock()
        
        do {
            // 重置同步配置
            try database.resetSyncConfig(userID: userID)
            
            IMLogger.shared.info("♻️ Sync reset for user: \(userID)")
            
            // 开始全量同步
            startSync(force: true)
        } catch {
            IMLogger.shared.error("Failed to reset sync: \(error)")
            updateState(.failed(error))
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
    private func performIncrementalSync(fromSeq: Int64) {
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
            startTime: startTime
        )
    }
    
    /// 执行同步
    private func performSync() {
        let startTime = Date()
        
        // 获取本地最后同步的 seq
        let syncConfig = database.getSyncConfig(userID: userID)
        let lastSeq = syncConfig?.lastSyncSeq ?? 0
        
        if lastSeq == 0 {
            IMLogger.shared.info("📊 Starting FULL sync (lastSeq=0, first time sync)")
        } else {
            IMLogger.shared.info("📊 Starting INCREMENTAL sync from seq: \(lastSeq)")
        }
        
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
            startTime: startTime
        )
    }
    
    /// 同步一批消息
    private func syncBatch(
        lastSeq: Int64,
        totalFetched: Int,
        totalCount: Int64,
        currentBatch: Int,
        retryCount: Int,
        startTime: Date
    ) {
        // 检查是否已取消
        guard currentSyncTask?.isCancelled == false else {
            IMLogger.shared.warning("Sync task cancelled")
            return
        }
        
        IMLogger.shared.debug("📦 Fetching batch \(currentBatch), lastSeq: \(lastSeq), count: \(batchSize)")
        
        // 保存当前批次上下文
        let context = SyncBatchContext(
            id: UUID(),  // 生成唯一标识
            lastSeq: lastSeq,
            totalFetched: totalFetched,
            totalCount: totalCount,
            currentBatch: currentBatch,
            retryCount: retryCount,
            startTime: startTime
        )
        
        batchContextLock.lock()
        // 取消旧 context 的定时器
        currentBatchContext?.cancelTimer()
        currentBatchContext = context
        batchContextLock.unlock()
        
        // 发送同步请求（不等待响应）
        syncMessages(lastSeq: lastSeq, count: batchSize, context: context)
    }
    
    /// 处理同步成功
        private func handleSyncSuccess(
            response: IMSyncResponse,
            totalFetched: Int,
            totalCount: Int64,
            currentBatch: Int,
            startTime: Date
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
                
                // ✅ 通知 messageManager 批量处理同步的消息（会触发 UI 更新）
                messageManager.handleSyncedMessages(response.messages)
            }
            
            // 3. 更新 lastSyncSeq
            if response.maxSeq > 0 {
                try database.updateLastSyncSeq(userID: userID, seq: response.maxSeq)
                IMLogger.shared.info("✅ Updated lastSyncSeq to: \(response.maxSeq)")
            } else {
                IMLogger.shared.warning("⚠️ Sync response maxSeq=0, skip updating lastSyncSeq")
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
                    startTime: startTime
                )
            } else {
                // 同步完成
                handleSyncCompleted(
                    totalFetched: newTotalFetched,
                    totalBatches: currentBatch,
                    startTime: startTime
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
                startTime: startTime
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
        startTime: Date
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
                    startTime: startTime
                )
            }
        } else {
            // 重试次数耗尽，同步失败
            updateState(.failed(error))
            
            // 更新数据库同步状态
            try? database.setSyncingState(userID: userID, isSyncing: false)
            
            IMLogger.shared.error("💔 Sync failed after \(maxRetryCount) retries: \(error)")
        }
    }
    
    /// 处理同步完成
    private func handleSyncCompleted(
        totalFetched: Int,
        totalBatches: Int,
        startTime: Date
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
    
    /// 发送同步请求（不等待响应）
    /// - Parameters:
    ///   - lastSeq: 上次同步的最大 seq
    ///   - count: 本次拉取数量
    ///   - context: 同步批次上下文
    func syncMessages(lastSeq: Int64, count: Int, context: SyncBatchContext) {
        guard isConnected?() == true else {
            IMLogger.shared.error("Transport not connected, sync failed")
            handleSyncFailure(error: IMError.notConnected, contextID: context.id)
            return
        }
        
        guard let sendData = onSendData else {
            IMLogger.shared.error("onSendData callback not set")
            handleSyncFailure(error: IMError.notInitialized, contextID: context.id)
            return
        }
        
        // 创建同步请求（使用 Protobuf）
        var syncReq = Im_Protocol_SyncRequest()
        syncReq.lastSeq = lastSeq
        syncReq.count = Int32(count)
        syncReq.timestamp = IMUtils.currentTimeMillis()
        
        do {
            let requestData = try syncReq.serializedData()
            
            // 发送同步请求（通过闭包，序列号由 transport 内部生成）
            sendData(requestData, .syncReq) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success:
                    IMLogger.shared.debug("Sync request sent via long connection (lastSeq=\(lastSeq), count=\(count))")
                    
                    // 启动超时定时器（30秒）
                    let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self, weak context] _ in
                        guard let self = self, let context = context else { return }
                        
                        // 检查 context 是否匹配（避免超时处理错误的请求）
                        self.batchContextLock.lock()
                        let shouldTimeout = self.currentBatchContext?.id == context.id
                        self.batchContextLock.unlock()
                        
                        if shouldTimeout {
                            IMLogger.shared.warning("Sync request timeout (contextID: \(context.id))")
                            self.handleSyncFailure(error: IMError.timeout, contextID: context.id)
                        } else {
                            IMLogger.shared.debug("Timeout fired but context already changed, ignore (contextID: \(context.id))")
                        }
                    }
                    
                    // 保存定时器到 context
                    context.timeoutTimer = timer
                    
                case .failure(let error):
                    IMLogger.shared.error("Failed to send sync request: \(error)")
                    self.handleSyncFailure(error: error, contextID: context.id)
                }
            }
        } catch {
            IMLogger.shared.error("Failed to serialize sync request: \(error)")
            handleSyncFailure(error: error, contextID: context.id)
        }
    }
    
    /// 处理同步失败
    /// - Parameters:
    ///   - error: 错误信息
    ///   - contextID: 上下文唯一标识（用于验证是否是当前请求）
    private func handleSyncFailure(error: Error, contextID: UUID) {
        batchContextLock.lock()
        guard let context = currentBatchContext, context.id == contextID else {
            batchContextLock.unlock()
            IMLogger.shared.debug("handleSyncFailure: context mismatch or already cleared (contextID: \(contextID))")
            return
        }
        // 取消定时器
        context.cancelTimer()
        currentBatchContext = nil
        batchContextLock.unlock()
        
        // 处理错误（重试或失败）
        handleSyncError(
            error: error,
            lastSeq: context.lastSeq,
            totalFetched: context.totalFetched,
            totalCount: context.totalCount,
            currentBatch: context.currentBatch,
            retryCount: context.retryCount,
            startTime: context.startTime
        )
    }
}

// MARK: - Internal Methods for Response Handling

extension IMMessageSyncManager {
    
    /// 处理长连接同步响应（由 IMClient 通过 messageRouter 调用）
    /// - Parameters:
    ///   - response: 同步响应（Protobuf）
    ///   - sequence: 序列号（用于日志）
    internal func handleSyncResponse(_ response: Im_Protocol_SyncResponse, sequence: UInt32) {
        batchContextLock.lock()
        guard let context = currentBatchContext else {
            batchContextLock.unlock()
            IMLogger.shared.warning("Received sync response but no pending request (seq=\(sequence))")
            return
        }
        // 取消定时器（请求已完成）
        context.cancelTimer()
        currentBatchContext = nil
        batchContextLock.unlock()
        
        // 检查错误码
        guard response.errorCode == .errSuccess else {
            IMLogger.shared.error("Sync response error: \(response.errorMsg)")
            handleSyncError(
                error: IMError.unknown(response.errorMsg),
                lastSeq: context.lastSeq,
                totalFetched: context.totalFetched,
                totalCount: context.totalCount,
                currentBatch: context.currentBatch,
                retryCount: context.retryCount,
                startTime: context.startTime
            )
            return
        }
        
        // 转换为 IMMessage 对象（✅ 使用 MessageInfo 结构）
        let messages = response.messages.compactMap { msgInfo -> IMMessage? in
            guard !msgInfo.messageID.isEmpty,
                  !msgInfo.conversationID.isEmpty,
                  !msgInfo.senderID.isEmpty else {
                return nil
            }
            
            let message = IMMessage()
            message.messageID = msgInfo.messageID
            message.conversationID = msgInfo.conversationID
            message.senderID = msgInfo.senderID
            message.seq = msgInfo.seq
            message.messageType = IMMessageType(rawValue: Int(msgInfo.messageType)) ?? .text
            message.content = String(data: msgInfo.content, encoding: .utf8) ?? ""  // ✅ Data -> String
            message.createTime = msgInfo.createTime  // ✅ 创建时间
            message.serverTime = msgInfo.serverTime
            message.sendTime = msgInfo.sendTime      // ✅ 发送时间（UI显示）
            message.status = IMMessageStatus(rawValue: Int(msgInfo.status)) ?? .sent
            
            // ✅ 根据 senderID 判断消息方向
            message.direction = (msgInfo.senderID == self.userID) ? .send : .receive
            
            // ✅ 使用服务端返回的已读状态
            message.isRead = msgInfo.isRead
            
            return message
        }
        
        let syncResponse = IMSyncResponse(
            messages: messages,
            maxSeq: response.maxSeq,
            hasMore: response.hasMore_p,
            totalCount: response.totalCount
        )
        
        IMLogger.shared.info("Sync response received (seq=\(sequence), messages=\(messages.count), maxSeq=\(response.maxSeq), hasMore=\(response.hasMore_p))")
        
        // 继续处理同步成功
        handleSyncSuccess(
            response: syncResponse,
            totalFetched: context.totalFetched,
            totalCount: context.totalCount > 0 ? context.totalCount : syncResponse.totalCount,
            currentBatch: context.currentBatch,
            startTime: context.startTime
        )
    }
}

// MARK: - Range Sync (范围同步，用于补拉丢失的消息)

extension IMMessageSyncManager {
    
    /// 同步指定 seq 范围的消息（用于补拉丢失的消息）
    /// - Parameters:
    ///   - conversationID: 会话 ID（可选，如果指定则只同步该会话）
    ///   - startSeq: 起始 seq（包含）
    ///   - endSeq: 结束 seq（包含）
    ///   - retryCount: 重试次数
    ///   - retryHandler: 重试回调（失败时调用）
    public func syncMessagesInRange(
        conversationID: String? = nil,
        startSeq: Int64,
        endSeq: Int64,
        retryCount: Int = 0,
        retryHandler: (() -> Void)? = nil
    ) {
        // 生成唯一请求ID
        let requestId = UUID().uuidString
        
        IMLogger.shared.info("""
            🔄 范围同步消息（长连接）：
            - 请求ID: \(requestId)
            - 会话: \(conversationID ?? "全局")
            - seq 范围: [\(startSeq), \(endSeq)]
            - 预计数量: \(endSeq - startSeq + 1)
            - 重试次数: \(retryCount)
            """)
        
        // 检查连接状态
        guard isConnected?() == true else {
            IMLogger.shared.error("连接未建立，无法发送范围同步请求")
            // 触发重试
            retryHandler?()
            return
        }
        
        // 保存上下文（用于响应回来时重试）
        let context = SyncRangeContext(
            requestId: requestId,
            conversationID: conversationID,
            startSeq: startSeq,
            endSeq: endSeq,
            retryCount: retryCount,
            retryHandler: retryHandler
        )
        
        rangeContextLock.lock()
        syncRangeContexts[requestId] = context  // ✅ 直接用 requestId 作为 key
        rangeContextLock.unlock()
        
        // 创建范围同步请求（使用 Protobuf）
        var syncRangeReq = Im_Protocol_SyncRangeRequest()
        syncRangeReq.requestID = requestId  // ✅ 设置 requestId
        syncRangeReq.startSeq = startSeq
        syncRangeReq.endSeq = endSeq
        syncRangeReq.count = Int32(min(endSeq - startSeq + 1, 100))  // 限制单次拉取数量
        if let conversationID = conversationID {
            syncRangeReq.conversationID = conversationID
        }
        
        do {
            let requestData = try syncRangeReq.serializedData()
            
            // 发送范围同步请求（不等待响应，响应通过 messageRouter 处理）
            guard let sendData = onSendData else {
                IMLogger.shared.error("onSendData callback not set")
                // 触发重试
                retryHandler?()
                return
            }
            
            sendData(requestData, .syncRangeReq) { result in
                switch result {
                case .success:
                    IMLogger.shared.debug("范围同步请求已发送 (startSeq=\(startSeq), endSeq=\(endSeq))")
                case .failure(let error):
                    IMLogger.shared.error("发送范围同步请求失败: \(error)")
                    // 触发重试
                    retryHandler?()
                }
            }
        } catch {
            IMLogger.shared.error("序列化范围同步请求失败: \(error)")
            // 触发重试
            retryHandler?()
        }
    }
    
    /// 处理范围同步响应（由 IMClient 通过 messageRouter 调用）
    /// - Parameters:
    ///   - response: 范围同步响应（Protobuf）
    ///   - sequence: 序列号
    internal func handleSyncRangeResponse(_ response: Im_Protocol_SyncRangeResponse, sequence: UInt32) {
        // 从响应中获取 requestId（唯一标识）
        let requestId = response.requestID
        
        // 根据 requestId 直接查找上下文（O(1) 时间复杂度）
        rangeContextLock.lock()
        let context = syncRangeContexts.removeValue(forKey: requestId)  // ✅ 直接查找并移除
        rangeContextLock.unlock()
        
        guard let context = context else {
            IMLogger.shared.warning("收到范围同步响应但找不到对应的上下文 (requestId=\(requestId), seq=\(sequence))")
            return
        }
        
        let conversationID = response.conversationID.isEmpty ? nil : response.conversationID
        
        // 检查错误码
        guard response.errorCode == .errSuccess else {
            IMLogger.shared.error("范围同步响应错误 (requestId=\(requestId)): \(response.errorMsg)")
            // 触发重试
            context.retryHandler?()
            return
        }
        
        // 转换为 IMMessage 对象（✅ 使用 MessageInfo 结构）
        let messages = response.messages.compactMap { msgInfo -> IMMessage? in
            guard !msgInfo.messageID.isEmpty,
                  !msgInfo.conversationID.isEmpty,
                  !msgInfo.senderID.isEmpty else {
                return nil
            }
            
            let message = IMMessage()
            message.messageID = msgInfo.messageID
            message.conversationID = msgInfo.conversationID
            message.senderID = msgInfo.senderID
            message.seq = msgInfo.seq
            message.messageType = IMMessageType(rawValue: Int(msgInfo.messageType)) ?? .text
            message.content = String(data: msgInfo.content, encoding: .utf8) ?? ""  // ✅ Data -> String
            message.createTime = msgInfo.createTime  // ✅ 创建时间
            message.serverTime = msgInfo.serverTime
            message.sendTime = msgInfo.sendTime      // ✅ 发送时间（UI显示）
            message.status = IMMessageStatus(rawValue: Int(msgInfo.status)) ?? .sent
            
            // ✅ 根据 senderID 判断消息方向
            message.direction = (msgInfo.senderID == self.userID) ? .send : .receive
            
            // ✅ 使用服务端返回的已读状态
            message.isRead = msgInfo.isRead
            
            return message
        }
        
        // 保存到数据库
        if !messages.isEmpty {
            _ = try? database.saveMessages(messages)
            
            // ✅ 通知 messageManager 批量处理同步的消息（会触发 UI 更新）
            messageManager.handleSyncedMessages(messages)
        }
        
        IMLogger.shared.info("""
            ✅ 范围同步成功：
            - 请求ID: \(requestId)
            - 会话: \(conversationID ?? "全局")
            - 请求范围: [\(response.startSeq), \(response.endSeq)]
            - 实际拉取: \(messages.count) 条
            - 还有更多: \(response.hasMore_p)
            """)
        
        // 如果还有更多，继续拉取（会生成新的 requestId）
        if response.hasMore_p {
            IMLogger.shared.debug("继续拉取下一批范围同步数据...")
            syncMessagesInRange(
                conversationID: conversationID,
                startSeq: response.endSeq + 1,
                endSeq: context.endSeq,
                retryCount: context.retryCount,
                retryHandler: context.retryHandler
            )
        }
    }
}



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
    
    /// 当前批量同步上下文
    private var currentBatchSyncContext: BatchSyncContext?
    private let batchSyncContextLock = NSLock()
    
    /// 批量同步上下文
    internal class BatchSyncContext {
        let id: UUID
        let startTime: Date
        let retryCount: Int  // 重试次数
        var timeoutTimer: Timer?  // 超时定时器
        
        init(id: UUID, startTime: Date, retryCount: Int = 0) {
            self.id = id
            self.startTime = startTime
            self.retryCount = retryCount
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
            
            // 清理旧的批量同步上下文（取消定时器）
            batchSyncContextLock.lock()
            currentBatchSyncContext?.cancelTimer()
            currentBatchSyncContext = nil
            batchSyncContextLock.unlock()
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
    
    /// 停止同步（只停止批量同步，不影响范围同步）
    public func stopSync() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        currentSyncTask?.cancel()
        currentSyncTask = nil
        
        // 清理批量同步上下文（取消定时器）
        batchSyncContextLock.lock()
        currentBatchSyncContext?.cancelTimer()
        currentBatchSyncContext = nil
        batchSyncContextLock.unlock()
        
        updateState(.idle)
        
        // 更新数据库同步状态
        try? database.setSyncingState(userID: userID, isSyncing: false)
        
        IMLogger.shared.info("⏸️ Sync stopped for user: \(userID)")
    }
    
    /// 清理所有范围同步（内部方法，供登出或切换账号时使用）
    internal func clearAllRangeSync() {
        // 清理所有范围同步上下文（取消定时器）
        Self.rangeContextLock.lock()
        for context in Self.syncRangeContexts.values {
            context.cancelTimer()
        }
        Self.syncRangeContexts.removeAll()
        Self.rangeContextLock.unlock()
        
        // 取消所有待执行的范围同步重试任务
        Self.retryTaskLock.lock()
        for task in Self.pendingRetryTasks.values {
            task.cancel()
        }
        Self.pendingRetryTasks.removeAll()
        Self.retryTaskLock.unlock()
        
        IMLogger.shared.debug("🧹 All range sync tasks cleared")
    }
    
    /// 重置同步（清空本地 seq，重新全量同步）
    public func resetSync() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // 停止当前同步
        currentSyncTask?.cancel()
        currentSyncTask = nil
        
        // 清理批量同步上下文（取消定时器）
        batchSyncContextLock.lock()
        currentBatchSyncContext?.cancelTimer()
        currentBatchSyncContext = nil
        batchSyncContextLock.unlock()
        
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
    
    /// 执行同步（批量同步：一次请求完成所有会话同步）
    private func performSync(retryCount: Int = 0) {
        // ✅ 检查 currentSyncTask 是否被取消（用于重试场景）
        if let task = currentSyncTask, task.isCancelled {
            IMLogger.shared.debug("Sync task was cancelled, skip execution")
            return
        }
        
        let startTime = Date()
        
        IMLogger.shared.info("📊 Starting batch sync (retry: \(retryCount))")
        
        // 设置同步状态
        do {
            try database.setSyncingState(userID: userID, isSyncing: true)
        } catch {
            IMLogger.shared.error("Failed to set syncing state: \(error)")
        }
        
        // 保存批量同步上下文
        let context = BatchSyncContext(
            id: UUID(),
            startTime: startTime,
            retryCount: retryCount
        )
        
        batchSyncContextLock.lock()
        currentBatchSyncContext = context
        batchSyncContextLock.unlock()
        
        // 发送批量同步请求（不等待响应）
        sendBatchSyncRequest(context: context)
    }
    
    /// 发送批量同步请求
    private func sendBatchSyncRequest(context: BatchSyncContext) {
        // 从数据库获取同步配置，读取每个会话的 lastSeq
        let syncConfig = database.getSyncConfig(userID: userID)
        var conversationStates: [Im_Protocol_ConversationSyncState] = []
        
        if let config = syncConfig, !config.conversationStates.isEmpty {
            // 有本地状态，发送增量同步请求
            for (conversationID, state) in config.conversationStates {
                var protoState = Im_Protocol_ConversationSyncState()
                protoState.conversationID = conversationID
                protoState.lastSeq = state.maxSeq
                conversationStates.append(protoState)
            }
            IMLogger.shared.info("📤 Sending batch sync request (incremental) with \(conversationStates.count) conversation states")
        } else {
            // 无本地状态，发送全量同步请求（conversationStates 为空）
            IMLogger.shared.info("📤 Sending batch sync request (full sync)")
        }
        
        // 构造批量同步请求
        var request = Im_Protocol_BatchSyncRequest()
        request.conversationStates = conversationStates
        request.maxCountPerConversation = 100  // 每个会话最多100条
        
        // 序列化
        guard let requestData = try? request.serializedData() else {
            IMLogger.shared.error("Failed to serialize batch sync request")
            handleBatchSyncFailure(error: IMError.invalidData, contextID: context.id)
            return
        }
        
        // 发送请求（不等待响应，响应会通过 handleBatchSyncResponse 处理）
        onSendData?(requestData, .batchSyncReq) { [weak self, weak context] result in
            guard let self = self, let context = context else { return }
            
            switch result {
            case .success:
                IMLogger.shared.debug("Batch sync request sent")
                
                // 启动超时定时器（30秒）
                let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self, weak context] _ in
                    guard let self = self, let context = context else { return }
                    
                    // 检查 context 是否匹配（避免超时处理错误的请求）
                    self.batchSyncContextLock.lock()
                    let shouldTimeout = self.currentBatchSyncContext?.id == context.id
                    self.batchSyncContextLock.unlock()
                    
                    if shouldTimeout {
                        IMLogger.shared.warning("Batch sync request timeout (contextID: \(context.id))")
                        self.handleBatchSyncFailure(error: IMError.timeout, contextID: context.id)
                    } else {
                        IMLogger.shared.debug("Timeout fired but context already changed, ignore (contextID: \(context.id))")
                    }
                }
                
                // 保存定时器到 context
                context.timeoutTimer = timer
                
            case .failure(let error):
                IMLogger.shared.error("Failed to send batch sync request: \(error)")
                self.handleBatchSyncFailure(error: error, contextID: context.id)
            }
        }
    }
    
    /// 处理批量同步失败
    private func handleBatchSyncFailure(error: Error, contextID: UUID) {
        batchSyncContextLock.lock()
        guard let context = currentBatchSyncContext, context.id == contextID else {
            batchSyncContextLock.unlock()
            IMLogger.shared.debug("handleBatchSyncFailure: context mismatch")
            return
        }
        // 取消超时定时器
        context.cancelTimer()
        let retryCount = context.retryCount
        currentBatchSyncContext = nil
        batchSyncContextLock.unlock()
        
        IMLogger.shared.error("❌ Batch sync failed (retry: \(retryCount)): \(error)")
        
        // 判断是否需要重试
        if retryCount < maxRetryCount {
            let delay = Double(retryCount + 1) * 2.0  // 2s, 4s, 6s
            
            IMLogger.shared.warning("⏳ Retrying batch sync in \(delay) seconds... (attempt \(retryCount + 1)/\(maxRetryCount))")
            
            // ✅ 使用 DispatchWorkItem 创建可取消的重试任务
            let retryTask = DispatchWorkItem { [weak self] in
                // 检查任务是否被取消
                guard let self = self else { return }
                
                // 再次检查状态，确保用户没有主动停止同步
                self.stateLock.lock()
                let currentState = self.state
                self.stateLock.unlock()
                
                // 只有在非空闲状态下才执行重试
                if case .idle = currentState {
                    IMLogger.shared.debug("Retry cancelled because sync was stopped")
                    return
                }
                
                self.performSync(retryCount: retryCount + 1)
            }
            
            // 保存到 currentSyncTask，以便可以被 stopSync() 取消
            stateLock.lock()
            currentSyncTask = retryTask
            stateLock.unlock()
            
            // 延迟执行
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: retryTask)
        } else {
            // 重试次数耗尽，同步失败
            IMLogger.shared.error("💔 Batch sync failed after \(maxRetryCount) retries: \(error)")
            updateState(.failed(error))
            
            // 清理同步状态
            try? database.setSyncingState(userID: userID, isSyncing: false)
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

// MARK: - Range Sync (范围同步，用于补拉丢失的消息)

extension IMMessageSyncManager {
    
    /// 范围同步上下文（用于超时管理）
    private class SyncRangeContext {
        let requestId: String
        let conversationID: String
        let startSeq: Int64
        let endSeq: Int64
        let retryCount: Int
        var timeoutTimer: Timer?
        
        init(requestId: String, conversationID: String, startSeq: Int64, endSeq: Int64, retryCount: Int) {
            self.requestId = requestId
            self.conversationID = conversationID
            self.startSeq = startSeq
            self.endSeq = endSeq
            self.retryCount = retryCount
        }
        
        func cancelTimer() {
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
        
        deinit {
            cancelTimer()
        }
    }
    
    /// 保存正在进行的范围同步请求（key: requestId）
    private static var syncRangeContexts = [String: SyncRangeContext]()
    private static let rangeContextLock = NSLock()
    
    /// 保存待执行的重试任务（key: "conversationID_startSeq_endSeq"）
    private static var pendingRetryTasks = [String: DispatchWorkItem]()
    private static let retryTaskLock = NSLock()
    
    /// 同步指定 seq 范围的消息（用于补拉丢失的消息）
    /// - Parameters:
    ///   - conversationID: 会话 ID（必填）
    ///   - startSeq: 起始 seq（包含）
    ///   - endSeq: 结束 seq（包含）
    ///   - retryCount: 重试次数（内部使用）
    public func syncMessagesInRange(
        conversationID: String,
        startSeq: Int64,
        endSeq: Int64,
        retryCount: Int = 0
    ) {
        // 生成唯一请求ID
        let requestId = UUID().uuidString
        
        IMLogger.shared.info("""
            🔄 范围同步消息：
            - 请求ID: \(requestId)
            - 会话: \(conversationID)
            - seq 范围: [\(startSeq), \(endSeq)]
            - 预计数量: \(endSeq - startSeq + 1)
            - 重试次数: \(retryCount)
            """)
        
        // 检查连接状态
        guard isConnected?() == true else {
            IMLogger.shared.error("连接未建立，无法发送范围同步请求（等待连接恢复后重新触发）")
            return
        }
        
        // 保存上下文
        let context = SyncRangeContext(
            requestId: requestId,
            conversationID: conversationID,
            startSeq: startSeq,
            endSeq: endSeq,
            retryCount: retryCount
        )
        
        Self.rangeContextLock.lock()
        Self.syncRangeContexts[requestId] = context
        Self.rangeContextLock.unlock()
        
        // 创建范围同步请求
        var syncRangeReq = Im_Protocol_SyncRangeRequest()
        syncRangeReq.requestID = requestId
        syncRangeReq.conversationID = conversationID
        syncRangeReq.startSeq = startSeq
        syncRangeReq.endSeq = endSeq
        syncRangeReq.count = Int32(min(endSeq - startSeq + 1, 500))  // 限制单次拉取数量
        
        do {
            let requestData = try syncRangeReq.serializedData()
            
            guard let sendData = onSendData else {
                IMLogger.shared.error("onSendData callback not set")
                Self.rangeContextLock.lock()
                Self.syncRangeContexts.removeValue(forKey: requestId)
                Self.rangeContextLock.unlock()
                return
            }
            
            // 发送请求
            sendData(requestData, .syncRangeReq) { [weak self] result in
                switch result {
                case .success:
                    IMLogger.shared.debug("范围同步请求已发送 (requestId=\(requestId))")
                    
                    // 启动超时定时器（30秒）
                    let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                        self?.handleRangeSyncTimeout(requestId: requestId)
                    }
                    
                    Self.rangeContextLock.lock()
                    Self.syncRangeContexts[requestId]?.timeoutTimer = timer
                    Self.rangeContextLock.unlock()
                    
                case .failure(let error):
                    IMLogger.shared.error("发送范围同步请求失败: \(error)")
                    self?.handleRangeSyncFailure(requestId: requestId, error: error)
                }
            }
        } catch {
            IMLogger.shared.error("序列化范围同步请求失败: \(error)")
            Self.rangeContextLock.lock()
            Self.syncRangeContexts.removeValue(forKey: requestId)
            Self.rangeContextLock.unlock()
        }
    }
    
    /// 处理范围同步超时
    private func handleRangeSyncTimeout(requestId: String) {
        handleRangeSyncError(requestId: requestId, reason: "timeout")
    }
    
    /// 处理范围同步失败
    private func handleRangeSyncFailure(requestId: String, error: Error) {
        handleRangeSyncError(requestId: requestId, reason: "error: \(error)")
    }
    
    /// 处理范围同步错误（统一的错误处理逻辑）
    private func handleRangeSyncError(requestId: String, reason: String) {
        Self.rangeContextLock.lock()
        guard let context = Self.syncRangeContexts.removeValue(forKey: requestId) else {
            Self.rangeContextLock.unlock()
            return
        }
        context.cancelTimer()  // 取消定时器
        Self.rangeContextLock.unlock()
        
        IMLogger.shared.error("❌ Range sync failed (requestId=\(requestId)): \(reason)")
        
        // 重试
        if context.retryCount < maxRetryCount {
            let delay = Double(context.retryCount + 1) * 2.0
            IMLogger.shared.info("⏳ Retrying range sync in \(delay) seconds... (attempt \(context.retryCount + 1)/\(maxRetryCount))")
            
            // 生成重试任务的唯一 key
            let retryKey = "\(context.conversationID)_\(context.startSeq)_\(context.endSeq)"
            
            // ✅ 使用 DispatchWorkItem 创建可取消的重试任务
            let retryTask = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                // 从待执行任务中移除（执行时清理）
                Self.retryTaskLock.lock()
                Self.pendingRetryTasks.removeValue(forKey: retryKey)
                Self.retryTaskLock.unlock()
                
                // 检查连接状态
                guard self.isConnected?() == true else {
                    IMLogger.shared.debug("Range sync retry skipped: not connected")
                    return
                }
                
                self.syncMessagesInRange(
                    conversationID: context.conversationID,
                    startSeq: context.startSeq,
                    endSeq: context.endSeq,
                    retryCount: context.retryCount + 1
                )
            }
            
            // 保存到待执行任务字典（用于可能的取消）
            Self.retryTaskLock.lock()
            // 取消旧的重试任务（如果存在）
            Self.pendingRetryTasks[retryKey]?.cancel()
            Self.pendingRetryTasks[retryKey] = retryTask
            Self.retryTaskLock.unlock()
            
            // 延迟执行
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: retryTask)
        } else {
            IMLogger.shared.error("💔 Range sync failed after \(maxRetryCount) retries")
        }
    }
    
    /// 处理范围同步响应（由 IMClient 通过 messageRouter 调用）
    internal func handleSyncRangeResponse(_ response: Im_Protocol_SyncRangeResponse) {
        let requestId = response.requestID
        
        // 查找上下文
        Self.rangeContextLock.lock()
        guard let context = Self.syncRangeContexts.removeValue(forKey: requestId) else {
            Self.rangeContextLock.unlock()
            IMLogger.shared.warning("收到范围同步响应但找不到对应的上下文 (requestId=\(requestId))")
            return
        }
        context.cancelTimer()
        Self.rangeContextLock.unlock()
        
        // 检查错误码
        guard response.errorCode == .errSuccess else {
            IMLogger.shared.error("❌ 范围同步失败 (requestId=\(requestId)): 服务端返回错误 [\(response.errorCode)] \(response.errorMsg)")
            // 服务端返回的业务错误不需要重试，直接失败
            return
        }
        
        // 转换消息
        let messages = response.messages.compactMap { msgInfo -> IMMessage? in
            return convertProtoMessageToIMMessage(msgInfo)
        }
        
        // 保存到数据库
        if !messages.isEmpty {
            do {
                try database.saveMessages(messages)
                
                // 通知 messageManager
                messageManager.handleSyncedMessages(messages)
                
                IMLogger.shared.info("""
                    ✅ 范围同步成功：
                    - 请求ID: \(requestId)
                    - 会话: \(response.conversationID)
                    - 返回范围: [\(response.startSeq), \(response.endSeq)]
                    - 实际拉取: \(messages.count) 条
                    - 还有更多: \(response.hasMore_p)
                    """)
            } catch {
                IMLogger.shared.error("Failed to save range sync messages: \(error)")
            }
        }
        
        // 如果还有更多，继续拉取
        if response.hasMore_p {
            IMLogger.shared.debug("继续拉取下一批范围同步数据...")
            syncMessagesInRange(
                conversationID: context.conversationID,
                startSeq: response.endSeq + 1,
                endSeq: context.endSeq,
                retryCount: context.retryCount
            )
        }
    }
    
    // MARK: - 批量同步响应处理
    
    /// 处理批量同步响应（由 IMClient 的 messageRouter 调用）
    internal func handleBatchSyncResponse(_ response: Im_Protocol_BatchSyncResponse) {
        batchSyncContextLock.lock()
        guard let context = currentBatchSyncContext else {
            batchSyncContextLock.unlock()
            IMLogger.shared.warning("Received batch sync response but no pending request")
            return
        }
        // 取消超时定时器
        context.cancelTimer()
        currentBatchSyncContext = nil
        batchSyncContextLock.unlock()
        
        // 检查错误码
        guard response.errorCode == .errSuccess else {
            IMLogger.shared.error("Batch sync response error: \(response.errorMsg)")
            updateState(.failed(IMError.custom(response.errorMsg)))
            try? database.setSyncingState(userID: userID, isSyncing: false)
            return
        }
        
        // 处理每个会话的消息
        var totalMessageCount = 0
        var conversationsWithGaps = 0
        
        for convMessages in response.conversationMessages {
            // 转换消息
            let messages = convMessages.messages.compactMap { msgInfo -> IMMessage? in
                return convertProtoMessageToIMMessage(msgInfo)
            }
            
            // 1. 检测该会话中消息的 seq 丢失
            if !messages.isEmpty {
                let lossInfoList = messageManager.checkBatchMessageLoss(messages: messages)
                
                if !lossInfoList.isEmpty {
                    conversationsWithGaps += 1
                    IMLogger.shared.warning("""
                        ⚠️ 会话 \(convMessages.conversationID) 中检测到消息丢失：
                        \(lossInfoList.map { "gap=\($0.lossCount)" }.joined(separator: ", "))
                        """)
                    // 注：批量同步中检测到的 gap 通常是服务器侧问题，记录日志即可
                    // 不需要触发补拉，因为补拉也可能返回同样的结果
                }
            }
            
            // 2. 保存到数据库
            if !messages.isEmpty {
                do {
                    try database.saveMessages(messages)
                    
                    // 通知 messageManager
                    messageManager.handleSyncedMessages(messages)
                    
                    IMLogger.shared.debug("💾 Saved \(messages.count) messages for conversation \(convMessages.conversationID)")
                } catch {
                    IMLogger.shared.error("Failed to save messages for conversation \(convMessages.conversationID): \(error)")
                }
            }
            
            // 3. 更新本地同步状态
            if var syncConfig = database.getSyncConfig(userID: userID) {
                syncConfig.updateConversationMaxSeq(convMessages.conversationID, maxSeq: convMessages.maxSeq)
                try? database.saveSyncConfig(syncConfig)
            }
            
            totalMessageCount += messages.count
            
            // 4. 如果该会话还有更多消息
            if convMessages.hasMore_p {
                IMLogger.shared.debug("⚠️ Conversation \(convMessages.conversationID) has more messages (maxSeq=\(convMessages.maxSeq))")
                // TODO: 可以在这里触发单独的会话同步
            }
            
            // 5. 通知进度（每个会话处理完后）
            let progress = IMSyncProgress(
                currentCount: totalMessageCount,
                totalCount: Int64(response.totalMessageCount),
                currentBatch: 1  // 批量同步只有一个批次
            )
            
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(progress)
            }
        }
        
        let duration = Date().timeIntervalSince(context.startTime)
        let throughput = duration > 0 ? Double(totalMessageCount) / duration : 0
        
        IMLogger.shared.info("""
            ✅ Batch sync completed in \(String(format: "%.2f", duration))s
            - Conversations: \(response.conversationMessages.count)
            - Total messages: \(totalMessageCount)
            - Conversations with gaps: \(conversationsWithGaps)
            - Throughput: \(String(format: "%.0f", throughput)) msg/s
            - Server time: \(response.serverTime)
            """)
        
        updateState(.completed)
        
        // 清理同步状态
        try? database.setSyncingState(userID: userID, isSyncing: false)
    }
    
    // MARK: - 消息转换
    
    /// 将 Protobuf MessageInfo 转换为 IMMessage
    private func convertProtoMessageToIMMessage(_ protoMsg: Im_Protocol_MessageInfo) -> IMMessage? {
        let message = IMMessage()
        
        // 基础字段
        message.serverMsgID = protoMsg.serverMsgID
        message.clientMsgID = protoMsg.clientMsgID
        message.conversationID = protoMsg.conversationID
        message.senderID = protoMsg.senderID
        message.receiverID = protoMsg.receiverID
        message.groupID = protoMsg.groupID
        message.seq = protoMsg.seq
        message.sendTime = protoMsg.sendTime
        message.serverTime = protoMsg.serverTime
        message.createTime = protoMsg.createTime
        
        // 消息状态字段
        message.isRead = protoMsg.isRead
        message.isDeleted = protoMsg.isDeleted
        message.isRevoked = protoMsg.isRevoked
        message.revokedBy = protoMsg.revokedBy
        message.revokedTime = protoMsg.revokedTime
        
        // 已读相关字段
        message.readBy = protoMsg.readBy
        message.readTime = protoMsg.readTime
        
        // 扩展字段
        message.extra = protoMsg.extra
        message.attachedInfo = protoMsg.attachedInfo
        
        // 转换消息类型
        if let messageType = IMMessageType(rawValue: Int(protoMsg.messageType)) {
            message.messageType = messageType
        } else {
            // 未知消息类型，使用 .unknown
            IMLogger.shared.warning("Unknown message type: \(protoMsg.messageType), using .unknown")
            message.messageType = .unknown
        }
        
        // 转换消息状态
        if let status = IMMessageStatus(rawValue: Int(protoMsg.status)) {
            message.status = status
        } else {
            message.status = .sent  // 默认为已发送
        }
        
        // 转换消息内容（从 Data 到 String）
        if let contentStr = String(data: protoMsg.content, encoding: .utf8) {
            message.content = contentStr
        } else {
            message.content = ""
        }
        
        // 转换会话类型
        if let conversationType = IMConversationType(rawValue: Int(protoMsg.conversationType)) {
            message.conversationType = conversationType
        } else {
            // 如果没有指定或无效，根据 groupID 推断
            if !protoMsg.groupID.isEmpty {
                message.conversationType = .group
            } else {
                message.conversationType = .single
            }
        }
        
        // 推断消息方向（同步的消息需要判断是发送还是接收）
        if protoMsg.senderID == userID {
            message.direction = .send
        } else {
            message.direction = .receive
        }
        
        return message
    }
}



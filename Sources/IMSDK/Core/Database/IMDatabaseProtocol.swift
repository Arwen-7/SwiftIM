/// IMDatabaseProtocol - 数据库协议
///
/// 定义统一的数据库接口，使用 SQLite + WAL 实现

import Foundation

/// 数据库配置
public struct IMDatabaseConfig {
    /// 数据库文件名
    public var fileName: String
    /// 是否启用加密
    public var enableEncryption: Bool
    /// 加密密钥
    public var encryptionKey: Data?
    /// 是否启用 WAL 模式
    public var enableWAL: Bool
    
    public init(
        fileName: String = "imsdk.db",
        enableEncryption: Bool = false,
        encryptionKey: Data? = nil,
        enableWAL: Bool = false  // 默认不启用 WAL 模式
    ) {
        self.fileName = fileName
        self.enableEncryption = enableEncryption
        self.encryptionKey = encryptionKey
        self.enableWAL = enableWAL
    }
}

/// 数据库协议
/// 所有数据库实现都必须遵循此协议
public protocol IMDatabaseProtocol: AnyObject {
    
    // MARK: - 生命周期
    
    /// 关闭数据库
    func close()
    
    // MARK: - 消息操作
    
    /// 保存消息
    @discardableResult
    func saveMessage(_ message: IMMessage) throws -> IMMessageSaveResult
    
    /// 批量保存消息
    @discardableResult
    func saveMessages(_ messages: [IMMessage]) throws -> IMMessageBatchSaveStats
    
    /// 获取消息
    func getMessage(messageID: String) -> IMMessage?
    
    /// 获取消息
    func getMessage(clientMsgID: String) -> IMMessage?
    
    /// 获取会话消息列表
    func getMessages(conversationID: String, limit: Int) -> [IMMessage]
    
    /// 获取指定时间之前的消息
    func getMessagesBefore(conversationID: String, beforeTime: Int64, limit: Int) -> [IMMessage]
    
    /// 更新消息状态
    func updateMessageStatus(messageID: String, status: IMMessageStatus) throws
    
    /// 删除消息
    func deleteMessage(messageID: String) throws
    
    /// 标记消息为已读
    func markMessagesAsRead(messageIDs: [String]) throws
    
    /// 撤回消息
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - revokerID: 撤回者 ID
    ///   - revokeTime: 撤回时间
    func revokeMessage(messageID: String, revokerID: String, revokeTime: Int64) throws
    
    /// 更新消息已读状态（群聊）
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - readerID: 读取者 ID
    ///   - readTime: 读取时间
    func updateMessageReadStatus(messageID: String, readerID: String, readTime: Int64) throws
    
    /// 获取历史消息（分页）
    func getHistoryMessages(conversationID: String, startTime: Int64, count: Int) -> [IMMessage]
    
    /// 基于 seq 的历史消息查询
    func getHistoryMessagesBySeq(conversationID: String, startSeq: Int64, count: Int) -> [IMMessage]
    
    /// 搜索消息
    func searchMessages(keyword: String, conversationID: String?, limit: Int) -> [IMMessage]
    
    /// 获取消息数量
    func getHistoryMessageCount(conversationID: String) -> Int
    
    /// 获取最大 seq
    func getMaxSeq() -> Int64
    
    /// 获取指定会话的最新消息（用于消息丢失检测）
    func getLatestMessage(conversationID: String) throws -> IMMessage?
    
    // MARK: - 会话操作
    
    /// 保存会话
    func saveConversation(_ conversation: IMConversation) throws
    
    func saveConversations(_ conversations: [IMConversation]) throws -> Int
    
    /// 获取会话
    func getConversation(conversationID: String) -> IMConversation?
    
    /// 获取所有会话
    func getAllConversations(sortByTime: Bool) -> [IMConversation]
    
    /// 删除会话
    func deleteConversation(conversationID: String) throws
    
    /// 更新会话最后一条消息（OpenIM 方案）
    func updateConversationLastMessage(conversationID: String, message: IMMessage) throws
    
    /// 更新未读数
    func updateConversationUnreadCount(conversationID: String, unreadCount: Int) throws
    
    /// 清空未读数
    func clearUnreadCount(conversationID: String) throws
    
    /// 获取会话未读数
    func getUnreadCount(conversationID: String) -> Int
    
    /// 获取总未读数
    func getTotalUnreadCount() -> Int
    
    /// 设置置顶
    func setConversationPinned(conversationID: String, isPinned: Bool) throws
    
    /// 设置免打扰
    func setConversationMuted(conversationID: String, isMuted: Bool) throws
    
    /// 更新草稿
    func updateDraft(conversationID: String, draft: String) throws
    
    // MARK: - 用户操作
    
    /// 保存用户
    func saveUser(_ user: IMUser) throws
    
    /// 批量保存用户
    func saveUsers(_ users: [IMUser]) throws
    
    /// 获取用户
    func getUser(userID: String) -> IMUser?
    
    /// 批量获取用户
    func getUsers(userIDs: [String]) -> [IMUser]
    
    /// 搜索用户
    func searchUsers(keyword: String, limit: Int) -> [IMUser]
    
    /// 更新用户在线状态
    func updateUserOnlineStatus(userID: String, isOnline: Bool) throws
    
    // MARK: - 群组操作
    
    /// 保存群组
    func saveGroup(_ group: IMGroup) throws
    
    /// 获取群组
    func getGroup(groupID: String) -> IMGroup?
    
    /// 获取我的群组列表
    func getMyGroups(userID: String) -> [IMGroup]
    
    /// 删除群组
    func deleteGroup(groupID: String) throws
    
    /// 添加群成员
    func addGroupMember(groupID: String, userID: String, role: Int) throws
    
    /// 批量添加群成员
    func addGroupMembers(groupID: String, userIDs: [String]) throws
    
    /// 移除群成员
    func removeGroupMember(groupID: String, userID: String) throws
    
    /// 获取群成员列表
    func getGroupMembers(groupID: String) -> [IMUser]
    
    // MARK: - 好友操作
    
    /// 添加好友
    func addFriend(userID: String, friendID: String, remark: String?, source: String?) throws
    
    /// 获取好友列表
    func getFriends(userID: String) -> [IMUser]
    
    /// 获取好友备注
    func getFriendRemark(userID: String, friendID: String) -> String?
    
    /// 检查是否为好友
    func isFriend(userID: String, friendID: String) -> Bool
    
    /// 搜索好友
    func searchFriends(userID: String, keyword: String) -> [IMUser]
    
    /// 更新好友备注
    func updateFriendRemark(userID: String, friendID: String, remark: String) throws
    
    /// 删除好友
    func deleteFriend(userID: String, friendID: String) throws
    
    // MARK: - 同步配置操作
    
    /// 保存同步配置
    func saveSyncConfig(_ config: IMSyncConfig) throws
    
    /// 获取同步配置
    func getSyncConfig(userID: String) -> IMSyncConfig?
    
    /// 更新最后同步的 seq
    func updateLastSyncSeq(userID: String, seq: Int64) throws
    
    /// 设置同步状态
    func setSyncingState(userID: String, isSyncing: Bool) throws
    
    /// 重置同步配置
    func resetSyncConfig(userID: String) throws
    
    /// 获取最旧消息时间
    func getOldestMessageTime(conversationID: String) -> Int64
    
    /// 获取最新消息时间
    func getLatestMessageTime(conversationID: String) -> Int64
    
    /// 获取指定时间范围内的消息
    func getMessagesInTimeRange(conversationID: String, startTime: Int64, endTime: Int64) throws -> [IMMessage]
    
    /// 按发送者搜索消息
    func searchMessagesBySender(senderID: String, conversationID: String?, limit: Int) throws -> [IMMessage]
    
    /// 搜索消息数量
    func searchMessageCount(keyword: String, conversationID: String?, timeRange: (start: Int64, end: Int64)?) -> Int
}


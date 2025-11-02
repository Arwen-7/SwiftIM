/// IMModels - 核心数据模型
/// 定义 SDK 中使用的所有核心数据模型
/// 使用原生 Swift 类型，无需第三方依赖

import Foundation

// MARK: - 错误定义

/// IM 错误
public enum IMError: Error, LocalizedError {
    case notInitialized
    case notLoggedIn
    case notConnected
    case networkError(String)
    case databaseError(String)
    case invalidParameter(String)
    case invalidData
    case authenticationFailed(String)
    case kickedOut(String)
    case timeout
    case cancelled
    case sendFailed
    case permissionDenied
    case unknown(String)
    case custom(String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK not initialized"
        case .notLoggedIn:
            return "User not logged in"
        case .notConnected:
            return "Not connected to server"
        case .networkError(let message):
            return "Network error: \(message)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .invalidData:
            return "Invalid data"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .kickedOut(let message):
            return "Kicked out by server: \(message)"
        case .timeout:
            return "Request timeout"
        case .cancelled:
            return "Operation cancelled"
        case .sendFailed:
            return "Failed to send message"
        case .permissionDenied:
            return "Permission denied"
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - 连接状态

/// 连接状态
public enum IMConnectionState: Int {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case reconnecting = 3
}

// MARK: - 会话类型

/// 会话类型
public enum IMConversationType: Int, Codable {
    case single = 1      // 单聊
    case group = 2       // 群聊
    case chatRoom = 3    // 聊天室
    case system = 4      // 系统消息
}

// MARK: - 消息类型

/// 消息类型
public enum IMMessageType: Int, Codable {
    case text = 1          // 文本
    case image = 2         // 图片
    case audio = 3         // 语音
    case video = 4         // 视频
    case file = 5          // 文件
    case location = 6      // 位置
    case card = 7          // 名片
    case notification = 8  // 通知
    case custom = 100      // 自定义
}

// MARK: - 富媒体消息内容

/// 图片消息内容
public struct IMImageMessageContent: Codable {
    public var url: String = ""              // 原图 URL
    public var thumbnailUrl: String = ""     // 缩略图 URL
    public var width: Int = 0                // 图片宽度
    public var height: Int = 0               // 图片高度
    public var size: Int64 = 0               // 文件大小（字节）
    public var format: String = ""           // 图片格式（jpg, png, gif, etc）
    public var localPath: String = ""        // 本地路径
    public var thumbnailPath: String = ""    // 缩略图本地路径
    
    public init() {}
}

/// 语音消息内容
public struct IMAudioMessageContent: Codable {
    public var url: String = ""              // 语音 URL
    public var duration: Int = 0             // 时长（秒）
    public var size: Int64 = 0               // 文件大小（字节）
    public var format: String = ""           // 音频格式（aac, mp3, etc）
    public var localPath: String = ""        // 本地路径
    
    public init() {}
}

/// 视频消息内容
public struct IMVideoMessageContent: Codable {
    public var url: String = ""              // 视频 URL
    public var thumbnailUrl: String = ""     // 视频封面 URL
    public var snapshotUrl: String = ""      // 视频快照 URL（别名）
    public var duration: Int = 0             // 时长（秒）
    public var width: Int = 0                // 视频宽度
    public var height: Int = 0               // 视频高度
    public var size: Int64 = 0               // 文件大小（字节）
    public var format: String = ""           // 视频格式（mp4, mov, etc）
    public var localPath: String = ""        // 本地路径
    public var thumbnailPath: String = ""    // 封面本地路径
    public var snapshotPath: String = ""     // 快照本地路径（别名）
    
    public init() {}
}

/// 文件消息内容
public struct IMFileMessageContent: Codable {
    public var url: String = ""              // 文件 URL
    public var fileName: String = ""         // 文件名
    public var size: Int64 = 0               // 文件大小（字节）
    public var format: String = ""           // 文件扩展名
    public var localPath: String = ""        // 本地路径
    
    public init() {}
}

/// 位置消息内容
public struct IMLocationMessageContent: Codable {
    public var latitude: Double = 0.0        // 纬度
    public var longitude: Double = 0.0       // 经度
    public var address: String = ""          // 地址描述
    public var name: String = ""             // 位置名称
    
    public init() {}
}

/// 名片消息内容
public struct IMCardMessageContent: Codable {
    public var userID: String = ""           // 用户 ID
    public var nickname: String = ""         // 昵称
    public var avatar: String = ""           // 头像
    
    public init() {}
}

// MARK: - 文件传输

/// 文件类型
public enum IMFileType: String, Codable {
    case image      // 图片
    case audio      // 音频
    case video      // 视频
    case file       // 普通文件
    case document   // 文档
    case unknown    // 未知类型
}

/// 文件上传/下载任务状态
public enum IMFileTransferStatus: Int, Codable {
    case waiting      // 等待中
    case transferring // 传输中
    case paused       // 已暂停
    case completed    // 已完成
    case failed       // 失败
    case cancelled    // 已取消
}

/// 断点续传信息
public struct IMResumeData: Codable {
    public var taskID: String               // 任务 ID
    public var fileURL: String              // 文件 URL
    public var localPath: String            // 本地路径
    public var totalBytes: Int64            // 总字节数
    public var completedBytes: Int64        // 已完成字节数
    public var lastModified: Int64          // 最后修改时间
    public var eTag: String?                // ETag（用于验证）
    
    public init(
        taskID: String,
        fileURL: String,
        localPath: String,
        totalBytes: Int64,
        completedBytes: Int64,
        lastModified: Int64 = Int64(Date().timeIntervalSince1970),
        eTag: String? = nil
    ) {
        self.taskID = taskID
        self.fileURL = fileURL
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
        self.lastModified = lastModified
        self.eTag = eTag
    }
}

/// 文件传输进度
public struct IMFileTransferProgress {
    public var taskID: String               // 任务 ID
    public var totalBytes: Int64            // 总字节数
    public var completedBytes: Int64        // 已完成字节数
    public var progress: Double             // 进度（0.0 - 1.0）
    public var speed: Double                // 速度（字节/秒）
    public var status: IMFileTransferStatus // 状态
    public var startTime: Date              // 开始时间
    
    public init(
        taskID: String,
        totalBytes: Int64,
        completedBytes: Int64,
        status: IMFileTransferStatus = .waiting,
        speed: Double = 0.0,
        startTime: Date = Date()
    ) {
        self.taskID = taskID
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
        self.progress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0.0
        self.speed = speed
        self.status = status
        self.startTime = startTime
    }
}

/// 文件上传结果
public struct IMFileUploadResult {
    public var url: String                  // 文件 URL
    public var fileID: String               // 文件 ID
    public var size: Int64                  // 文件大小
    public var format: String               // 文件格式
    
    public init(url: String, fileID: String, size: Int64, format: String) {
        self.url = url
        self.fileID = fileID
        self.size = size
        self.format = format
    }
}

/// 文件下载结果
public struct IMFileDownloadResult {
    public var localPath: String            // 本地路径
    public var size: Int64                  // 文件大小
    
    public init(localPath: String, size: Int64) {
        self.localPath = localPath
        self.size = size
    }
}

/// 图片压缩配置
public struct IMImageCompressionConfig {
    public var maxWidth: CGFloat            // 最大宽度
    public var maxHeight: CGFloat           // 最大高度
    public var quality: CGFloat             // 压缩质量 (0.0-1.0)
    public var format: String               // 格式 (jpg, png)
    
    public static let `default` = IMImageCompressionConfig(
        maxWidth: 1920,
        maxHeight: 1920,
        quality: 0.8,
        format: "jpg"
    )
    
    public init(maxWidth: CGFloat, maxHeight: CGFloat, quality: CGFloat, format: String) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
        self.format = format
    }
}

/// 视频压缩配置
public struct IMVideoCompressionConfig {
    public var maxDuration: TimeInterval    // 最大时长（秒）
    public var maxSize: Int64               // 最大大小（字节）
    public var bitrate: Int                 // 比特率
    public var frameRate: Int               // 帧率
    
    public static let `default` = IMVideoCompressionConfig(
        maxDuration: 300,      // 5分钟
        maxSize: 100 * 1024 * 1024,  // 100MB
        bitrate: 2_000_000,    // 2Mbps
        frameRate: 30
    )
    
    public init(maxDuration: TimeInterval, maxSize: Int64, bitrate: Int, frameRate: Int) {
        self.maxDuration = maxDuration
        self.maxSize = maxSize
        self.bitrate = bitrate
        self.frameRate = frameRate
    }
}

// MARK: - 消息保存结果

/// 消息保存结果
public enum IMMessageSaveResult {
    case inserted   // 插入新消息
    case updated    // 更新已有消息
    case skipped    // 跳过（已存在且无需更新）
}

/// 批量保存统计信息
public struct IMMessageBatchSaveStats: CustomStringConvertible {
    public var insertedCount: Int = 0  // 插入数量
    public var updatedCount: Int = 0   // 更新数量
    public var skippedCount: Int = 0   // 跳过数量
    
    /// 总处理数量
    public var totalCount: Int {
        return insertedCount + updatedCount + skippedCount
    }
    
    /// 去重率（跳过的数量占总数的比例）
    public var deduplicationRate: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(skippedCount) / Double(totalCount)
    }
    
    public var description: String {
        return "BatchSaveStats(inserted: \(insertedCount), updated: \(updatedCount), skipped: \(skippedCount), total: \(totalCount), dedup: \(String(format: "%.1f%%", deduplicationRate * 100)))"
    }
}

// MARK: - 消息状态

/// 消息状态
public enum IMMessageStatus: Int, Codable {
    case sending = 0      // 发送中
    case sent = 1         // 已发送
    case delivered = 2    // 已送达
    case read = 3         // 已读
    case failed = 4       // 发送失败
}

// MARK: - 消息方向

/// 消息方向
public enum IMMessageDirection: Int, Codable {
    case send = 1         // 发送
    case receive = 2      // 接收
}

// MARK: - 用户

/// 用户信息
public class IMUser: Codable {
    public var userID: String = ""
    public var nickname: String = ""
    public var avatar: String = ""
    public var phone: String = ""
    public var email: String = ""
    public var gender: Int = 0  // 0: 未知, 1: 男, 2: 女
    public var birth: Int64 = 0
    public var signature: String = ""
    public var extra: String = ""
    public var createTime: Int64 = 0
    public var updateTime: Int64 = 0
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case userID, nickname, avatar, phone, email, gender, birth, signature, extra, createTime, updateTime
    }
    
    public init(userID: String) {
        self.userID = userID
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        gender = try container.decodeIfPresent(Int.self, forKey: .gender) ?? 0
        birth = try container.decodeIfPresent(Int64.self, forKey: .birth) ?? 0
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        createTime = try container.decodeIfPresent(Int64.self, forKey: .createTime) ?? 0
        updateTime = try container.decodeIfPresent(Int64.self, forKey: .updateTime) ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(phone, forKey: .phone)
        try container.encode(email, forKey: .email)
        try container.encode(gender, forKey: .gender)
        try container.encode(birth, forKey: .birth)
        try container.encode(signature, forKey: .signature)
        try container.encode(extra, forKey: .extra)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(updateTime, forKey: .updateTime)
    }
}

// MARK: - 消息

/// 消息
public class IMMessage: Codable {
    public var messageID: String = ""
    public var clientMsgID: String = ""
    public var conversationID: String = ""
    public var conversationType: IMConversationType = .single
    public var senderID: String = ""
    public var receiverID: String = ""
    public var groupID: String = ""
    public var messageType: IMMessageType = .text
    public var content: String = ""
    public var contentData: Data?
    public var extra: String = ""
    public var status: IMMessageStatus = .sending
    public var direction: IMMessageDirection = .send
    public var seq: Int64 = 0
    public var sendTime: Int64 = 0
    public var serverTime: Int64 = 0
    public var createTime: Int64 = 0  // 创建时间
    public var isRead: Bool = false
    public var readBy: [String] = []  // 已读者 ID 列表（群聊）
    public var readTime: Int64 = 0    // 读取时间（单聊）
    public var isDeleted: Bool = false
    public var isRevoked: Bool = false
    public var revokedBy: String = ""  // 撤回者 ID
    public var revokedTime: Int64 = 0  // 撤回时间
    public var attachedInfo: String = ""
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case messageID, clientMsgID, conversationID, conversationType, senderID, receiverID
        case groupID, messageType, content, extra, status, direction, seq
        case sendTime, serverTime, createTime, isRead, readBy, readTime, isDeleted, isRevoked, revokedBy, revokedTime, attachedInfo
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try container.decode(String.self, forKey: .messageID)
        clientMsgID = try container.decodeIfPresent(String.self, forKey: .clientMsgID) ?? ""
        conversationID = try container.decodeIfPresent(String.self, forKey: .conversationID) ?? ""
        conversationType = try container.decode(IMConversationType.self, forKey: .conversationType)
        senderID = try container.decode(String.self, forKey: .senderID)
        receiverID = try container.decodeIfPresent(String.self, forKey: .receiverID) ?? ""
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID) ?? ""
        messageType = try container.decode(IMMessageType.self, forKey: .messageType)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        status = try container.decode(IMMessageStatus.self, forKey: .status)
        direction = try container.decode(IMMessageDirection.self, forKey: .direction)
        seq = try container.decodeIfPresent(Int64.self, forKey: .seq) ?? 0
        sendTime = try container.decode(Int64.self, forKey: .sendTime)
        serverTime = try container.decodeIfPresent(Int64.self, forKey: .serverTime) ?? 0
        createTime = try container.decodeIfPresent(Int64.self, forKey: .createTime) ?? 0
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        readTime = try container.decodeIfPresent(Int64.self, forKey: .readTime) ?? 0
        readBy = try container.decodeIfPresent([String].self, forKey: .readBy) ?? []
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        isRevoked = try container.decodeIfPresent(Bool.self, forKey: .isRevoked) ?? false
        revokedBy = try container.decodeIfPresent(String.self, forKey: .revokedBy) ?? ""
        revokedTime = try container.decodeIfPresent(Int64.self, forKey: .revokedTime) ?? 0
        attachedInfo = try container.decodeIfPresent(String.self, forKey: .attachedInfo) ?? ""
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(clientMsgID, forKey: .clientMsgID)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(conversationType, forKey: .conversationType)
        try container.encode(senderID, forKey: .senderID)
        try container.encode(receiverID, forKey: .receiverID)
        try container.encode(groupID, forKey: .groupID)
        try container.encode(messageType, forKey: .messageType)
        try container.encode(content, forKey: .content)
        try container.encode(extra, forKey: .extra)
        try container.encode(status, forKey: .status)
        try container.encode(direction, forKey: .direction)
        try container.encode(seq, forKey: .seq)
        try container.encode(sendTime, forKey: .sendTime)
        try container.encode(serverTime, forKey: .serverTime)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(readBy, forKey: .readBy)
        try container.encode(readTime, forKey: .readTime)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(isRevoked, forKey: .isRevoked)
        try container.encode(revokedBy, forKey: .revokedBy)
        try container.encode(revokedTime, forKey: .revokedTime)
        try container.encode(attachedInfo, forKey: .attachedInfo)
    }
}

// MARK: - 会话

/// 会话
public class IMConversation: Codable {
    public var conversationID: String = ""
    public var conversationType: IMConversationType = .single
    public var userID: String = ""
    public var groupID: String = ""
    public var showName: String = ""
    public var faceURL: String = ""
    
    // 完整消息 JSON（OpenIM 方案）
    public var latestMsg: String = ""  // 存储完整消息的 JSON 字符串
    public var latestMsgSendTime: Int64 = 0  // 最后消息时间
    
    // 计算属性：按需反序列化为消息对象
    public var lastMessage: IMMessage? {
        get {
            guard !latestMsg.isEmpty else { return nil }
            guard let data = latestMsg.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(IMMessage.self, from: data)
        }
        set {
            if let msg = newValue,
               let data = try? JSONEncoder().encode(msg),
               let json = String(data: data, encoding: .utf8) {
                latestMsg = json
                latestMsgSendTime = msg.sendTime
            } else {
                latestMsg = ""
                latestMsgSendTime = 0
            }
        }
    }
    
    public var unreadCount: Int = 0
    public var lastReadTime: Int64 = 0  // 最后已读时间
    public var isPinned: Bool = false
    public var draftText: String = ""
    public var draftTime: Int64 = 0
    public var isMuted: Bool = false
    public var isPrivate: Bool = false
    public var extra: String = ""
    public var updateTime: Int64 = 0
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case conversationID, conversationType, userID, groupID, showName, faceURL
        case latestMsg, latestMsgSendTime
        case unreadCount, lastReadTime, isPinned, draftText, draftTime
        case isMuted, isPrivate, extra, updateTime
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        conversationType = try container.decode(IMConversationType.self, forKey: .conversationType)
        userID = try container.decodeIfPresent(String.self, forKey: .userID) ?? ""
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID) ?? ""
        showName = try container.decodeIfPresent(String.self, forKey: .showName) ?? ""
        faceURL = try container.decodeIfPresent(String.self, forKey: .faceURL) ?? ""
        latestMsg = try container.decodeIfPresent(String.self, forKey: .latestMsg) ?? ""
        latestMsgSendTime = try container.decodeIfPresent(Int64.self, forKey: .latestMsgSendTime) ?? 0
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        lastReadTime = try container.decodeIfPresent(Int64.self, forKey: .lastReadTime) ?? 0
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText) ?? ""
        draftTime = try container.decodeIfPresent(Int64.self, forKey: .draftTime) ?? 0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        updateTime = try container.decodeIfPresent(Int64.self, forKey: .updateTime) ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(conversationType, forKey: .conversationType)
        try container.encode(userID, forKey: .userID)
        try container.encode(groupID, forKey: .groupID)
        try container.encode(showName, forKey: .showName)
        try container.encode(faceURL, forKey: .faceURL)
        try container.encode(latestMsg, forKey: .latestMsg)
        try container.encode(latestMsgSendTime, forKey: .latestMsgSendTime)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encode(lastReadTime, forKey: .lastReadTime)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(draftText, forKey: .draftText)
        try container.encode(draftTime, forKey: .draftTime)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(extra, forKey: .extra)
        try container.encode(updateTime, forKey: .updateTime)
    }
}

// MARK: - 群组

/// 群组信息
public class IMGroup: Codable {
    public var groupID: String = ""
    public var groupName: String = ""
    public var faceURL: String = ""
    public var ownerUserID: String = ""
    public var memberCount: Int = 0
    public var introduction: String = ""
    public var notification: String = ""
    public var extra: String = ""
    public var createTime: Int64 = 0
    public var updateTime: Int64 = 0
    public var status: Int = 0  // 0: 正常, 1: 解散
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case groupID, groupName, faceURL, ownerUserID, memberCount
        case introduction, notification, extra, createTime, updateTime, status
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try container.decode(String.self, forKey: .groupID)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        faceURL = try container.decodeIfPresent(String.self, forKey: .faceURL) ?? ""
        ownerUserID = try container.decodeIfPresent(String.self, forKey: .ownerUserID) ?? ""
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        introduction = try container.decodeIfPresent(String.self, forKey: .introduction) ?? ""
        notification = try container.decodeIfPresent(String.self, forKey: .notification) ?? ""
        extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        createTime = try container.decodeIfPresent(Int64.self, forKey: .createTime) ?? 0
        updateTime = try container.decodeIfPresent(Int64.self, forKey: .updateTime) ?? 0
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupID, forKey: .groupID)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(faceURL, forKey: .faceURL)
        try container.encode(ownerUserID, forKey: .ownerUserID)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(introduction, forKey: .introduction)
        try container.encode(notification, forKey: .notification)
        try container.encode(extra, forKey: .extra)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(updateTime, forKey: .updateTime)
        try container.encode(status, forKey: .status)
    }
}

// MARK: - 好友

/// 好友信息
public class IMFriend: Codable {
    public var friendUserID: String = ""
    public var ownerUserID: String = ""
    public var remark: String = ""
    public var createTime: Int64 = 0
    public var addSource: Int = 0
    public var operatorUserID: String = ""
    public var extra: String = ""
    public var user: IMUser?
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case friendUserID, ownerUserID, remark, createTime
        case addSource, operatorUserID, extra, user
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendUserID = try container.decode(String.self, forKey: .friendUserID)
        ownerUserID = try container.decodeIfPresent(String.self, forKey: .ownerUserID) ?? ""
        remark = try container.decodeIfPresent(String.self, forKey: .remark) ?? ""
        createTime = try container.decodeIfPresent(Int64.self, forKey: .createTime) ?? 0
        addSource = try container.decodeIfPresent(Int.self, forKey: .addSource) ?? 0
        operatorUserID = try container.decodeIfPresent(String.self, forKey: .operatorUserID) ?? ""
        extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        user = try container.decodeIfPresent(IMUser.self, forKey: .user)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(friendUserID, forKey: .friendUserID)
        try container.encode(ownerUserID, forKey: .ownerUserID)
        try container.encode(remark, forKey: .remark)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(addSource, forKey: .addSource)
        try container.encode(operatorUserID, forKey: .operatorUserID)
        try container.encode(extra, forKey: .extra)
        try container.encodeIfPresent(user, forKey: .user)
    }
}

// MARK: - 同步配置

/// 同步配置
public class IMSyncConfig: Codable {
    public var userID: String = ""
    public var lastSyncSeq: Int64 = 0        // 最后同步的 seq
    public var lastSyncTime: Int64 = 0       // 最后同步时间
    public var isSyncing: Bool = false       // 是否正在同步
    public var version: Int = 0              // 版本号
    
    public init() {}
    
    public init(userID: String) {
        self.userID = userID
    }
}

/// 同步响应
public struct IMSyncResponse {
    public let messages: [IMMessage]    // 消息列表
    public let maxSeq: Int64            // 最大 seq
    public let hasMore: Bool            // 是否还有更多
    public let totalCount: Int64        // 总数量
    
    public init(messages: [IMMessage], maxSeq: Int64, hasMore: Bool, totalCount: Int64) {
        self.messages = messages
        self.maxSeq = maxSeq
        self.hasMore = hasMore
        self.totalCount = totalCount
    }
}

// MARK: - 同步进度

/// 同步进度
public struct IMSyncProgress {
    public let currentCount: Int       // 当前已同步数量
    public let totalCount: Int64       // 总数量
    public let progress: Double        // 进度 0.0-1.0
    public let currentBatch: Int       // 当前批次
    
    public init(currentCount: Int, totalCount: Int64, currentBatch: Int) {
        self.currentCount = currentCount
        self.totalCount = totalCount
        self.progress = totalCount > 0 ? Double(currentCount) / Double(totalCount) : 0.0
        self.currentBatch = currentBatch
    }
}

/// 同步状态
public enum IMSyncState {
    case idle           // 空闲
    case syncing        // 同步中
    case completed      // 已完成
    case failed(Error)  // 失败
}

// MARK: - 协议消息定义已迁移到 Protobuf
// 所有协议相关的消息定义（包括撤回、已读回执等）现在使用 Protobuf 生成
// 参见：IMProtocol.proto → IMProtocol.pb.swift

// MARK: - 消息已读回执通知（保留用于业务层）

/// 消息已读回执通知（业务层使用）
public struct IMReadReceiptNotification: Codable {
    public let conversationID: String      // 会话 ID
    public let conversationType: IMConversationType  // 会话类型
    public let messageIDs: [String]        // 消息 ID 列表
    public let readerID: String            // 读取者 ID
    public let readTime: Int64             // 读取时间
    
    public init(conversationID: String, conversationType: IMConversationType, messageIDs: [String], readerID: String, readTime: Int64) {
        self.conversationID = conversationID
        self.conversationType = conversationType
        self.messageIDs = messageIDs
        self.readerID = readerID
        self.readTime = readTime
    }
}


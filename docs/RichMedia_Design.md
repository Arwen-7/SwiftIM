# 富媒体消息 - 技术设计（MVP版本）

## 📋 概览

### 功能描述
实现富媒体消息支持，包括图片、语音、视频、文件消息的发送、接收和管理。

### 核心目标
1. **多种媒体类型**：支持图片、语音、视频、文件
2. **文件管理**：上传、下载、缓存管理
3. **进度跟踪**：实时上传下载进度回调
4. **缩略图支持**：图片自动生成缩略图
5. **本地缓存**：已下载文件本地缓存

---

## 🎯 技术方案

### 1. 数据模型

#### 1.1 消息内容模型

```swift
// 图片消息
public struct IMImageMessageContent: Codable {
    public var url: String              // 原图 URL
    public var thumbnailUrl: String     // 缩略图 URL
    public var width: Int               // 宽度
    public var height: Int              // 高度
    public var size: Int64              // 文件大小
    public var format: String           // 格式
    public var localPath: String        // 本地路径
    public var thumbnailPath: String    // 缩略图本地路径
}

// 语音消息
public struct IMAudioMessageContent: Codable {
    public var url: String              // 语音 URL
    public var duration: Int            // 时长（秒）
    public var size: Int64              // 文件大小
    public var format: String           // 格式
    public var localPath: String        // 本地路径
}

// 视频消息
public struct IMVideoMessageContent: Codable {
    public var url: String              // 视频 URL
    public var thumbnailUrl: String     // 封面 URL
    public var duration: Int            // 时长（秒）
    public var width: Int               // 宽度
    public var height: Int              // 高度
    public var size: Int64              // 文件大小
    public var format: String           // 格式
    public var localPath: String        // 本地路径
    public var thumbnailPath: String    // 封面本地路径
}

// 文件消息
public struct IMFileMessageContent: Codable {
    public var url: String              // 文件 URL
    public var fileName: String         // 文件名
    public var size: Int64              // 文件大小
    public var format: String           // 格式
    public var localPath: String        // 本地路径
}
```

#### 1.2 文件传输模型

```swift
// 传输状态
public enum IMFileTransferStatus {
    case waiting      // 等待中
    case transferring // 传输中
    case paused       // 已暂停
    case completed    // 已完成
    case failed       // 失败
    case cancelled    // 已取消
}

// 传输进度
public struct IMFileTransferProgress {
    public var taskID: String
    public var totalBytes: Int64
    public var completedBytes: Int64
    public var progress: Double         // 0.0 - 1.0
    public var speed: Double            // 字节/秒
    public var status: IMFileTransferStatus
}

// 上传结果
public struct IMFileUploadResult {
    public var url: String
    public var fileID: String
    public var size: Int64
    public var format: String
}

// 下载结果
public struct IMFileDownloadResult {
    public var localPath: String
    public var size: Int64
}
```

### 2. 文件管理器（IMFileManager）

#### 2.1 核心功能

```swift
public final class IMFileManager {
    public static let shared = IMFileManager()
    
    // 配置
    public var uploadBaseURL: String
    public var downloadBaseURL: String
    
    // 文件上传
    @discardableResult
    public func uploadFile(
        _ fileURL: URL,
        fileType: IMMessageType,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMFileUploadResult, Error>) -> Void
    ) -> String
    
    // 文件下载
    @discardableResult
    public func downloadFile(
        from url: String,
        fileType: IMMessageType,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMFileDownloadResult, Error>) -> Void
    ) -> String
    
    // 图片缩略图生成
    public func generateThumbnail(
        for imageURL: URL,
        maxSize: CGSize
    ) -> URL?
    
    // 缓存管理
    public func getCacheSize() -> Int64
    public func clearCache() throws
}
```

#### 2.2 目录结构

```
Documents/
└── IMFiles/
    ├── Images/       # 图片目录
    ├── Audio/        # 语音目录
    ├── Videos/       # 视频目录
    ├── Files/        # 文件目录
    └── Thumbnails/   # 缩略图目录
```

### 3. 消息发送集成

#### 3.1 IMMessageManager 扩展

```swift
extension IMMessageManager {
    // 发送图片消息
    public func sendImageMessage(
        imageURL: URL,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    )
    
    // 发送语音消息
    public func sendAudioMessage(
        audioURL: URL,
        duration: Int,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    )
    
    // 发送视频消息
    public func sendVideoMessage(
        videoURL: URL,
        duration: Int,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    )
    
    // 发送文件消息
    public func sendFileMessage(
        fileURL: URL,
        conversationID: String,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<IMMessage, Error>) -> Void
    )
    
    // 下载富媒体文件
    public func downloadMediaFile(
        from message: IMMessage,
        progressHandler: ((IMFileTransferProgress) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    )
}
```

#### 3.2 发送流程

```
发送图片消息：
  1. 创建消息对象（状态: sending）
  2. 保存到数据库
  3. 生成缩略图
  4. 上传原图（带进度回调）
  5. 上传缩略图
  6. 更新消息内容和状态（sent/failed）
  7. 通知监听器
```

---

## 📊 核心流程

### 1. 发送图片消息

```
┌─────────────┐
│ 选择图片     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 生成缩略图   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 创建消息     │  状态: sending
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 上传原图     │  进度回调
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 上传缩略图   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 更新消息     │  状态: sent, 内容: JSON
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 通知UI      │
└─────────────┘
```

### 2. 下载富媒体文件

```
┌─────────────┐
│ 收到消息     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 解析内容     │  JSON → Content
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 检查缓存     │
└──────┬──────┘
       │
   已缓存│     未缓存
       ▼       ▼
   ┌───────┐ ┌───────────┐
   │ 返回   │ │ 下载文件   │  进度回调
   └───────┘ └─────┬─────┘
                   │
                   ▼
             ┌───────────┐
             │ 保存到本地 │
             └─────┬─────┘
                   │
                   ▼
             ┌───────────┐
             │ 返回路径   │
             └───────────┘
```

---

## ⚡️ 性能优化

### 1. 缩略图优化

```swift
// 图片缩略图
- 最大尺寸：200x200
- 压缩质量：0.8
- 格式：JPEG
- 节省：约 80-90% 存储空间
```

### 2. 文件缓存

```
- 已下载文件本地缓存
- 避免重复下载
- 支持缓存清理
```

### 3. 并发控制

```
- 使用 URLSession
- 支持多任务并发
- 自动队列管理
```

---

## 🔒 安全性

### 1. 文件验证

```swift
- 文件大小限制
- 文件类型检查
- 恶意文件过滤
```

### 2. 网络安全

```
- HTTPS 传输
- Token 认证
- 防重放攻击
```

---

## 📈 监控指标

### 1. 上传成功率

```
正常范围：> 95%
异常情况：< 90%
```

### 2. 下载成功率

```
正常范围：> 98%
异常情况：< 95%
```

### 3. 缓存命中率

```
理想范围：60-80%
低命中率：< 50%
```

---

## 🎊 总结

### MVP 版本包含

1. ✅ 完整的数据模型
2. ✅ 文件上传/下载
3. ✅ 图片缩略图生成
4. ✅ 文件分类存储
5. ✅ 缓存管理
6. ✅ 进度回调

### 后续扩展

1. ⏳ 断点续传
2. ⏳ 文件压缩
3. ⏳ 视频封面生成
4. ⏳ CDN 加速
5. ⏳ 文件加密

---

**设计完成时间**：2025-10-24  
**实现版本**：MVP  
**优先级**：🔥 高


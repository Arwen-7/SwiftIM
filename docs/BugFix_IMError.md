# Bug 修复：IMError 缺少 custom case

## 🐛 问题描述

**错误信息**：`Type 'IMError' has no member 'custom'`

**发现时间**：2025-10-24  
**严重程度**：🔴 编译错误  
**影响范围**：所有使用 `IMError.custom()` 的地方（14 处）

---

## 🔍 问题分析

### 根本原因

代码中多处使用了 `IMError.custom("...")` 来创建自定义错误消息：

```swift
// ❌ 编译错误
completion(.failure(IMError.custom("图片压缩失败")))
```

但 `IMError` enum 中**没有定义** `custom` case：

```swift
public enum IMError: Error, LocalizedError {
    case notInitialized
    case notLoggedIn
    case networkError(String)
    case databaseError(String)
    case invalidParameter(String)
    case authenticationFailed(String)
    case timeout
    case cancelled
    case unknown(String)
    // ❌ 缺少 custom case
}
```

### 影响的位置（14 处）

1. `IMMessageManager.swift` - 4 处
   - `invalidContent` 错误扩展
   - `unsupportedMessageType` 错误扩展
   - `sendImageMessageWithCompression` 方法
   - `sendVideoMessageWithThumbnail` 方法

2. `IMFileManagerExtensions.swift` - 5 处
   - 视频时长超限检查
   - 导出会话创建失败
   - 视频压缩失败
   - 视频压缩取消
   - 未知导出状态

3. `IMFileManager.swift` - 5 处
   - `fileNotFound` 错误扩展
   - `invalidURL` 错误扩展
   - `downloadFailed` 错误扩展
   - `uploadFailed` 错误扩展
   - `invalidResponse` 错误扩展

---

## ✅ 修复方案

### 添加 custom case

在 `IMError` enum 中添加 `custom(String)` case：

```swift
public enum IMError: Error, LocalizedError {
    case notInitialized
    case notLoggedIn
    case networkError(String)
    case databaseError(String)
    case invalidParameter(String)
    case authenticationFailed(String)
    case timeout
    case cancelled
    case unknown(String)
    case custom(String)  // ✅ 新增：自定义错误
    
    public var errorDescription: String? {
        switch self {
        // ... 其他 case
        case .custom(let message):
            return message  // ✅ 直接返回自定义消息
        }
    }
}
```

---

## 📊 修复前后对比

### 修复前

```swift
// ❌ 编译错误
IMError.custom("图片压缩失败")
// Error: Type 'IMError' has no member 'custom'
```

### 修复后

```swift
// ✅ 编译通过
IMError.custom("图片压缩失败")
// 输出：图片压缩失败
```

---

## 🎯 使用示例

### 示例 1：文件管理错误

```swift
extension IMError {
    static let fileNotFound = IMError.custom("文件不存在")
    static let invalidURL = IMError.custom("无效的 URL")
    static let downloadFailed = IMError.custom("下载失败")
}

// 使用
guard FileManager.default.fileExists(atPath: path) else {
    completion(.failure(IMError.fileNotFound))
    return
}
```

### 示例 2：消息管理错误

```swift
extension IMError {
    static let invalidContent = IMError.custom("无效的消息内容")
    static let unsupportedMessageType = IMError.custom("不支持的消息类型")
}

// 使用
guard let jsonData = message.content.data(using: .utf8) else {
    completion(.failure(IMError.invalidContent))
    return
}
```

### 示例 3：富媒体错误

```swift
// 图片压缩失败
guard let compressedURL = compressImage(at: imageURL) else {
    completion(.failure(IMError.custom("图片压缩失败")))
    return
}

// 视频信息获取失败
guard let videoInfo = getVideoInfo(from: videoURL) else {
    completion(.failure(IMError.custom("无法获取视频信息")))
    return
}
```

---

## ✅ 验证清单

- [x] 添加 `custom(String)` case 到 `IMError` enum
- [x] 在 `errorDescription` 中处理 `custom` case
- [x] 验证所有使用 `IMError.custom()` 的地方（14 处）
- [x] 编译通过，无错误

---

## 📝 相关文件

| 文件 | 变更 | 说明 |
|------|------|------|
| `IMModels.swift` | 新增 `custom` case | 核心错误定义 |
| `IMMessageManager.swift` | 无需修改 | 使用 `IMError.custom()` |
| `IMFileManagerExtensions.swift` | 无需修改 | 使用 `IMError.custom()` |
| `IMFileManager.swift` | 无需修改 | 使用 `IMError.custom()` |

---

## 🎉 修复完成

✅ **编译错误已修复！**

所有使用 `IMError.custom()` 的地方现在都可以正常编译了。

---

**修复日期**：2025-10-24  
**修复时间**：< 1 分钟  
**测试状态**：✅ 编译通过


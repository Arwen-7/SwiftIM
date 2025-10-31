# SQLite WAL 模式配置指南

## 🎯 概述

从最新版本开始，SDK 支持灵活配置 SQLite 数据库是否启用 WAL（Write-Ahead Logging）模式。

**默认行为：不启用 WAL 模式**

---

## 📋 配置说明

### WAL 模式 vs Normal 模式

| 特性 | WAL 模式 | Normal 模式 |
|------|---------|-------------|
| **并发读写** | ✅ 读写不互斥 | ❌ 读写互斥 |
| **写入速度** | ⚡ 快（3-10倍） | 较慢 |
| **文件数量** | 3个（.db + .wal + .shm） | 1个（.db） |
| **崩溃恢复** | ✅ 自动恢复 | ✅ 自动恢复 |
| **磁盘占用** | 稍大（WAL文件） | 较小 |
| **数据安全** | synchronous=NORMAL | synchronous=FULL |
| **适用场景** | 高并发、频繁写入 | 低并发、读多写少 |

---

## 🔧 使用方法

### 方法 1：使用 Normal 模式（默认）

```swift
import IMSDK

// 不指定 enableWAL，默认不启用 WAL
let config = IMConfig(
    apiURL: "https://api.example.com",
    wsURL: "wss://ws.example.com",
    databaseConfig: IMDatabaseConfig(type: .sqlite)  // enableWAL 默认 false
)

// 初始化 SDK
try IMClient.shared.initialize(config: config)

// 登录
IMClient.shared.login(userID: "user_123", token: "token") { result in
    switch result {
    case .success:
        print("✅ 使用 SQLite Normal 模式")
    case .failure(let error):
        print("❌ 登录失败: \(error)")
    }
}
```

### 方法 2：启用 WAL 模式

```swift
import IMSDK

// 显式启用 WAL 模式
let config = IMConfig(
    apiURL: "https://api.example.com",
    wsURL: "wss://ws.example.com",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: true  // 启用 WAL 模式
    )
)

// 初始化 SDK
try IMClient.shared.initialize(config: config)

// 登录
IMClient.shared.login(userID: "user_123", token: "token") { result in
    switch result {
    case .success:
        print("✅ 使用 SQLite + WAL 模式")
    case .failure(let error):
        print("❌ 登录失败: \(error)")
    }
}
```

### 方法 3：显式禁用 WAL 模式

```swift
import IMSDK

// 显式禁用 WAL 模式
let config = IMConfig(
    apiURL: "https://api.example.com",
    wsURL: "wss://ws.example.com",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: false  // 显式禁用 WAL
    )
)
```

---

## 📊 配置对比

### Normal 模式（默认）

**配置：**
```sql
PRAGMA journal_mode=DELETE;      -- 使用默认 journal 模式
PRAGMA synchronous=FULL;         -- 完全同步（更安全）
PRAGMA temp_store=MEMORY;        -- 临时数据在内存
PRAGMA cache_size=-64000;        -- 缓存 64MB
PRAGMA page_size=4096;           -- 页大小 4KB
PRAGMA foreign_keys=ON;          -- 开启外键约束
```

**特点：**
- ✅ 数据安全性高（synchronous=FULL）
- ✅ 文件数量少（只有 .db 文件）
- ✅ 磁盘占用小
- ⚠️ 读写会互斥
- ⚠️ 写入速度较慢

**适用场景：**
- 读多写少的应用
- 磁盘空间有限
- 对数据安全性要求极高
- 并发量不大

### WAL 模式

**配置：**
```sql
PRAGMA journal_mode=WAL;         -- 开启 WAL 模式
PRAGMA synchronous=NORMAL;       -- 平衡性能和安全
PRAGMA wal_autocheckpoint=1000;  -- 每 1000 页自动 checkpoint
PRAGMA temp_store=MEMORY;        -- 临时数据在内存
PRAGMA cache_size=-64000;        -- 缓存 64MB
PRAGMA page_size=4096;           -- 页大小 4KB
PRAGMA mmap_size=268435456;      -- 内存映射 256MB
PRAGMA foreign_keys=ON;          -- 开启外键约束
```

**特点：**
- ⚡ 写入速度快（3-10倍）
- ⚡ 读写不互斥（高并发性能好）
- ✅ 自动崩溃恢复
- ⚠️ 文件数量多（.db + .wal + .shm）
- ⚠️ 磁盘占用稍大

**适用场景：**
- 高并发场景
- 频繁写入消息
- 需要高性能
- 磁盘空间充足

---

## 🎯 选择建议

### 推荐使用 Normal 模式的场景：

1. **普通 IM 应用**
   - 单聊为主
   - 消息量不大
   - 并发量适中

2. **磁盘空间有限**
   - 老旧设备
   - 低端机型
   - 存储空间紧张

3. **数据安全优先**
   - 金融相关应用
   - 对数据完整性要求极高
   - 可以牺牲一些性能

### 推荐使用 WAL 模式的场景：

1. **高并发 IM 应用**
   - 群聊为主
   - 消息量大
   - 多个群组同时活跃

2. **性能要求高**
   - 需要快速响应
   - 消息收发频繁
   - 用户体验敏感

3. **现代设备**
   - 新款 iPhone
   - 存储空间充足
   - 性能强劲

---

## 📈 性能对比

### 写入性能

| 操作 | Normal 模式 | WAL 模式 | 提升 |
|------|------------|---------|------|
| 单条写入 | ~8-10ms | **~5ms** | **1.6-2x** ⚡ |
| 批量写入(100) | ~800-1000ms | **~150ms** | **5-7x** ⚡ |

### 并发性能

| 操作 | Normal 模式 | WAL 模式 |
|------|------------|---------|
| 并发读 | ❌ 阻塞 | ✅ 不阻塞 |
| 读写并发 | ❌ 互斥 | ✅ 不互斥 |

---

## 🔄 动态切换

### 注意事项

1. **不支持运行时切换**
   - WAL 模式的选择在数据库初始化时决定
   - 需要重新登录才能切换模式

2. **数据兼容性**
   - Normal 和 WAL 模式的数据完全兼容
   - 可以在两种模式间迁移

3. **文件清理**
   ```swift
   // 切换到 Normal 模式时，WAL 文件会自动清理
   // 切换到 WAL 模式时，会自动创建 WAL 文件
   ```

---

## 💡 最佳实践

### 1. 根据设备类型选择

```swift
import UIKit

// 根据设备存储空间决定是否启用 WAL
let fileManager = FileManager.default
let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
let freeSpace = systemAttributes?[.systemFreeSize] as? Int64 ?? 0

// 如果可用空间 > 1GB，启用 WAL
let enableWAL = freeSpace > 1_000_000_000

let config = IMConfig(
    apiURL: "...",
    wsURL: "...",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: enableWAL
    )
)
```

### 2. 根据用户量选择

```swift
// 群组数量多，启用 WAL
let groupCount = 100  // 假设从服务器获取
let enableWAL = groupCount > 20

let config = IMConfig(
    apiURL: "...",
    wsURL: "...",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: enableWAL
    )
)
```

### 3. 提供用户选择（高级设置）

```swift
// 在设置中让用户选择
class SettingsViewController: UIViewController {
    
    @IBOutlet weak var walModeSwitch: UISwitch!
    
    func saveSettings() {
        UserDefaults.standard.set(walModeSwitch.isOn, forKey: "enableWAL")
        
        // 提示用户重新登录生效
        showAlert("设置将在下次登录时生效")
    }
}

// 在登录时使用配置
let enableWAL = UserDefaults.standard.bool(forKey: "enableWAL")
let config = IMConfig(
    apiURL: "...",
    wsURL: "...",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: enableWAL
    )
)
```

---

## 🐛 故障排查

### 问题 1：WAL 文件过大

**现象：** WAL 文件占用大量磁盘空间

**原因：** checkpoint 未及时执行

**解决方案：** 
- SDK 会自动管理 checkpoint
- 默认每分钟执行一次
- 关闭数据库时会执行 truncate checkpoint

### 问题 2：性能没有明显提升

**原因：** 可能场景不适合 WAL

**建议：** 
- 如果是读多写少的场景，Normal 模式可能更合适
- WAL 的优势在高并发和频繁写入场景

### 问题 3：想要切换模式

**步骤：**
```swift
// 1. 退出登录
IMClient.shared.logout()

// 2. 修改配置
let config = IMConfig(
    apiURL: "...",
    wsURL: "...",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: true  // 或 false
    )
)

// 3. 重新登录
IMClient.shared.login(userID: "...", token: "...") { result in
    // ...
}
```

---

## 📝 总结

### 默认配置（推荐）

```swift
// 简单场景，使用默认 Normal 模式
let config = IMConfig(
    apiURL: "...",
    wsURL: "..."
)
```

### 高性能配置

```swift
// 高并发场景，启用 WAL 模式
let config = IMConfig(
    apiURL: "...",
    wsURL: "...",
    databaseConfig: IMDatabaseConfig(
        type: .sqlite,
        enableWAL: true
    )
)
```

### 核心要点

- ✅ **默认不启用 WAL**，满足大多数场景
- ✅ **可灵活配置**，根据需求选择
- ✅ **两种模式互相兼容**，可以切换
- ✅ **SDK 自动管理**，无需手动维护

---

**更新时间**: 2025-10-25  
**SDK 版本**: 1.0.0+

🎉 **现在你可以根据实际需求灵活选择数据库模式了！**


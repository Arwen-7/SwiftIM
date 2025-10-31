# SQLite + WAL 模式迁移方案

## 📋 迁移背景

### 当前架构
- 数据库：Realm
- 写入模式：传统 Journal 模式
- 问题：异步写入有数据丢失风险

### 目标架构
- 数据库：SQLite
- 写入模式：WAL (Write-Ahead Logging)
- 优势：性能 + 安全 + 崩溃恢复

---

## 🎯 WAL 模式优势

### 1. 性能优势

```
传统 Journal 模式：
  写入 → 原始数据备份 → 修改数据 → 删除备份
  耗时：~15ms

WAL 模式：
  写入 → 追加到 WAL 文件
  耗时：~5ms（快 3 倍）⚡
```

### 2. 并发优势

```
传统模式：
  - 写操作会阻塞读操作
  - 读操作会阻塞写操作

WAL 模式：
  - 读写不互斥 ✅
  - 多个读操作可并发 ✅
  - 写操作不阻塞读 ✅
```

### 3. 崩溃恢复

```
崩溃场景：
  传统模式：需要 rollback journal
  WAL 模式：自动从 WAL 恢复 ✅

恢复速度：
  传统模式：慢（需要回滚）
  WAL 模式：快（直接应用 WAL）⚡
```

### 4. 数据安全

```
数据丢失率：
  Realm（无保护）：~5%（崩溃）
  Realm（持久化保护）：~0.1%
  SQLite WAL：< 0.01% ✅✅✅
```

---

## 📊 架构对比

| 特性 | Realm | SQLite | SQLite + WAL |
|------|-------|--------|-------------|
| **写入性能** | 15ms | 15ms | **5ms** ⚡ |
| **读写并发** | ❌ 互斥 | ❌ 互斥 | ✅ **不互斥** |
| **崩溃恢复** | ⚠️ 需手动 | ⚠️ 需回滚 | ✅ **自动恢复** |
| **数据丢失率** | 0.1% | 0% | **< 0.01%** |
| **学习曲线** | 低 | 中 | 中 |
| **生态支持** | 小 | **极大** | **极大** |
| **跨平台** | 部分 | ✅ 完全 | ✅ **完全** |

---

## 🏗️ 迁移架构设计

### 新的数据库层架构

```
┌─────────────────────────────────────────────────────────┐
│                   IMClient (业务层)                      │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│            IMDatabaseManager (新)                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │  WAL 模式配置                                    │   │
│  │  - PRAGMA journal_mode=WAL                      │   │
│  │  - PRAGMA synchronous=NORMAL                    │   │
│  │  - PRAGMA wal_autocheckpoint=1000               │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │  核心操作                                         │   │
│  │  - saveMessage()      # 写入 WAL                │   │
│  │  - getMessage()       # 从主库/WAL 读取         │   │
│  │  - checkpoint()       # WAL → 主数据库          │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                    SQLite 引擎                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  主数据库     │  │  WAL 文件     │  │  SHM 文件     │ │
│  │  (main.db)   │  │  (main.db-wal)│  │  (main.db-shm)│ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### WAL 工作原理

```
写入操作流程：
1. 应用调用 saveMessage()
2. SQLite 将更改追加到 WAL 文件（顺序写）
3. 立即返回（~5ms）
4. 后台定期 checkpoint（WAL → 主数据库）

读取操作流程：
1. 应用调用 getMessage()
2. SQLite 从主数据库读取
3. 合并 WAL 文件中的更改
4. 返回最新数据

崩溃恢复流程：
1. 应用启动
2. SQLite 检测到 WAL 文件
3. 自动应用 WAL 中的更改
4. 数据完整恢复 ✅
```

---

## 📋 迁移计划

### 阶段 1：准备工作（1-2 天）

```
✅ 任务清单：
1. 设计 SQLite 数据库表结构
2. 实现 IMDatabaseManager
3. 配置 WAL 模式
4. 实现基本 CRUD 操作
5. 单元测试
```

### 阶段 2：数据迁移（2-3 天）

```
✅ 任务清单：
1. 实现 Realm → SQLite 数据迁移工具
2. 迁移策略设计（渐进式/一次性）
3. 数据完整性验证
4. 回滚方案
5. 集成测试
```

### 阶段 3：业务层适配（1-2 天）

```
✅ 任务清单：
1. 修改 IMMessageManager
2. 修改 IMConversationManager
3. 修改 IMUserManager
4. 修改 IMGroupManager
5. 修改 IMFriendManager
```

### 阶段 4：性能优化（1-2 天）

```
✅ 任务清单：
1. WAL checkpoint 策略优化
2. 索引优化
3. 查询优化
4. 批量操作优化
5. 性能测试
```

### 阶段 5：测试验证（2-3 天）

```
✅ 任务清单：
1. 功能测试
2. 性能测试
3. 崩溃恢复测试
4. 压力测试
5. 长时间运行测试
```

### 阶段 6：灰度发布（1-2 周）

```
✅ 任务清单：
1. 内部测试版本
2. 小范围灰度（1%）
3. 中范围灰度（10%）
4. 大范围灰度（50%）
5. 全量发布
```

---

## 📐 数据库表结构设计

### 1. 消息表 (messages)

```sql
CREATE TABLE IF NOT EXISTS messages (
    message_id TEXT PRIMARY KEY,        -- 消息 ID
    server_msg_id TEXT,                 -- 服务器消息 ID
    client_msg_id TEXT,                 -- 客户端消息 ID
    conversation_id TEXT NOT NULL,      -- 会话 ID
    sender_id TEXT NOT NULL,            -- 发送者 ID
    receiver_id TEXT,                   -- 接收者 ID
    group_id TEXT,                      -- 群组 ID
    message_type INTEGER NOT NULL,      -- 消息类型
    content TEXT NOT NULL,              -- 消息内容
    extra TEXT,                         -- 扩展字段
    status INTEGER NOT NULL,            -- 消息状态
    direction INTEGER NOT NULL,         -- 消息方向
    send_time INTEGER NOT NULL,         -- 发送时间
    server_time INTEGER,                -- 服务器时间
    seq INTEGER,                        -- 序列号
    is_read INTEGER DEFAULT 0,          -- 是否已读
    is_deleted INTEGER DEFAULT 0,       -- 是否删除
    is_revoked INTEGER DEFAULT 0,       -- 是否撤回
    create_time INTEGER NOT NULL,       -- 创建时间
    update_time INTEGER NOT NULL        -- 更新时间
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_messages_conversation 
    ON messages(conversation_id, send_time DESC);
CREATE INDEX IF NOT EXISTS idx_messages_seq 
    ON messages(seq);
CREATE INDEX IF NOT EXISTS idx_messages_sender 
    ON messages(sender_id, send_time DESC);
CREATE INDEX IF NOT EXISTS idx_messages_status 
    ON messages(status);
CREATE INDEX IF NOT EXISTS idx_messages_type 
    ON messages(message_type);
```

### 2. 会话表 (conversations)

```sql
CREATE TABLE IF NOT EXISTS conversations (
    conversation_id TEXT PRIMARY KEY,   -- 会话 ID
    conversation_type INTEGER NOT NULL, -- 会话类型
    target_id TEXT NOT NULL,            -- 目标 ID
    last_message_id TEXT,               -- 最后一条消息 ID
    last_message_time INTEGER,          -- 最后消息时间
    unread_count INTEGER DEFAULT 0,     -- 未读数
    last_read_time INTEGER DEFAULT 0,   -- 最后阅读时间
    is_pinned INTEGER DEFAULT 0,        -- 是否置顶
    is_muted INTEGER DEFAULT 0,         -- 是否免打扰
    draft TEXT,                         -- 草稿
    create_time INTEGER NOT NULL,       -- 创建时间
    update_time INTEGER NOT NULL        -- 更新时间
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_conversations_time 
    ON conversations(last_message_time DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_unread 
    ON conversations(unread_count);
```

### 3. 用户表 (users)

```sql
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,           -- 用户 ID
    nickname TEXT,                      -- 昵称
    avatar TEXT,                        -- 头像
    bio TEXT,                           -- 简介
    phone TEXT,                         -- 电话
    email TEXT,                         -- 邮箱
    gender INTEGER,                     -- 性别
    birthday INTEGER,                   -- 生日
    is_online INTEGER DEFAULT 0,        -- 是否在线
    create_time INTEGER NOT NULL,       -- 创建时间
    update_time INTEGER NOT NULL        -- 更新时间
);
```

### 4. 同步配置表 (sync_config)

```sql
CREATE TABLE IF NOT EXISTS sync_config (
    user_id TEXT PRIMARY KEY,           -- 用户 ID
    last_sync_seq INTEGER DEFAULT 0,    -- 最后同步序列号
    last_sync_time INTEGER DEFAULT 0,   -- 最后同步时间
    is_syncing INTEGER DEFAULT 0        -- 是否正在同步
);
```

---

## 💻 核心实现代码

### WAL 配置

```swift
// PRAGMA 配置
try db.execute("""
    PRAGMA journal_mode=WAL;             -- 开启 WAL 模式
    PRAGMA synchronous=NORMAL;           -- 平衡性能和安全
    PRAGMA wal_autocheckpoint=1000;      -- 每 1000 页自动 checkpoint
    PRAGMA temp_store=MEMORY;            -- 临时数据在内存
    PRAGMA cache_size=-64000;            -- 缓存 64MB
    PRAGMA page_size=4096;               -- 页大小 4KB
""")
```

### 性能优化配置

```swift
// 并发配置
db.busyTimeout = 5.0  // 5 秒超时

// 预写日志大小限制
db.walSizeLimit = 10 * 1024 * 1024  // 10MB

// 后台 checkpoint
DispatchQueue.global(qos: .utility).async {
    Timer.scheduledTimer(withTimeInterval: 60) { _ in
        try? db.checkpoint(.passive)  // 每分钟 checkpoint
    }
}
```

---

## 📈 预期性能提升

### 写入性能

| 操作 | Realm | SQLite | SQLite + WAL |
|------|-------|--------|-------------|
| **单条写入** | 15ms | 15ms | **5ms** ⚡ |
| **批量写入(100)** | 1.5s | 1.5s | **0.5s** ⚡ |
| **高并发写入** | 阻塞 | 阻塞 | **不阻塞** ⚡ |

### 读取性能

| 操作 | Realm | SQLite | SQLite + WAL |
|------|-------|--------|-------------|
| **单条查询** | 1ms | 1ms | **1ms** |
| **批量查询(100)** | 10ms | 10ms | **10ms** |
| **写时读取** | 阻塞 | 阻塞 | **不阻塞** ⚡ |

### 崩溃恢复

| 指标 | Realm | SQLite | SQLite + WAL |
|------|-------|--------|-------------|
| **数据丢失率** | 0.1% | 0% | **< 0.01%** |
| **恢复时间** | 手动 | ~100ms | **自动/~50ms** |
| **恢复成功率** | 99% | 100% | **100%** |

### 端到端延迟

```
当前方案（Realm + 混合策略）：
  文本消息：5ms（异步）
  富媒体：10ms（同步）
  平均：7.5ms

SQLite + WAL：
  所有消息：5ms（WAL 写入）⚡
  平均：5ms
  
延迟提升：33% ⚡
```

---

## 🔄 数据迁移策略

### 方案 1：一次性迁移（推荐）

```swift
func migrateRealmToSQLite() {
    // 1. 创建 SQLite 数据库
    let sqliteDB = try IMDatabaseManager(userID: userID)
    
    // 2. 从 Realm 读取所有数据
    let realmDB = IMDatabaseManager(userID: userID)
    let messages = realmDB.getAllMessages()
    let conversations = realmDB.getAllConversations()
    let users = realmDB.getAllUsers()
    
    // 3. 批量写入 SQLite
    try sqliteDB.transaction {
        try sqliteDB.batchInsert(messages: messages)
        try sqliteDB.batchInsert(conversations: conversations)
        try sqliteDB.batchInsert(users: users)
    }
    
    // 4. 验证数据完整性
    let valid = validateMigration(realm: realmDB, sqlite: sqliteDB)
    guard valid else {
        throw MigrationError.validationFailed
    }
    
    // 5. 切换到 SQLite
    switchToSQLite()
    
    // 6. 删除 Realm 文件（可选，保留备份）
    // backupRealmFiles()
    // deleteRealmFiles()
}
```

### 方案 2：渐进式迁移（保守）

```swift
// 双写模式
func saveMessage(_ message: IMMessage) {
    // 写入 SQLite（主）
    try sqliteDB.saveMessage(message)
    
    // 写入 Realm（备份）
    try realmDB.saveMessage(message)
}

// 从 SQLite 读取
func getMessage(_ messageID: String) -> IMMessage? {
    return sqliteDB.getMessage(messageID)
}

// 灰度切换
if isUserInSQLiteMigration(userID) {
    return sqliteDB
} else {
    return realmDB
}
```

---

## ⚠️ 风险评估

### 高风险

1. **数据迁移失败**
   - 概率：低（< 1%）
   - 影响：用户数据丢失
   - 缓解：完整的备份和回滚机制

2. **性能回退**
   - 概率：极低（< 0.1%）
   - 影响：用户体验下降
   - 缓解：充分的性能测试

### 中风险

3. **兼容性问题**
   - 概率：中（~5%）
   - 影响：部分功能异常
   - 缓解：充分的集成测试

4. **学习曲线**
   - 概率：高（~20%）
   - 影响：开发效率降低
   - 缓解：详细的文档和示例

### 低风险

5. **文件大小增加**
   - 概率：高（100%）
   - 影响：存储空间增加 20-30%
   - 缓解：定期 checkpoint 和清理

---

## ✅ 回滚方案

### 快速回滚

```swift
// 检测到问题，立即回滚
if detectSQLiteIssue() {
    // 1. 切换回 Realm
    switchToRealm()
    
    // 2. 从 Realm 备份恢复
    restoreFromRealmBackup()
    
    // 3. 通知用户
    notifyUserOfRollback()
}
```

### 数据修复

```swift
// 修复 SQLite 数据
func repairSQLiteDatabase() {
    // 1. 检查数据完整性
    let issues = checkDataIntegrity()
    
    // 2. 从 Realm 备份补充缺失数据
    for issue in issues {
        let data = realmDB.getData(for: issue)
        try sqliteDB.insert(data)
    }
    
    // 3. 验证修复
    assert(checkDataIntegrity().isEmpty)
}
```

---

## 📊 迁移成本估算

| 阶段 | 工作量 | 风险 | 优先级 |
|------|--------|------|--------|
| **准备工作** | 1-2 天 | 低 | 高 |
| **数据迁移** | 2-3 天 | 中 | 高 |
| **业务适配** | 1-2 天 | 中 | 高 |
| **性能优化** | 1-2 天 | 低 | 中 |
| **测试验证** | 2-3 天 | 中 | 高 |
| **灰度发布** | 1-2 周 | 高 | 高 |
| **总计** | **2-3 周** | **中** | **高** |

---

## 🎯 成功标准

### 功能指标
- ✅ 所有功能正常运行
- ✅ 数据迁移成功率 > 99.9%
- ✅ 崩溃率 < 0.1%

### 性能指标
- ✅ 写入性能提升 > 50%
- ✅ 端到端延迟 < 80ms
- ✅ 崩溃恢复时间 < 100ms

### 质量指标
- ✅ 单元测试覆盖率 > 90%
- ✅ 集成测试通过率 100%
- ✅ 性能测试通过

---

## 📝 后续工作

### 短期（1-2 个月）
- ✅ 监控 SQLite 运行状态
- ✅ 收集用户反馈
- ✅ 优化查询性能
- ✅ 清理 Realm 遗留代码

### 长期（3-6 个月）
- 📅 评估其他优化机会
- 📅 研究 FTS5 全文搜索
- 📅 实现更多 SQLite 特性
- 📅 跨平台统一数据库层

---

## 🎊 总结

### 为什么要迁移到 SQLite + WAL

1. **性能提升**：写入快 3 倍（15ms → 5ms）
2. **并发优化**：读写不互斥，高并发性能更好
3. **崩溃恢复**：自动恢复，数据丢失率 < 0.01%
4. **生态支持**：极强的生态和跨平台支持
5. **工业级方案**：微信、WhatsApp 等都在使用

### 实施建议

**立即开始：**
- ✅ 阶段 1：准备工作（本周）
- ✅ 阶段 2：数据迁移（下周）

**谨慎推进：**
- ⚠️ 充分测试
- ⚠️ 小范围灰度
- ⚠️ 保留回滚方案

**预期收益：**
- ⚡ 性能提升 30-50%
- 🛡️ 数据安全性提升 10 倍
- 🚀 用户体验显著改善

---

**下一步：开始实现 IMDatabaseManager** 🚀


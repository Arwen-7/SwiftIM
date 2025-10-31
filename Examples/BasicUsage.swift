/// BasicUsage - IMSDK 基础使用示例
/// 展示如何使用 IM SDK 的基本功能

import Foundation
import IMSDK

/// 示例类
class IMSDKBasicUsageExample {
    
    // MARK: - 1. 初始化和登录
    
    func setupSDK() {
        // 配置 SDK
        let config = IMConfig(
            apiURL: "https://your-api-server.com",
            wsURL: "wss://your-websocket-server.com"
        )
        
        // 初始化
        do {
            try IMClient.shared.initialize(config: config)
            print("✅ SDK 初始化成功")
        } catch {
            print("❌ SDK 初始化失败: \(error)")
        }
    }
    
    func login() {
        // 登录
        IMClient.shared.login(
            userID: "user123",
            token: "your-auth-token"
        ) { result in
            switch result {
            case .success(let user):
                print("✅ 登录成功")
                print("用户昵称: \(user.nickname)")
                print("用户头像: \(user.avatar)")
                
            case .failure(let error):
                print("❌ 登录失败: \(error)")
            }
        }
    }
    
    func logout() {
        IMClient.shared.logout { result in
            switch result {
            case .success:
                print("✅ 登出成功")
            case .failure(let error):
                print("❌ 登出失败: \(error)")
            }
        }
    }
    
    // MARK: - 2. 发送消息
    
    func sendTextMessage() {
        let messageManager = IMClient.shared.messageManager!
        
        // 创建文本消息
        let message = messageManager.createTextMessage(
            content: "你好，世界！",
            to: "receiver_user_id",
            conversationType: .single
        )
        
        // 发送消息
        messageManager.sendMessage(message) { result in
            switch result {
            case .success(let sentMessage):
                print("✅ 消息发送成功")
                print("消息 ID: \(sentMessage.messageID)")
                
            case .failure(let error):
                print("❌ 消息发送失败: \(error)")
            }
        }
    }
    
    func sendImageMessage() {
        let messageManager = IMClient.shared.messageManager!
        
        // 1. 先上传图片到服务器
        // let imageURL = uploadImage(imageData)
        
        // 2. 创建图片消息
        let message = messageManager.createImageMessage(
            imageURL: "https://example.com/image.jpg",
            to: "receiver_user_id",
            conversationType: .single
        )
        
        // 3. 发送消息
        messageManager.sendMessage(message) { result in
            switch result {
            case .success:
                print("✅ 图片消息发送成功")
            case .failure(let error):
                print("❌ 图片消息发送失败: \(error)")
            }
        }
    }
    
    // MARK: - 3. 接收消息
    
    func setupMessageListener() {
        // 添加消息监听器
        IMClient.shared.addMessageListener(self)
    }
    
    // MARK: - 4. 会话管理
    
    func getConversationList() {
        let conversationManager = IMClient.shared.conversationManager!
        
        // 获取所有会话
        let conversations = conversationManager.getAllConversations()
        
        print("会话数量: \(conversations.count)")
        
        for conversation in conversations {
            print("会话 ID: \(conversation.conversationID)")
            print("显示名称: \(conversation.showName)")
            print("未读数: \(conversation.unreadCount)")
            print("最后消息: \(conversation.lastMessage?.content ?? "")")
            print("---")
        }
    }
    
    func clearUnreadCount(conversationID: String) {
        let conversationManager = IMClient.shared.conversationManager!
        
        conversationManager.clearUnreadCount(conversationID: conversationID) { result in
            switch result {
            case .success:
                print("✅ 清除未读数成功")
            case .failure(let error):
                print("❌ 清除未读数失败: \(error)")
            }
        }
    }
    
    func getTotalUnreadCount() {
        let conversationManager = IMClient.shared.conversationManager!
        let totalUnreadCount = conversationManager.getTotalUnreadCount()
        print("总未读数: \(totalUnreadCount)")
    }
    
    // MARK: - 5. 用户信息
    
    func getUserInfo(userID: String) {
        let userManager = IMClient.shared.userManager!
        
        userManager.getUserInfo(userID: userID) { result in
            switch result {
            case .success(let user):
                print("✅ 获取用户信息成功")
                print("昵称: \(user.nickname)")
                print("头像: \(user.avatar)")
                print("签名: \(user.signature)")
                
            case .failure(let error):
                print("❌ 获取用户信息失败: \(error)")
            }
        }
    }
    
    func updateUserInfo() {
        let userManager = IMClient.shared.userManager!
        
        guard let currentUser = userManager.getCurrentUser() else {
            print("❌ 未登录")
            return
        }
        
        // 修改用户信息
        currentUser.nickname = "新昵称"
        currentUser.signature = "这是我的个性签名"
        
        userManager.updateUserInfo(currentUser) { result in
            switch result {
            case .success(let updatedUser):
                print("✅ 更新用户信息成功")
                print("新昵称: \(updatedUser.nickname)")
                
            case .failure(let error):
                print("❌ 更新用户信息失败: \(error)")
            }
        }
    }
    
    // MARK: - 6. 群组管理
    
    func createGroup() {
        let groupManager = IMClient.shared.groupManager!
        
        groupManager.createGroup(
            groupName: "我的群组",
            faceURL: "https://example.com/group-avatar.jpg",
            introduction: "这是一个测试群组",
            memberUserIDs: ["user1", "user2", "user3"]
        ) { result in
            switch result {
            case .success(let group):
                print("✅ 创建群组成功")
                print("群组 ID: \(group.groupID)")
                print("群组名称: \(group.groupName)")
                print("成员数: \(group.memberCount)")
                
            case .failure(let error):
                print("❌ 创建群组失败: \(error)")
            }
        }
    }
    
    func inviteToGroup(groupID: String, userIDs: [String]) {
        let groupManager = IMClient.shared.groupManager!
        
        groupManager.inviteMembers(groupID: groupID, userIDs: userIDs) { result in
            switch result {
            case .success:
                print("✅ 邀请成员成功")
            case .failure(let error):
                print("❌ 邀请成员失败: \(error)")
            }
        }
    }
    
    // MARK: - 7. 好友管理
    
    func addFriend(userID: String) {
        let friendManager = IMClient.shared.friendManager!
        
        friendManager.addFriend(userID: userID, message: "你好，我想加你为好友") { result in
            switch result {
            case .success:
                print("✅ 发送好友请求成功")
            case .failure(let error):
                print("❌ 发送好友请求失败: \(error)")
            }
        }
    }
    
    func getFriendList() {
        let friendManager = IMClient.shared.friendManager!
        
        friendManager.getFriendList { result in
            switch result {
            case .success(let friends):
                print("✅ 获取好友列表成功")
                print("好友数量: \(friends.count)")
                
                for friend in friends {
                    print("好友 ID: \(friend.friendUserID)")
                    print("备注: \(friend.remark)")
                    print("---")
                }
                
            case .failure(let error):
                print("❌ 获取好友列表失败: \(error)")
            }
        }
    }
    
    // MARK: - 8. 监听器
    
    func setupAllListeners() {
        // 连接监听器
        IMClient.shared.addConnectionListener(self)
        
        // 消息监听器
        IMClient.shared.addMessageListener(self)
        
        // 会话监听器
        IMClient.shared.addConversationListener(self)
        
        // 用户监听器
        IMClient.shared.addUserListener(self)
        
        // 群组监听器
        IMClient.shared.addGroupListener(self)
        
        // 好友监听器
        IMClient.shared.addFriendListener(self)
    }
}

// MARK: - 实现监听器协议

extension IMSDKBasicUsageExample: IMConnectionListener {
    func onConnected() {
        print("🟢 WebSocket 已连接")
    }
    
    func onDisconnected(error: Error?) {
        print("🔴 WebSocket 已断开: \(error?.localizedDescription ?? "unknown")")
    }
    
    func onConnectionStateChanged(_ state: IMConnectionState) {
        print("🔄 连接状态改变: \(state)")
    }
}

extension IMSDKBasicUsageExample: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        print("📨 收到新消息")
        print("发送者: \(message.senderID)")
        print("内容: \(message.content)")
        print("时间: \(IMUtils.formatTimestamp(message.sendTime))")
    }
    
    func onMessageStatusChanged(_ message: IMMessage) {
        print("📝 消息状态改变: \(message.messageID) -> \(message.status)")
    }
}

extension IMSDKBasicUsageExample: IMConversationListener {
    func onConversationUpdated(_ conversation: IMConversation) {
        print("💬 会话更新: \(conversation.showName)")
    }
    
    func onUnreadCountChanged(_ conversationID: String, count: Int) {
        print("🔔 未读数改变: \(conversationID) -> \(count)")
    }
    
    func onTotalUnreadCountChanged(_ count: Int) {
        print("🔔 总未读数: \(count)")
    }
}

extension IMSDKBasicUsageExample: IMUserListener {
    func onUserInfoUpdated(_ user: IMUser) {
        print("👤 用户信息更新: \(user.nickname)")
    }
}

extension IMSDKBasicUsageExample: IMGroupListener {
    func onJoinedGroup(_ group: IMGroup) {
        print("👥 加入群组: \(group.groupName)")
    }
    
    func onGroupInfoUpdated(_ group: IMGroup) {
        print("👥 群组信息更新: \(group.groupName)")
    }
}

extension IMSDKBasicUsageExample: IMFriendListener {
    func onFriendAdded(_ friend: IMFriend) {
        print("👫 添加好友: \(friend.friendUserID)")
    }
    
    func onFriendRequestReceived(_ userID: String, message: String) {
        print("👋 收到好友请求: \(userID) - \(message)")
    }
}


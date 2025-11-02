//
//  TalkConfig.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import Foundation

/// Talk 应用配置
struct TalkConfig {
    /// IM 服务器地址（根据你的服务器地址修改）
    static let imServerURL = "ws://localhost:8080/ws"
    
    /// API 服务器地址
    static let apiServerURL = "http://localhost:8080"
    
    /// 默认头像
    static let defaultAvatar = "person.circle.fill"
    
    /// 应用名称
    static let appName = "Talk"
}

/// 用户信息持久化
class UserDefaults_Keys {
    static let currentUserID = "current_user_id"
    static let currentUserToken = "current_user_token"
    static let currentUserNickname = "current_user_nickname"
    static let isLoggedIn = "is_logged_in"
}


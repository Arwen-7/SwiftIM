/// IMGroupManager - 群组管理器
/// 负责群组的创建、解散、成员管理等

import Foundation

/// 群组监听器
public protocol IMGroupListener: AnyObject {
    /// 群组信息更新
    func onGroupInfoUpdated(_ group: IMGroup)
    
    /// 加入群组
    func onJoinedGroup(_ group: IMGroup)
    
    /// 退出群组
    func onLeftGroup(_ groupID: String)
    
    /// 被邀请进群
    func onInvitedToGroup(_ group: IMGroup, inviterUserID: String)
    
    /// 被踢出群
    func onKickedFromGroup(_ groupID: String, operatorUserID: String)
}

public extension IMGroupListener {
    func onGroupInfoUpdated(_ group: IMGroup) {}
    func onJoinedGroup(_ group: IMGroup) {}
    func onLeftGroup(_ groupID: String) {}
    func onInvitedToGroup(_ group: IMGroup, inviterUserID: String) {}
    func onKickedFromGroup(_ groupID: String, operatorUserID: String) {}
}

/// 群组管理器
public final class IMGroupManager {
    
    // MARK: - Properties
    
    private let database: IMDatabaseProtocol
    private let httpManager: IMHTTPManager
    
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 群组缓存
    private let groupCache = IMMemoryCache<IMGroup>(countLimit: 100)
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, httpManager: IMHTTPManager) {
        self.database = database
        self.httpManager = httpManager
    }
    
    // MARK: - Listener Management
    
    /// 添加群组监听器
    public func addListener(_ listener: IMGroupListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除群组监听器
    public func removeListener(_ listener: IMGroupListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    /// 通知所有监听器
    private func notifyListeners(_ block: (IMGroupListener) -> Void) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMGroupListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Create Group
    
    /// 创建群组
    public func createGroup(
        groupName: String,
        faceURL: String = "",
        introduction: String = "",
        memberUserIDs: [String] = [],
        completion: @escaping (Result<IMGroup, IMError>) -> Void
    ) {
        struct CreateGroupRequest: IMRequest {
            let path = "/api/group/create"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(groupName: String, faceURL: String, introduction: String, memberUserIDs: [String]) {
                self.parameters = [
                    "groupName": groupName,
                    "faceURL": faceURL,
                    "introduction": introduction,
                    "memberUserIDs": memberUserIDs
                ]
            }
        }
        
        let request = CreateGroupRequest(
            groupName: groupName,
            faceURL: faceURL,
            introduction: introduction,
            memberUserIDs: memberUserIDs
        )
        
        httpManager.request(request, responseType: IMGroup.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let group = response.data {
                    // 保存到数据库
                    try? self?.database.saveGroup(group)
                    
                    // 添加到缓存
                    self?.groupCache.set(group, forKey: group.groupID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onJoinedGroup(group) }
                    
                    completion(.success(group))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Join/Leave Group
    
    /// 加入群组
    public func joinGroup(
        groupID: String,
        completion: @escaping (Result<IMGroup, IMError>) -> Void
    ) {
        struct JoinGroupRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .post
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
            
            init(groupID: String) {
                self.path = "/api/group/\(groupID)/join"
            }
        }
        
        let request = JoinGroupRequest(groupID: groupID)
        
        httpManager.request(request, responseType: IMGroup.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let group = response.data {
                    // 保存到数据库
                    try? self?.database.saveGroup(group)
                    
                    // 添加到缓存
                    self?.groupCache.set(group, forKey: group.groupID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onJoinedGroup(group) }
                    
                    completion(.success(group))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 退出群组
    public func leaveGroup(
        groupID: String,
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct LeaveGroupRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .post
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
            
            init(groupID: String) {
                self.path = "/api/group/\(groupID)/leave"
            }
        }
        
        let request = LeaveGroupRequest(groupID: groupID)
        
        httpManager.request(request, responseType: String.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    // 从缓存移除
                    self?.groupCache.remove(forKey: groupID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onLeftGroup(groupID) }
                    
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Get Group Info
    
    /// 获取群组信息
    public func getGroupInfo(
        groupID: String,
        forceUpdate: Bool = false,
        completion: @escaping (Result<IMGroup, IMError>) -> Void
    ) {
        // 如果不强制更新，先从缓存获取
        if !forceUpdate, let group = groupCache.get(forKey: groupID) {
            completion(.success(group))
            return
        }
        
        // 从数据库获取
        if !forceUpdate, let group = database.getGroup(groupID: groupID) {
            groupCache.set(group, forKey: groupID)
            completion(.success(group))
            return
        }
        
        // 从服务器获取
        fetchGroupInfoFromServer(groupID: groupID, completion: completion)
    }
    
    /// 从服务器获取群组信息
    private func fetchGroupInfoFromServer(
        groupID: String,
        completion: @escaping (Result<IMGroup, IMError>) -> Void
    ) {
        struct GetGroupRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .get
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
            
            init(groupID: String) {
                self.path = "/api/group/\(groupID)"
            }
        }
        
        let request = GetGroupRequest(groupID: groupID)
        
        httpManager.request(request, responseType: IMGroup.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let group = response.data {
                    // 保存到数据库
                    try? self?.database.saveGroup(group)
                    
                    // 添加到缓存
                    self?.groupCache.set(group, forKey: groupID)
                    
                    completion(.success(group))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update Group Info
    
    /// 更新群组信息
    public func updateGroupInfo(
        groupID: String,
        groupName: String? = nil,
        faceURL: String? = nil,
        introduction: String? = nil,
        notification: String? = nil,
        completion: @escaping (Result<IMGroup, IMError>) -> Void
    ) {
        var params: [String: Any] = ["groupID": groupID]
        if let name = groupName { params["groupName"] = name }
        if let url = faceURL { params["faceURL"] = url }
        if let intro = introduction { params["introduction"] = intro }
        if let notif = notification { params["notification"] = notif }
        
        struct UpdateGroupRequest: IMRequest {
            let path = "/api/group/update"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(parameters: [String: Any]) {
                self.parameters = parameters
            }
        }
        
        let request = UpdateGroupRequest(parameters: params)
        
        httpManager.request(request, responseType: IMGroup.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let group = response.data {
                    // 更新数据库
                    try? self?.database.saveGroup(group)
                    
                    // 更新缓存
                    self?.groupCache.set(group, forKey: groupID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onGroupInfoUpdated(group) }
                    
                    completion(.success(group))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Invite Members
    
    /// 邀请成员
    public func inviteMembers(
        groupID: String,
        userIDs: [String],
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct InviteMembersRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(groupID: String, userIDs: [String]) {
                self.path = "/api/group/\(groupID)/invite"
                self.parameters = ["userIDs": userIDs]
            }
        }
        
        let request = InviteMembersRequest(groupID: groupID, userIDs: userIDs)
        
        httpManager.request(request, responseType: String.self) { result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Kick Members
    
    /// 踢出成员
    public func kickMembers(
        groupID: String,
        userIDs: [String],
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct KickMembersRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(groupID: String, userIDs: [String]) {
                self.path = "/api/group/\(groupID)/kick"
                self.parameters = ["userIDs": userIDs]
            }
        }
        
        let request = KickMembersRequest(groupID: groupID, userIDs: userIDs)
        
        httpManager.request(request, responseType: String.self) { result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Dismiss Group
    
    /// 解散群组
    public func dismissGroup(
        groupID: String,
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct DismissGroupRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .post
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
            
            init(groupID: String) {
                self.path = "/api/group/\(groupID)/dismiss"
            }
        }
        
        let request = DismissGroupRequest(groupID: groupID)
        
        httpManager.request(request, responseType: String.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    // 从缓存移除
                    self?.groupCache.remove(forKey: groupID)
                    
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}


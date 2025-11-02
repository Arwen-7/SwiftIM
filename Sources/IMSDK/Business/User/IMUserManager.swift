/// IMUserManager - 用户管理器
/// 负责用户信息的管理和同步

import Foundation
import Alamofire

/// 用户监听器
public protocol IMUserListener: AnyObject {
    /// 用户信息更新
    func onUserInfoUpdated(_ user: IMUser)
}

public extension IMUserListener {
    func onUserInfoUpdated(_ user: IMUser) {}
}

/// 用户管理器
public final class IMUserManager {
    
    // MARK: - Properties
    
    private let database: IMDatabaseProtocol
    private let httpManager: IMHTTPManager
    
    private var currentUser: IMUser?
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 用户信息缓存
    private let userCache = IMMemoryCache<IMUser>(countLimit: 500)
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, httpManager: IMHTTPManager) {
        self.database = database
        self.httpManager = httpManager
    }
    
    // MARK: - Listener Management
    
    /// 添加用户监听器
    public func addListener(_ listener: IMUserListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除用户监听器
    public func removeListener(_ listener: IMUserListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    /// 通知所有监听器
    private func notifyListeners(_ block: @escaping (IMUserListener) -> Void) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMUserListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Current User
    
    /// 设置当前用户
    public func setCurrentUser(_ user: IMUser) {
        self.currentUser = user
        
        // 保存到数据库
        try? database.saveUser(user)
        
        // 添加到缓存
        userCache.set(user, forKey: user.userID)
    }
    
    /// 获取当前用户
    public func getCurrentUser() -> IMUser? {
        return currentUser
    }
    
    /// 获取当前用户 ID
    public func getCurrentUserID() -> String {
        return currentUser?.userID ?? ""
    }
    
    // MARK: - User Info
    
    /// 获取用户信息
    public func getUserInfo(
        userID: String,
        forceUpdate: Bool = false,
        completion: @escaping (Result<IMUser, IMError>) -> Void
    ) {
        // 如果不强制更新，先从缓存获取
        if !forceUpdate, let user = userCache.get(forKey: userID) {
            completion(.success(user))
            return
        }
        
        // 从数据库获取
        if !forceUpdate, let user = database.getUser(userID: userID) {
            userCache.set(user, forKey: userID)
            completion(.success(user))
            return
        }
        
        // 从服务器获取
        fetchUserInfoFromServer(userID: userID, completion: completion)
    }
    
    /// 批量获取用户信息
    public func getUsersInfo(
        userIDs: [String],
        completion: @escaping (Result<[IMUser], IMError>) -> Void
    ) {
        var users: [IMUser] = []
        var missingUserIDs: [String] = []
        
        // 先从缓存和数据库获取
        for userID in userIDs {
            if let user = userCache.get(forKey: userID) {
                users.append(user)
            } else if let user = database.getUser(userID: userID) {
                userCache.set(user, forKey: userID)
                users.append(user)
            } else {
                missingUserIDs.append(userID)
            }
        }
        
        // 如果都有缓存，直接返回
        if missingUserIDs.isEmpty {
            completion(.success(users))
            return
        }
        
        // 从服务器批量获取缺失的用户信息
        fetchUsersInfoFromServer(userIDs: missingUserIDs) { result in
            switch result {
            case .success(let fetchedUsers):
                users.append(contentsOf: fetchedUsers)
                completion(.success(users))
            case .failure(let error):
                // 即使失败也返回已有的用户信息
                if !users.isEmpty {
                    completion(.success(users))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// 从服务器获取用户信息
    private func fetchUserInfoFromServer(
        userID: String,
        completion: @escaping (Result<IMUser, IMError>) -> Void
    ) {
        struct GetUserRequest: IMRequest {
            let path: String
            let method: HTTPMethod = .get
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
            
            init(userID: String) {
                self.path = "/api/user/info/\(userID)"
            }
        }
        
        let request = GetUserRequest(userID: userID)
        
        httpManager.request(request, responseType: IMUser.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let user = response.data {
                    // 保存到数据库
                    try? self?.database.saveUser(user)
                    
                    // 添加到缓存
                    self?.userCache.set(user, forKey: userID)
                    
                    completion(.success(user))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 从服务器批量获取用户信息
    private func fetchUsersInfoFromServer(
        userIDs: [String],
        completion: @escaping (Result<[IMUser], IMError>) -> Void
    ) {
        struct GetUsersRequest: IMRequest {
            let path = "/api/user/info/batch"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userIDs: [String]) {
                self.parameters = ["userIDs": userIDs]
            }
        }
        
        let request = GetUsersRequest(userIDs: userIDs)
        
        httpManager.request(request, responseType: [IMUser].self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let users = response.data {
                    // 保存到数据库
                    try? self?.database.saveUsers(users)
                    
                    // 添加到缓存
                    for user in users {
                        self?.userCache.set(user, forKey: user.userID)
                    }
                    
                    completion(.success(users))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update User Info
    
    /// 更新用户信息
    public func updateUserInfo(
        _ user: IMUser,
        completion: @escaping (Result<IMUser, IMError>) -> Void
    ) {
        struct UpdateUserRequest: IMRequest {
            let path = "/api/user/update"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(user: IMUser) {
                self.parameters = [
                    "userID": user.userID,
                    "nickname": user.nickname,
                    "avatar": user.avatar,
                    "signature": user.signature,
                    "gender": user.gender,
                    "birth": user.birth
                ]
            }
        }
        
        let request = UpdateUserRequest(user: user)
        
        httpManager.request(request, responseType: IMUser.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let updatedUser = response.data {
                    // 更新数据库
                    try? self?.database.saveUser(updatedUser)
                    
                    // 更新缓存
                    self?.userCache.set(updatedUser, forKey: updatedUser.userID)
                    
                    // 如果是当前用户，更新
                    if updatedUser.userID == self?.getCurrentUserID() {
                        self?.currentUser = updatedUser
                    }
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onUserInfoUpdated(updatedUser) }
                    
                    completion(.success(updatedUser))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Search
    
    /// 搜索用户
    public func searchUsers(
        keyword: String,
        completion: @escaping (Result<[IMUser], IMError>) -> Void
    ) {
        struct SearchUsersRequest: IMRequest {
            let path = "/api/user/search"
            let method: HTTPMethod = .get
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(keyword: String) {
                self.parameters = ["keyword": keyword]
            }
        }
        
        let request = SearchUsersRequest(keyword: keyword)
        
        httpManager.request(request, responseType: [IMUser].self) { result in
            switch result {
            case .success(let response):
                if response.isSuccess, let users = response.data {
                    completion(.success(users))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}


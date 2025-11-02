/// IMFriendManager - 好友管理器
/// 负责好友的添加、删除、备注等

import Foundation
import Alamofire

/// 好友监听器
public protocol IMFriendListener: AnyObject {
    /// 好友添加
    func onFriendAdded(_ friend: IMFriend)
    
    /// 好友删除
    func onFriendDeleted(_ friendUserID: String)
    
    /// 好友信息更新
    func onFriendInfoUpdated(_ friend: IMFriend)
    
    /// 收到好友请求
    func onFriendRequestReceived(_ userID: String, message: String)
    
    /// 好友请求被接受
    func onFriendRequestAccepted(_ userID: String)
}

public extension IMFriendListener {
    func onFriendAdded(_ friend: IMFriend) {}
    func onFriendDeleted(_ friendUserID: String) {}
    func onFriendInfoUpdated(_ friend: IMFriend) {}
    func onFriendRequestReceived(_ userID: String, message: String) {}
    func onFriendRequestAccepted(_ userID: String) {}
}

/// 好友管理器
public final class IMFriendManager {
    
    // MARK: - Properties
    
    private let database: IMDatabaseProtocol
    private let httpManager: IMHTTPManager
    
    private var listeners: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let listenerLock = NSLock()
    
    // 好友缓存
    private let friendCache = IMMemoryCache<IMFriend>(countLimit: 500)
    
    // MARK: - Initialization
    
    public init(database: IMDatabaseProtocol, httpManager: IMHTTPManager) {
        self.database = database
        self.httpManager = httpManager
    }
    
    // MARK: - Listener Management
    
    /// 添加好友监听器
    public func addListener(_ listener: IMFriendListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.add(listener)
    }
    
    /// 移除好友监听器
    public func removeListener(_ listener: IMFriendListener) {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        listeners.remove(listener)
    }
    
    /// 通知所有监听器
    private func notifyListeners(_ block: @escaping (IMFriendListener) -> Void) {
        listenerLock.lock()
        let allListeners = listeners.allObjects.compactMap { $0 as? IMFriendListener }
        listenerLock.unlock()
        
        DispatchQueue.main.async {
            allListeners.forEach { block($0) }
        }
    }
    
    // MARK: - Add Friend
    
    /// 添加好友
    public func addFriend(
        userID: String,
        message: String = "",
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct AddFriendRequest: IMRequest {
            let path = "/api/friend/add"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String, message: String) {
                self.parameters = [
                    "userID": userID,
                    "message": message
                ]
            }
        }
        
        let request = AddFriendRequest(userID: userID, message: message)
        
        httpManager.request(request, responseType: String.self) { result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    IMLogger.shared.info("Friend request sent to \(userID)")
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 接受好友请求
    public func acceptFriendRequest(
        userID: String,
        completion: @escaping (Result<IMFriend, IMError>) -> Void
    ) {
        struct AcceptFriendRequest: IMRequest {
            let path = "/api/friend/accept"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String) {
                self.parameters = ["userID": userID]
            }
        }
        
        let request = AcceptFriendRequest(userID: userID)
        
        httpManager.request(request, responseType: IMFriend.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let friend = response.data {
                    // 添加到缓存
                    self?.friendCache.set(friend, forKey: friend.friendUserID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onFriendAdded(friend) }
                    
                    completion(.success(friend))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 拒绝好友请求
    public func rejectFriendRequest(
        userID: String,
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct RejectFriendRequest: IMRequest {
            let path = "/api/friend/reject"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String) {
                self.parameters = ["userID": userID]
            }
        }
        
        let request = RejectFriendRequest(userID: userID)
        
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
    
    // MARK: - Delete Friend
    
    /// 删除好友
    public func deleteFriend(
        userID: String,
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct DeleteFriendRequest: IMRequest {
            let path = "/api/friend/delete"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String) {
                self.parameters = ["userID": userID]
            }
        }
        
        let request = DeleteFriendRequest(userID: userID)
        
        httpManager.request(request, responseType: String.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess {
                    // 从缓存移除
                    self?.friendCache.remove(forKey: userID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onFriendDeleted(userID) }
                    
                    completion(.success(()))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Get Friends
    
    /// 获取好友列表
    public func getFriendList(
        completion: @escaping (Result<[IMFriend], IMError>) -> Void
    ) {
        struct GetFriendListRequest: IMRequest {
            let path = "/api/friend/list"
            let method: HTTPMethod = .get
            let parameters: [String: Any]? = nil
            let headers: HTTPHeaders? = nil
        }
        
        let request = GetFriendListRequest()
        
        httpManager.request(request, responseType: [IMFriend].self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let friends = response.data {
                    // 添加到缓存
                    for friend in friends {
                        self?.friendCache.set(friend, forKey: friend.friendUserID)
                    }
                    
                    completion(.success(friends))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 检查是否为好友
    public func isFriend(
        userID: String,
        completion: @escaping (Result<Bool, IMError>) -> Void
    ) {
        struct CheckFriendRequest: IMRequest {
            let path = "/api/friend/check"
            let method: HTTPMethod = .get
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String) {
                self.parameters = ["userID": userID]
            }
        }
        
        let request = CheckFriendRequest(userID: userID)
        
        httpManager.request(request, responseType: Bool.self) { result in
            switch result {
            case .success(let response):
                if response.isSuccess, let isFriend = response.data {
                    completion(.success(isFriend))
                } else {
                    completion(.failure(.networkError(response.message)))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update Friend
    
    /// 设置好友备注
    public func setFriendRemark(
        userID: String,
        remark: String,
        completion: @escaping (Result<Void, IMError>) -> Void
    ) {
        struct SetRemarkRequest: IMRequest {
            let path = "/api/friend/remark"
            let method: HTTPMethod = .post
            let parameters: [String: Any]?
            let headers: HTTPHeaders? = nil
            
            init(userID: String, remark: String) {
                self.parameters = [
                    "userID": userID,
                    "remark": remark
                ]
            }
        }
        
        let request = SetRemarkRequest(userID: userID, remark: remark)
        
        httpManager.request(request, responseType: IMFriend.self) { [weak self] result in
            switch result {
            case .success(let response):
                if response.isSuccess, let friend = response.data {
                    // 更新缓存
                    self?.friendCache.set(friend, forKey: friend.friendUserID)
                    
                    // 通知监听器
                    self?.notifyListeners { $0.onFriendInfoUpdated(friend) }
                    
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


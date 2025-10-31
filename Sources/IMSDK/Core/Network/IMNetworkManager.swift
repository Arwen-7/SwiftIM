/// IMNetworkManager - HTTP 网络管理器
/// 提供 HTTP 网络通信功能（包括请求、文件上传/下载）

import Foundation
import Alamofire

// MARK: - 网络请求协议

/// 网络请求
public protocol IMRequest {
    var path: String { get }
    var method: HTTPMethod { get }
    var parameters: [String: Any]? { get }
    var headers: HTTPHeaders? { get }
}

/// 网络响应
public struct IMResponse<T: Decodable> {
    public let code: Int
    public let message: String
    public let data: T?
    
    public var isSuccess: Bool {
        return code == 0
    }
}

// MARK: - HTTP Manager

/// HTTP 网络管理器
public final class IMHTTPManager {
    
    // MARK: - Properties
    
    private let session: Session
    private var baseURL: String
    private var defaultHeaders: HTTPHeaders
    
    // MARK: - Initialization
    
    public init(baseURL: String, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        
        self.session = Session(configuration: configuration)
        self.defaultHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }
    
    // MARK: - Public Methods
    
    /// 设置基础 URL
    public func setBaseURL(_ url: String) {
        self.baseURL = url
    }
    
    /// 设置默认请求头
    public func setDefaultHeaders(_ headers: HTTPHeaders) {
        self.defaultHeaders = headers
    }
    
    /// 添加请求头
    public func addHeader(name: String, value: String) {
        defaultHeaders.add(name: name, value: value)
    }
    
    /// 发送请求
    /// - Parameters:
    ///   - request: 请求
    ///   - responseType: 响应类型
    ///   - completion: 完成回调
    public func request<T: Decodable>(
        _ request: IMRequest,
        responseType: T.Type,
        completion: @escaping (Result<IMResponse<T>, IMError>) -> Void
    ) {
        let url = baseURL + request.path
        var headers = defaultHeaders
        if let requestHeaders = request.headers {
            requestHeaders.forEach { headers.add($0) }
        }
        
        IMLogger.shared.debug("HTTP Request: \(request.method.rawValue) \(url)")
        
        session.request(
            url,
            method: request.method,
            parameters: request.parameters,
            encoding: JSONEncoding.default,
            headers: headers
        )
        .validate()
        .responseDecodable(of: IMResponse<T>.self) { response in
            switch response.result {
            case .success(let imResponse):
                IMLogger.shared.debug("HTTP Response: code=\(imResponse.code), message=\(imResponse.message)")
                completion(.success(imResponse))
                
            case .failure(let error):
                IMLogger.shared.error("HTTP Error: \(error)")
                let imError = self.convertError(error)
                completion(.failure(imError))
            }
        }
    }
    
    /// 上传文件
    /// - Parameters:
    ///   - fileData: 文件数据
    ///   - path: 上传路径
    ///   - fileName: 文件名
    ///   - mimeType: MIME 类型
    ///   - progress: 进度回调
    ///   - completion: 完成回调
    public func upload(
        fileData: Data,
        path: String,
        fileName: String,
        mimeType: String = "application/octet-stream",
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, IMError>) -> Void
    ) {
        let url = baseURL + path
        
        IMLogger.shared.debug("Upload file: \(url)")
        
        session.upload(
            multipartFormData: { multipartFormData in
                multipartFormData.append(
                    fileData,
                    withName: "file",
                    fileName: fileName,
                    mimeType: mimeType
                )
            },
            to: url,
            headers: defaultHeaders
        )
        .uploadProgress { uploadProgress in
            progress?(uploadProgress.fractionCompleted)
        }
        .responseDecodable(of: IMResponse<String>.self) { response in
            switch response.result {
            case .success(let imResponse):
                if imResponse.isSuccess, let fileURL = imResponse.data {
                    IMLogger.shared.debug("Upload success: \(fileURL)")
                    completion(.success(fileURL))
                } else {
                    completion(.failure(.networkError(imResponse.message)))
                }
                
            case .failure(let error):
                IMLogger.shared.error("Upload error: \(error)")
                completion(.failure(self.convertError(error)))
            }
        }
    }
    
    /// 下载文件
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - destination: 保存路径
    ///   - progress: 进度回调
    ///   - completion: 完成回调
    public func download(
        url: String,
        destination: URL,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<URL, IMError>) -> Void
    ) {
        IMLogger.shared.debug("Download file: \(url)")
        
        let downloadDestination: DownloadRequest.Destination = { _, _ in
            return (destination, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        session.download(url, to: downloadDestination)
            .downloadProgress { downloadProgress in
                progress?(downloadProgress.fractionCompleted)
            }
            .response { response in
                if let error = response.error {
                    IMLogger.shared.error("Download error: \(error)")
                    completion(.failure(self.convertError(error)))
                } else if let fileURL = response.fileURL {
                    IMLogger.shared.debug("Download success: \(fileURL)")
                    completion(.success(fileURL))
                } else {
                    completion(.failure(.networkError("Download failed")))
                }
            }
    }
    
    // MARK: - Private Methods
    
    private func convertError(_ error: AFError) -> IMError {
        if error.isSessionTaskError {
            if let underlyingError = error.underlyingError as? URLError {
                switch underlyingError.code {
                case .timedOut:
                    return .timeout
                case .notConnectedToInternet:
                    return .networkError("No internet connection")
                default:
                    return .networkError(underlyingError.localizedDescription)
                }
            }
        }
        return .networkError(error.localizedDescription)
    }
}

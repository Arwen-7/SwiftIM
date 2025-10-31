/// IMCrypto - 加密工具
/// 提供 AES、RSA 加密，消息签名等安全功能

import Foundation
import CryptoSwift
import CommonCrypto

/// 加密错误
public enum IMCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidKey
    case invalidData
    case keyGenerationFailed
}

/// 加密工具类
public final class IMCrypto {
    
    // MARK: - Singleton
    
    public static let shared = IMCrypto()
    
    private init() {}
    
    // MARK: - AES Encryption
    
    /// AES-256-CBC 加密
    /// - Parameters:
    ///   - data: 要加密的数据
    ///   - key: 加密密钥（32字节）
    ///   - iv: 初始化向量（16字节）
    /// - Returns: 加密后的数据
    public func aesEncrypt(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 32, iv.count == 16 else {
            throw IMCryptoError.invalidKey
        }
        
        do {
            let aes = try AES(key: Array(key), blockMode: CBC(iv: Array(iv)), padding: .pkcs7)
            let encrypted = try aes.encrypt(Array(data))
            return Data(encrypted)
        } catch {
            IMLogger.shared.error("AES encryption failed: \(error)")
            throw IMCryptoError.encryptionFailed
        }
    }
    
    /// AES-256-CBC 解密
    /// - Parameters:
    ///   - data: 要解密的数据
    ///   - key: 解密密钥（32字节）
    ///   - iv: 初始化向量（16字节）
    /// - Returns: 解密后的数据
    public func aesDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 32, iv.count == 16 else {
            throw IMCryptoError.invalidKey
        }
        
        do {
            let aes = try AES(key: Array(key), blockMode: CBC(iv: Array(iv)), padding: .pkcs7)
            let decrypted = try aes.decrypt(Array(data))
            return Data(decrypted)
        } catch {
            IMLogger.shared.error("AES decryption failed: \(error)")
            throw IMCryptoError.decryptionFailed
        }
    }
    
    /// 使用密码加密（自动生成 key 和 iv）
    /// - Parameters:
    ///   - data: 要加密的数据
    ///   - password: 密码
    /// - Returns: (加密数据, salt, iv)
    public func encryptWithPassword(data: Data, password: String) throws -> (encrypted: Data, salt: Data, iv: Data) {
        // 生成随机 salt 和 iv
        let salt = generateRandomData(length: 32)
        let iv = generateRandomData(length: 16)
        
        // 使用 PBKDF2 从密码派生密钥
        let key = try deriveKey(password: password, salt: salt)
        
        // 加密
        let encrypted = try aesEncrypt(data: data, key: key, iv: iv)
        
        return (encrypted, salt, iv)
    }
    
    /// 使用密码解密
    /// - Parameters:
    ///   - data: 要解密的数据
    ///   - password: 密码
    ///   - salt: 盐值
    ///   - iv: 初始化向量
    /// - Returns: 解密后的数据
    public func decryptWithPassword(data: Data, password: String, salt: Data, iv: Data) throws -> Data {
        // 使用 PBKDF2 从密码派生密钥
        let key = try deriveKey(password: password, salt: salt)
        
        // 解密
        return try aesDecrypt(data: data, key: key, iv: iv)
    }
    
    // MARK: - Key Derivation
    
    /// 从密码派生密钥（PBKDF2）
    /// - Parameters:
    ///   - password: 密码
    ///   - salt: 盐值
    ///   - rounds: 迭代次数
    /// - Returns: 派生的密钥
    private func deriveKey(password: String, salt: Data, rounds: Int = 10000) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw IMCryptoError.invalidData
        }
        
        var derivedKey = Data(count: 32)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    32
                )
            }
        }
        
        guard result == kCCSuccess else {
            throw IMCryptoError.keyGenerationFailed
        }
        
        return derivedKey
    }
    
    // MARK: - Hash Functions
    
    /// SHA256 哈希
    /// - Parameter data: 要哈希的数据
    /// - Returns: 哈希值
    public func sha256(data: Data) -> Data {
        return Data(data.sha256())
    }
    
    /// SHA256 哈希（字符串）
    /// - Parameter string: 要哈希的字符串
    /// - Returns: 哈希值（十六进制字符串）
    public func sha256(string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return data.sha256().toHexString()
    }
    
    /// MD5 哈希
    /// - Parameter data: 要哈希的数据
    /// - Returns: 哈希值
    public func md5(data: Data) -> Data {
        return Data(data.md5())
    }
    
    /// MD5 哈希（字符串）
    /// - Parameter string: 要哈希的字符串
    /// - Returns: 哈希值（十六进制字符串）
    public func md5(string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return data.md5().toHexString()
    }
    
    // MARK: - HMAC
    
    /// HMAC-SHA256
    /// - Parameters:
    ///   - data: 要签名的数据
    ///   - key: 密钥
    /// - Returns: HMAC 值
    public func hmacSHA256(data: Data, key: Data) -> Data {
        do {
            let hmac = try HMAC(key: Array(key), variant: .sha2(.sha256))
            let result = try hmac.authenticate(Array(data))
            return Data(result)
        } catch {
            IMLogger.shared.error("HMAC generation failed: \(error)")
            return Data()
        }
    }
    
    // MARK: - Random Data Generation
    
    /// 生成随机数据
    /// - Parameter length: 数据长度
    /// - Returns: 随机数据
    public func generateRandomData(length: Int) -> Data {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, length, bytes.baseAddress!)
        }
        return data
    }
    
    /// 生成随机密钥（32字节）
    /// - Returns: 随机密钥
    public func generateRandomKey() -> Data {
        return generateRandomData(length: 32)
    }
    
    /// 生成随机 IV（16字节）
    /// - Returns: 随机 IV
    public func generateRandomIV() -> Data {
        return generateRandomData(length: 16)
    }
    
    // MARK: - Base64
    
    /// Base64 编码
    /// - Parameter data: 要编码的数据
    /// - Returns: Base64 字符串
    public func base64Encode(data: Data) -> String {
        return data.base64EncodedString()
    }
    
    /// Base64 解码
    /// - Parameter string: Base64 字符串
    /// - Returns: 解码后的数据
    public func base64Decode(string: String) -> Data? {
        return Data(base64Encoded: string)
    }
}

// MARK: - Extensions

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}


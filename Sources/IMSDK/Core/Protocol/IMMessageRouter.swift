//
//  IMMessageRouter.swift
//  IMSDK
//
//  Created by Arwen on 2025/10/27.
//  Updated: 2025/10/28 - Migrated to Protobuf
//

import Foundation
import SwiftProtobuf

// MARK: - 消息路由器

/// 消息路由器（根据命令类型路由到不同的处理器）
/// 使用 Protobuf 解析消息体
public final class IMMessageRouter {
    
    // MARK: - Type Aliases
    
    public typealias MessageHandler<T: SwiftProtobuf.Message> = (T, UInt32) -> Void
    
    // MARK: - Properties
    
    private let encoder: IMMessageEncoder
    private var handlers: [IMCommandType: Any] = [:]
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init() {
        self.encoder = IMMessageEncoder()
    }
    
    // MARK: - Register Handlers
    
    /// 注册消息处理器（Protobuf 版本）
    /// - Parameters:
    ///   - command: 命令类型
    ///   - type: Protobuf 消息类型
    ///   - handler: 处理器
    public func register<T: SwiftProtobuf.Message>(command: IMCommandType, type: T.Type, handler: @escaping MessageHandler<T>) {
        lock.lock()
        defer { lock.unlock() }
        
        handlers[command] = handler
    }
    
    /// 取消注册
    /// - Parameter command: 命令类型
    public func unregister(command: IMCommandType) {
        lock.lock()
        defer { lock.unlock() }
        
        handlers.removeValue(forKey: command)
    }
    
    // MARK: - Route Messages
    
    /// 路由消息
    /// - Parameter data: 原始二进制数据
    public func route(data: Data) {
        do {
            // 解码数据包
            let packets = try encoder.decodeData(data)
            
            // 路由每个包
            for (command, sequence, body) in packets {
                routePacket(command: command, sequence: sequence, body: body)
            }
            
        } catch {
            print("[IMMessageRouter] 解码失败：\(error)")
        }
    }
    
    /// 路由单个数据包（使用 Protobuf 解析）
    private func routePacket(command: IMCommandType, sequence: UInt32, body: Data) {
        lock.lock()
        let handler = handlers[command]
        lock.unlock()
        
        guard handler != nil else {
            print("[IMMessageRouter] 未注册的命令类型：\(command)")
            return
        }
        
        // 根据命令类型使用 Protobuf 解码并调用处理器
        do {
            switch command {
            case .authRsp:
                let msg = try Im_Protocol_AuthResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_AuthResponse>)?(msg, sequence)
                
            case .sendMsgRsp:
                let msg = try Im_Protocol_SendMessageResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_SendMessageResponse>)?(msg, sequence)
                
            case .pushMsg:
                let msg = try Im_Protocol_PushMessage(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_PushMessage>)?(msg, sequence)
                
            case .batchMsg:
                let msg = try Im_Protocol_BatchMessages(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_BatchMessages>)?(msg, sequence)
                
            case .heartbeatRsp:
                let msg = try Im_Protocol_HeartbeatResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_HeartbeatResponse>)?(msg, sequence)
                
            case .revokeMsgRsp:
                let msg = try Im_Protocol_RevokeMessageResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_RevokeMessageResponse>)?(msg, sequence)
                
            case .revokeMsgPush:
                let msg = try Im_Protocol_RevokeMessagePush(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_RevokeMessagePush>)?(msg, sequence)
                
            case .batchSyncRsp:
                let msg = try Im_Protocol_BatchSyncResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_BatchSyncResponse>)?(msg, sequence)
                
            case .syncRangeRsp:
                let msg = try Im_Protocol_SyncRangeResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_SyncRangeResponse>)?(msg, sequence)
                
            case .readReceiptRsp:
                let msg = try Im_Protocol_ReadReceiptResponse(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_ReadReceiptResponse>)?(msg, sequence)
                
            case .readReceiptPush:
                let msg = try Im_Protocol_ReadReceiptPush(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_ReadReceiptPush>)?(msg, sequence)
                
            case .typingStatusPush:
                let msg = try Im_Protocol_TypingStatusPush(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_TypingStatusPush>)?(msg, sequence)
                
            case .kickOut:
                let msg = try Im_Protocol_KickOutNotification(serializedData: body)
                (handler as? MessageHandler<Im_Protocol_KickOutNotification>)?(msg, sequence)
                
            default:
                print("[IMMessageRouter] 不支持的命令类型：\(command)")
            }
            
        } catch {
            print("[IMMessageRouter] Protobuf 解码失败：\(error)")
        }
    }
}

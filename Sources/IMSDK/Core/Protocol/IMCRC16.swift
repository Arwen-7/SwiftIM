//
//  IMCRC16.swift
//  IMSDK
//
//  Created by IMSDK on 2025-01-26.
//

import Foundation

/// CRC16 校验工具（CCITT 标准）
/// 用于验证协议包头的完整性
public struct IMCRC16 {
    
    // MARK: - Constants
    
    /// CRC16-CCITT 多项式
    private static let polynomial: UInt16 = 0x1021
    
    /// 预计算的 CRC 表（性能优化）
    private static let table: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc: UInt16 = UInt16(i) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ polynomial
                } else {
                    crc = crc << 1
                }
            }
            table[i] = crc
        }
        return table
    }()
    
    // MARK: - Public Methods
    
    /// 计算数据的 CRC16 校验值
    /// - Parameter data: 要计算校验值的数据
    /// - Returns: CRC16 校验值
    public static func calculate(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF  // 初始值
        
        for byte in data {
            let index = Int((crc >> 8) ^ UInt16(byte))
            crc = (crc << 8) ^ table[index]
        }
        
        return crc
    }
    
    /// 验证数据的 CRC16 校验值
    /// - Parameters:
    ///   - data: 要验证的数据
    ///   - expectedCRC: 期望的 CRC 值
    /// - Returns: 校验是否通过
    public static func verify(_ data: Data, expectedCRC: UInt16) -> Bool {
        let calculatedCRC = calculate(data)
        return calculatedCRC == expectedCRC
    }
}

// MARK: - Extensions

extension UInt16 {
    /// 将 UInt16 转换为大端字节序的 Data
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    /// 将 UInt32 转换为大端字节序的 Data
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}


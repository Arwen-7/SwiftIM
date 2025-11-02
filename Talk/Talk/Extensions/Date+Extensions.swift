//
//  Date+Extensions.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import Foundation

extension Date {
    /// 从时间戳创建 Date（毫秒）
    static func fromTimestamp(_ timestamp: Int64) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    /// 转换为时间戳（毫秒）
    func toTimestamp() -> Int64 {
        return Int64(self.timeIntervalSince1970 * 1000)
    }
    
    /// 智能显示时间
    func smartTimeString() -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // 判断是否是今天
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: self)
        }
        
        // 判断是否是昨天
        if calendar.isDateInYesterday(self) {
            return "昨天"
        }
        
        // 判断是否在本周
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        if self > weekAgo {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: self)
        }
        
        // 判断是否在今年
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: self)
        }
        
        // 其他情况显示完整日期
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}


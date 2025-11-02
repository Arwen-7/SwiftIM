//
//  UIColor+Extensions.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit

extension UIColor {
    /// 主题色
    static let talkPrimary = UIColor.systemBlue
    
    /// 背景色
    static let talkBackground = UIColor.systemGroupedBackground
    
    /// 分隔线颜色
    static let talkSeparator = UIColor.separator
    
    /// 文本主色
    static let talkTextPrimary = UIColor.label
    
    /// 文本次要色
    static let talkTextSecondary = UIColor.secondaryLabel
    
    /// 气泡颜色 - 自己发送
    static let talkBubbleSent = UIColor.systemBlue
    
    /// 气泡颜色 - 接收
    static let talkBubbleReceived = UIColor.systemGray5
    
    /// 便利初始化方法（十六进制颜色）
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if hexString.hasPrefix("#") {
            hexString.remove(at: hexString.startIndex)
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)
        
        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}


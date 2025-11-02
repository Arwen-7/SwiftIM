//
//  MessageCell.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit

/// 消息 Cell
class MessageCell: UITableViewCell {
    
    static let identifier = "MessageCell"
    
    // MARK: - UI Components
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .talkTextSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 约束引用，用于切换左右布局
    private var avatarLeadingConstraint: NSLayoutConstraint!
    private var avatarTrailingConstraint: NSLayoutConstraint!
    private var bubbleLeadingConstraint: NSLayoutConstraint!
    private var bubbleTrailingConstraint: NSLayoutConstraint!
    private var timeLabelLeadingConstraint: NSLayoutConstraint!
    private var timeLabelTrailingConstraint: NSLayoutConstraint!
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.addSubview(avatarImageView)
        contentView.addSubview(bubbleView)
        contentView.addSubview(timeLabel)
        bubbleView.addSubview(messageLabel)
        
        // 头像约束
        avatarLeadingConstraint = avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        avatarTrailingConstraint = avatarImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        
        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // 气泡约束
        bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8)
        bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8)
        
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 250),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        
        // 消息文本约束
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
        
        // 时间标签约束
        timeLabelLeadingConstraint = timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        timeLabelTrailingConstraint = timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        
        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(message: String, isSent: Bool, time: String) {
        messageLabel.text = message
        timeLabel.text = time
        
        // 更新布局和样式
        if isSent {
            // 发送的消息（右侧）
            avatarLeadingConstraint.isActive = false
            avatarTrailingConstraint.isActive = true
            
            bubbleLeadingConstraint.isActive = false
            bubbleTrailingConstraint.isActive = true
            
            timeLabelLeadingConstraint.isActive = false
            timeLabelTrailingConstraint.isActive = true
            
            bubbleView.backgroundColor = .talkBubbleSent
            messageLabel.textColor = .white
            
            // 头像
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .systemBlue
        } else {
            // 接收的消息（左侧）
            avatarLeadingConstraint.isActive = true
            avatarTrailingConstraint.isActive = false
            
            bubbleLeadingConstraint.isActive = true
            bubbleTrailingConstraint.isActive = false
            
            timeLabelLeadingConstraint.isActive = true
            timeLabelTrailingConstraint.isActive = false
            
            bubbleView.backgroundColor = .talkBubbleReceived
            messageLabel.textColor = .talkTextPrimary
            
            // 头像
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .systemGray3
        }
    }
}


//
//  ChatViewController.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit
import SwiftIM

/// 聊天页
class ChatViewController: UIViewController {
    
    // MARK: - Properties
    
    private let conversationID: String
    private let targetUserID: String
    private var messages: [IMMessage] = []
    
    // MARK: - UI Components
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.delegate = self
        table.dataSource = self
        table.register(MessageCell.self, forCellReuseIdentifier: MessageCell.identifier)
        table.separatorStyle = .none
        table.backgroundColor = .talkBackground
        table.keyboardDismissMode = .interactive
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private lazy var inputContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var inputTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.cornerRadius = 18
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        return textView
    }()
    
    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("发送", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private var inputContainerBottomConstraint: NSLayoutConstraint!
    
    // MARK: - Initialization
    
    init(conversationID: String, targetUserID: String) {
        self.conversationID = conversationID
        self.targetUserID = targetUserID
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupSDK()
        loadMessages()
        setupKeyboardObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 进入聊天页面时，清零未读数
        markMessagesAsRead()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 离开聊天页面时，再次清零未读数（确保已读）
        markMessagesAsRead()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        IMClient.shared.removeMessageListener(self)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .talkBackground
        
        view.addSubview(tableView)
        view.addSubview(inputContainerView)
        
        inputContainerView.addSubview(inputTextView)
        inputContainerView.addSubview(sendButton)
        
        inputContainerBottomConstraint = inputContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            // TableView
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor),
            
            // 输入容器
            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerBottomConstraint,
            inputContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            // 输入框
            inputTextView.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 8),
            inputTextView.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 12),
            inputTextView.bottomAnchor.constraint(equalTo: inputContainerView.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            inputTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 100),
            
            // 发送按钮
            sendButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: inputTextView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    private func setupNavigationBar() {
        title = targetUserID
        
        // 加载用户信息并更新标题
        IMClient.shared.userManager?.getUserInfo(userID: targetUserID, forceUpdate: false) { [weak self] result in
            if case .success(let user) = result {
                DispatchQueue.main.async {
                    self?.title = user.nickname.isEmpty ? user.userID : user.nickname
                }
            }
        }
    }
    
    private func setupSDK() {
        // 添加消息监听器
        IMClient.shared.addMessageListener(self)
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // MARK: - Data Loading
    
    private func loadMessages() {
        guard IMClient.shared.isLoggedIn else { return }
        
        // 从 SDK 加载消息
        let msgs = IMClient.shared.messageManager?.getMessages(
            conversationID: conversationID,
            limit: 50
        ) ?? []
        
        self.messages = msgs.reversed() // 最新的消息在底部
        self.tableView.reloadData()
        
        // 使用 performBatchUpdates 确保在布局完成后滚动
        self.tableView.performBatchUpdates(nil) { [weak self] _ in
            self?.scrollToBottom(animated: false)
        }
        
    }
    
    private func markMessagesAsRead() {
        // 标记会话为已读
        do {
            try IMClient.shared.conversationManager?.markAsRead(conversationID: conversationID)
        } catch {
            print("标记已读失败: \(error)")
        }
    }
    
    // MARK: - Actions
    
    @objc private func sendButtonTapped() {
        guard let text = inputTextView.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        sendMessage(text: text)
    }
    
    private func sendMessage(text: String) {
        guard IMClient.shared.isConnected else {
            showAlert(title: "提示", message: "网络未连接，请稍后再试")
            return
        }
        
        // 清空输入框
        inputTextView.text = ""
        sendButton.isEnabled = false
        
        // 创建并发送消息
        guard let messageManager = IMClient.shared.messageManager else { return }
        let message = messageManager.createTextMessage(
            content: text,
            to: targetUserID,
            conversationType: .single
        )
        
        do {
            _ = try messageManager.sendMessage(message)
            print("消息已提交到发送队列: clientMsgID=\(message.clientMsgID)")
        } catch {
            DispatchQueue.main.async { [weak self] in
                print("消息发送失败: \(error)")
                self?.showAlert(title: "发送失败", message: error.localizedDescription)
            }
        }
    }
    
    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty, tableView.numberOfRows(inSection: 0) > 0 else { return }
        
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Keyboard
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }
        
        inputContainerBottomConstraint.constant = -keyboardFrame.height
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
        
        scrollToBottom(animated: true)
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }
        
        inputContainerBottomConstraint.constant = 0
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MessageCell.identifier,
            for: indexPath
        ) as? MessageCell else {
            return UITableViewCell()
        }
        
        let message = messages[indexPath.row]
        let isSent = message.direction == .send
        
        // 格式化时间
        let date = Date.fromTimestamp(message.sendTime)
        let timeString = date.smartTimeString()
        
        cell.configure(message: message.content, isSent: isSent, time: timeString)
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        view.endEditing(true)
    }
}

// MARK: - UITextViewDelegate

extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
    }
}

// MARK: - IMMessageListener

extension ChatViewController: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        // 只处理当前会话的消息
        guard message.conversationID == conversationID else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 检查是否已存在（避免重复，只比较 clientMsgID）
            if !self.messages.contains(where: { $0.clientMsgID == message.clientMsgID }) {
                // 添加新消息
                self.messages.append(message)
                
                let indexPath = IndexPath(row: self.messages.count - 1, section: 0)
                self.tableView.insertRows(at: [indexPath], with: .none)
                self.scrollToBottom(animated: true)
                
                // 标记为已读
                self.markMessagesAsRead()
            }
        }
    }
    
    func onMessageStatusChanged(_ message: IMMessage) {
        // 消息状态改变（发送中、已发送、已送达等）
        guard message.conversationID == conversationID else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 查找并更新消息（只使用 clientMsgID 匹配）
            if let index = self.messages.firstIndex(where: { $0.clientMsgID == message.clientMsgID }) {
                self.messages[index] = message
                let indexPath = IndexPath(row: index, section: 0)
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
            
            // 如果发送失败，显示提示
            if message.status == .failed {
                print("消息发送失败: clientMsgID=\(message.clientMsgID)")
                // 可以在这里更新 UI 显示发送失败状态
            }
        }
    }
    
    func onMessageRevoked(message: IMMessage) {
        // 消息被撤回
        guard message.conversationID == conversationID else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 查找消息（只使用 clientMsgID 匹配）
            if let index = self.messages.firstIndex(where: { $0.clientMsgID == message.clientMsgID }) {
                self.messages[index] = message
                
                let indexPath = IndexPath(row: index, section: 0)
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        }
    }
}


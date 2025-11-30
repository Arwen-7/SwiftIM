//
//  ConversationListViewController.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit
import SwiftIM

/// 对话列表页
class ConversationListViewController: UIViewController {
    
    // MARK: - Properties
    
    private var conversations: [IMConversation] = []
    
    // MARK: - UI Components
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.delegate = self
        table.dataSource = self
        table.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.identifier)
        table.rowHeight = 74
        table.separatorInset = UIEdgeInsets(top: 0, left: 77, bottom: 0, right: 0)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private lazy var emptyView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let imageView = UIImageView(image: UIImage(systemName: "message"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = "暂无对话"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(imageView)
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        return view
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupSDK()
        loadConversations()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        view.addSubview(emptyView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyView.widthAnchor.constraint(equalToConstant: 200),
            emptyView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func setupNavigationBar() {
        title = "消息"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        // 添加新建对话按钮（支持单聊和群聊）
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .compose,
            target: self,
            action: #selector(addConversationTapped)
        )
        
        // 添加设置按钮
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        
        navigationItem.rightBarButtonItems = [addButton, settingsButton]
    }
    
    private func setupSDK() {
        // 添加会话监听器
        IMClient.shared.addConversationListener(self)
        
        // 添加消息监听器（用于更新会话列表）
        IMClient.shared.addMessageListener(self)
        
        // 检查登录状态
        if !IMClient.shared.isLoggedIn {
            // 未登录，跳转到设置页面
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsTapped()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadConversations() {
        guard IMClient.shared.isLoggedIn else {
            updateEmptyView()
            return
        }
        
        // 从 SDK 加载对话列表
        let convs = IMClient.shared.conversationManager?.getAllConversations() ?? []
        
        DispatchQueue.main.async { [weak self] in
            self?.conversations = convs
            self?.tableView.reloadData()
            self?.updateEmptyView()
        }
    }
    
    private func updateEmptyView() {
        emptyView.isHidden = !conversations.isEmpty
        tableView.isHidden = conversations.isEmpty
    }
    
    // MARK: - Actions
    
    @objc private func addConversationTapped() {
        let alert = UIAlertController(
            title: "新建对话",
            message: "请选择对话类型",
            preferredStyle: .actionSheet
        )
        
        // 发起单聊
        alert.addAction(UIAlertAction(title: "发起单聊", style: .default) { [weak self] _ in
            self?.showCreateSingleChat()
        })
        
        // 创建群聊
        alert.addAction(UIAlertAction(title: "创建群聊", style: .default) { [weak self] _ in
            self?.showCreateGroup()
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showCreateSingleChat() {
        let alert = UIAlertController(
            title: "发起单聊",
            message: "请输入对方用户 ID",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "用户 ID"
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let userID = alert?.textFields?.first?.text, !userID.isEmpty else { return }
            self?.createConversation(with: userID)
        })
        
        present(alert, animated: true)
    }
    
    private func showCreateGroup() {
        let createVC = CreateGroupViewController()
        createVC.delegate = self
        let nav = UINavigationController(rootViewController: createVC)
        present(nav, animated: true)
    }
    
    @objc private func settingsTapped() {
        let settingsVC = SettingsViewController()
        settingsVC.onLogout = { [weak self] in
            self?.conversations.removeAll()
            self?.tableView.reloadData()
            self?.updateEmptyView()
        }
        settingsVC.onLogin = { [weak self] in
            self?.loadConversations()
        }
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    private func createConversation(with userID: String) {
        guard let currentUserID = IMClient.shared.getCurrentUserID() else { return }
        
        // 创建会话 ID（使用 SDK 的标准格式：single_userID1_userID2）
        let sortedIDs = [currentUserID, userID].sorted()
        let conversationID = "single_\(sortedIDs[0])_\(sortedIDs[1])"
        
        // 跳转到聊天页面
        let chatVC = ChatViewController(
            conversationID: conversationID,
            conversationType: .single,
            targetID: userID
        )
        navigationController?.pushViewController(chatVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ConversationListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ConversationCell.identifier,
            for: indexPath
        ) as? ConversationCell else {
            return UITableViewCell()
        }
        
        let conversation = conversations[indexPath.row]
        
        // 获取最后一条消息
        let lastMessage = conversation.lastMessage
        let messageText = lastMessage?.content ?? "暂无消息"
        
        // 格式化时间
        let timeString: String
        if conversation.latestMsgSendTime > 0 {
            let date = Date.fromTimestamp(conversation.latestMsgSendTime)
            timeString = date.smartTimeString()
        } else {
            timeString = ""
        }
        
        cell.configure(
            name: conversation.showName.isEmpty ? conversation.conversationID : conversation.showName,
            message: messageText,
            time: timeString,
            unreadCount: conversation.unreadCount,
            avatarURL: conversation.faceURL,
            conversationType: conversation.conversationType
        )
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ConversationListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let conversation = conversations[indexPath.row]
        
        // 根据会话类型确定 targetID
        let targetID: String
        if conversation.conversationType == .single {
            targetID = conversation.userID
        } else if conversation.conversationType == .group {
            targetID = conversation.groupID
        } else {
            targetID = conversation.userID
        }
        
        // 跳转到聊天页面
        let chatVC = ChatViewController(
            conversationID: conversation.conversationID,
            conversationType: conversation.conversationType,
            targetID: targetID
        )
        chatVC.title = conversation.showName.isEmpty ? conversation.conversationID : conversation.showName
        
        navigationController?.pushViewController(chatVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.deleteConversation(at: indexPath)
            completion(true)
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    private func deleteConversation(at indexPath: IndexPath) {
        let conversation = conversations[indexPath.row]
        
        IMClient.shared.conversationManager?.deleteConversation(conversationID: conversation.conversationID) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.conversations.remove(at: indexPath.row)
                    self?.tableView.deleteRows(at: [indexPath], with: .fade)
                    self?.updateEmptyView()
                    
                case .failure(let error):
                    print("删除对话失败: \(error)")
                }
            }
        }
    }
}

// MARK: - IMConversationListener

extension ConversationListViewController: IMConversationListener {
    func onConversationCreated(_ conversation: IMConversation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 检查是否已存在
            if !self.conversations.contains(where: { $0.conversationID == conversation.conversationID }) {
                self.conversations.insert(conversation, at: 0)
                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                self.updateEmptyView()
            }
        }
    }
    
    func onConversationUpdated(_ conversation: IMConversation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let index = self.conversations.firstIndex(where: { $0.conversationID == conversation.conversationID }) {
                self.conversations[index] = conversation
                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }
    }
    
    func onConversationDeleted(_ conversationID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let index = self.conversations.firstIndex(where: { $0.conversationID == conversationID }) {
                self.conversations.remove(at: index)
                self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                self.updateEmptyView()
            }
        }
    }
    
    func onTotalUnreadCountChanged(_ count: Int) {
        // 可以在这里更新 TabBar 的角标
        DispatchQueue.main.async { [weak self] in
            self?.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
        }
    }
}

// MARK: - CreateGroupDelegate

extension ConversationListViewController: CreateGroupDelegate {
    func didCreateGroup(_ group: IMGroup) {
        // 群组创建成功后，直接进入群聊界面
        let conversationID = "group_\(group.groupID)"
        let chatVC = ChatViewController(
            conversationID: conversationID,
            conversationType: .group,
            targetID: group.groupID
        )
        chatVC.title = group.groupName
        navigationController?.pushViewController(chatVC, animated: true)
    }
}

// MARK: - IMMessageListener

extension ConversationListViewController: IMMessageListener {
    func onMessageReceived(_ message: IMMessage) {
        // 收到新消息时重新加载对话列表
        loadConversations()
    }
    
    func onMessageReadReceiptReceived(conversationID: String, messageIDs: [String]) {
        // 处理已读回执，重新加载对话列表
        loadConversations()
    }
}


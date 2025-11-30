import UIKit
import SwiftIM

/// 群成员列表界面
class GroupMemberListViewController: UITableViewController {
    
    // MARK: - Properties
    
    private let group: IMGroup
    private var members: [IMUser] = []
    
    // MARK: - Initialization
    
    init(group: IMGroup) {
        self.group = group
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "群成员 (\(group.memberCount))"
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MemberCell")
        
        loadMembers()
    }
    
    // MARK: - Data Loading
    
    private func loadMembers() {
        // TODO: 从 IMClient 获取群成员列表
        members = []
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return members.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MemberCell", for: indexPath)
        let member = members[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = member.nickname
        content.secondaryText = member.userID
        
        // 设置头像
        if !member.avatar.isEmpty, let url = URL(string: member.avatar) {
            // TODO: 加载网络图片
            content.image = UIImage(systemName: "person.circle.fill")
        } else {
            content.image = UIImage(systemName: "person.circle.fill")
        }
        
        // 标记群主
        if member.userID == group.ownerUserID {
            content.secondaryText = "群主"
        }
        
        cell.contentConfiguration = content
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let member = members[indexPath.row]
        
        // 显示成员信息或操作
        showMemberActions(member)
    }
    
    private func showMemberActions(_ member: IMUser) {
        let alert = UIAlertController(title: member.nickname, message: nil, preferredStyle: .actionSheet)
        
        // 发送消息
        alert.addAction(UIAlertAction(title: "发送消息", style: .default) { [weak self] _ in
            self?.sendMessage(to: member)
        })
        
        // 如果是群主，可以踢人
        if let currentUserID = IMClient.shared.currentUser?.userID,
           currentUserID == group.ownerUserID,
           member.userID != group.ownerUserID {
            alert.addAction(UIAlertAction(title: "移出群组", style: .destructive) { [weak self] _ in
                self?.kickMember(member)
            })
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func sendMessage(to member: IMUser) {
        // 进入单聊界面
        let currentUserID = IMClient.shared.currentUser?.userID ?? ""
        let userIDs = [currentUserID, member.userID].sorted()
        let conversationID = "single_\(userIDs[0])_\(userIDs[1])"
        
        let chatVC = ChatViewController(
            conversationID: conversationID,
            conversationType: .single,
            targetID: member.userID
        )
        chatVC.title = member.nickname
        navigationController?.pushViewController(chatVC, animated: true)
    }
    
    private func kickMember(_ member: IMUser) {
        let alert = UIAlertController(
            title: "移出群组",
            message: "确定要将 \(member.nickname) 移出群组吗？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            IMClient.shared.groupManager?.kickMembers(
                groupID: self.group.groupID,
                userIDs: [member.userID]
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.loadMembers()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "错误",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
}


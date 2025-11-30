import UIKit
import SwiftIM

/// 群组详情界面
class GroupDetailViewController: UITableViewController {
    
    // MARK: - Properties
    
    private var group: IMGroup
    private var members: [IMUser] = []
    
    private enum Section: Int, CaseIterable {
        case info = 0
        case members
        case actions
    }
    
    // MARK: - Initialization
    
    init(group: IMGroup) {
        self.group = group
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "群组详情"
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        
        switch section {
        case .info:
            return 3 // 群名称、群简介、群成员数
        case .members:
            return min(members.count + 1, 10) // 最多显示9个成员 + "查看全部"
        case .actions:
            return 2 // 邀请、退出
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .info:
            return infoCell(for: indexPath)
        case .members:
            return memberCell(for: indexPath)
        case .actions:
            return actionCell(for: indexPath)
        }
    }
    
    private func infoCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        
        switch indexPath.row {
        case 0:
            content.text = "群名称"
            content.secondaryText = group.groupName
        case 1:
            content.text = "群简介"
            content.secondaryText = group.introduction.isEmpty ? "无" : group.introduction
        case 2:
            content.text = "群成员"
            content.secondaryText = "\(group.memberCount) 人"
        default:
            break
        }
        
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        
        return cell
    }
    
    private func memberCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MemberCell", for: indexPath)
        
        if indexPath.row < members.count {
            let member = members[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = member.nickname
            content.image = UIImage(systemName: "person.circle.fill")
            cell.contentConfiguration = content
            cell.selectionStyle = .none
        } else {
            var content = cell.defaultContentConfiguration()
            content.text = "查看全部成员"
            content.textProperties.color = .systemBlue
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        }
        
        return cell
    }
    
    private func actionCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        
        switch indexPath.row {
        case 0:
            content.text = "邀请成员"
            content.textProperties.color = .systemBlue
        case 1:
            content.text = "退出群组"
            content.textProperties.color = .systemRed
        default:
            break
        }
        
        cell.contentConfiguration = content
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        
        switch section {
        case .info:
            return "群组信息"
        case .members:
            return "群成员"
        case .actions:
            return nil
        }
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .info:
            break
            
        case .members:
            if indexPath.row >= members.count {
                // 查看全部成员
                showAllMembers()
            }
            
        case .actions:
            if indexPath.row == 0 {
                // 邀请成员
                inviteMembers()
            } else {
                // 退出群组
                leaveGroup()
            }
        }
    }
    
    // MARK: - Actions
    
    private func showAllMembers() {
        let memberListVC = GroupMemberListViewController(group: group)
        navigationController?.pushViewController(memberListVC, animated: true)
    }
    
    private func inviteMembers() {
        // TODO: 实现邀请成员界面
        let alert = UIAlertController(
            title: "邀请成员",
            message: "此功能待实现",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    private func leaveGroup() {
        let alert = UIAlertController(
            title: "退出群组",
            message: "确定要退出 \(group.groupName) 吗？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            IMClient.shared.groupManager?.leaveGroup(groupID: self.group.groupID) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.navigationController?.popViewController(animated: true)
                        
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


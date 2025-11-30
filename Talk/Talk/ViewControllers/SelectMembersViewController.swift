//
//  SelectMembersViewController.swift
//  Talk
//
//  成员选择界面
//

import UIKit
import SwiftIM

protocol SelectMembersDelegate: AnyObject {
    func didSelectMembers(_ userIDs: [String])
}

/// 成员选择界面
class SelectMembersViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: SelectMembersDelegate?
    private var selectedUserIDs: Set<String> = []
    private var availableUsers: [(userID: String, nickname: String)] = []
    
    // MARK: - UI Components
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MemberCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private lazy var doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("确定", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "选择成员"
        view.backgroundColor = .systemBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        setupUI()
        loadUsers()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(tableView)
        view.addSubview(doneButton)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -20),
            
            doneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadUsers() {
        // 简单实现：硬编码一些用户
        // TODO: 从服务端获取好友列表或所有用户
        availableUsers = [
            ("1764496358586000", "Alice"),
            ("1764496360670000", "Bob")
        ]
        
        // 排除当前用户
        if let currentUserID = IMClient.shared.currentUserID {
            availableUsers.removeAll { $0.userID == currentUserID }
        }
        
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneButtonTapped() {
        delegate?.didSelectMembers(Array(selectedUserIDs))
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SelectMembersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableUsers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MemberCell", for: indexPath)
        let user = availableUsers[indexPath.row]
        
        cell.textLabel?.text = user.nickname
        cell.accessoryType = selectedUserIDs.contains(user.userID) ? .checkmark : .none
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SelectMembersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let user = availableUsers[indexPath.row]
        
        if selectedUserIDs.contains(user.userID) {
            selectedUserIDs.remove(user.userID)
        } else {
            selectedUserIDs.insert(user.userID)
        }
        
        tableView.reloadRows(at: [indexPath], with: .automatic)
        
        // 更新按钮文字
        if selectedUserIDs.isEmpty {
            doneButton.setTitle("确定", for: .normal)
        } else {
            doneButton.setTitle("确定（已选 \(selectedUserIDs.count) 人）", for: .normal)
        }
    }
}


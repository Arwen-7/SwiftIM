import UIKit
import SwiftIM

/// 创建群组回调协议
protocol CreateGroupDelegate: AnyObject {
    func didCreateGroup(_ group: IMGroup)
}

/// 创建群组界面
class CreateGroupViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: CreateGroupDelegate?
    private var selectedMemberIDs: [String] = []
    
    private lazy var groupNameTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "群组名称"
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()
    
    private lazy var introductionTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var selectMembersButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("选择成员", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.backgroundColor = .systemGray6
        button.setTitleColor(.systemBlue, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(selectMembersTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var selectedMembersLabel: UILabel = {
        let label = UILabel()
        label.text = "未选择成员"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var createButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("创建群组", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(createGroupTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "创建群组"
        view.backgroundColor = .systemBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        setupUI()
        
        // 键盘处理
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        // 点击空白处收起键盘
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(groupNameTextField)
        view.addSubview(introductionTextView)
        view.addSubview(selectMembersButton)
        view.addSubview(selectedMembersLabel)
        view.addSubview(createButton)
        
        let introLabel = UILabel()
        introLabel.text = "群组简介"
        introLabel.font = .systemFont(ofSize: 14)
        introLabel.textColor = .secondaryLabel
        introLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(introLabel)
        
        let membersLabel = UILabel()
        membersLabel.text = "群成员"
        membersLabel.font = .systemFont(ofSize: 14)
        membersLabel.textColor = .secondaryLabel
        membersLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(membersLabel)
        
        NSLayoutConstraint.activate([
            // 群组名称
            groupNameTextField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            groupNameTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            groupNameTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            groupNameTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // 简介标签
            introLabel.topAnchor.constraint(equalTo: groupNameTextField.bottomAnchor, constant: 20),
            introLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            // 简介输入框
            introductionTextView.topAnchor.constraint(equalTo: introLabel.bottomAnchor, constant: 8),
            introductionTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            introductionTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            introductionTextView.heightAnchor.constraint(equalToConstant: 100),
            
            // 成员标签
            membersLabel.topAnchor.constraint(equalTo: introductionTextView.bottomAnchor, constant: 20),
            membersLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            // 选择成员按钮
            selectMembersButton.topAnchor.constraint(equalTo: membersLabel.bottomAnchor, constant: 8),
            selectMembersButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            selectMembersButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            selectMembersButton.heightAnchor.constraint(equalToConstant: 44),
            
            // 已选成员标签
            selectedMembersLabel.topAnchor.constraint(equalTo: selectMembersButton.bottomAnchor, constant: 8),
            selectedMembersLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            selectedMembersLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // 创建按钮
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            createButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            createButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func selectMembersTapped() {
        let selectVC = SelectMembersViewController()
        selectVC.delegate = self
        let nav = UINavigationController(rootViewController: selectVC)
        present(nav, animated: true)
    }
    
    @objc private func createGroupTapped() {
        guard let groupName = groupNameTextField.text, !groupName.isEmpty else {
            showAlert(message: "请输入群组名称")
            return
        }
        
        let introduction = introductionTextView.text ?? ""
        
        // 显示加载
        createButton.isEnabled = false
        createButton.setTitle("创建中...", for: .normal)
        
        // 创建群组（包含选中的成员）
        IMClient.shared.groupManager?.createGroup(
            groupName: groupName,
            faceURL: "",
            introduction: introduction,
            memberUserIDs: selectedMemberIDs
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.createButton.isEnabled = true
                self?.createButton.setTitle("创建群组", for: .normal)
                
                switch result {
                case .success(let group):
                    self?.delegate?.didCreateGroup(group)
                    self?.dismiss(animated: true)
                    
                case .failure(let error):
                    self?.showAlert(message: "创建失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        UIView.animate(withDuration: 0.3) {
            self.view.frame.origin.y = -keyboardHeight / 2
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.view.frame.origin.y = 0
        }
    }
    
    // MARK: - Helper
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - SelectMembersDelegate

extension CreateGroupViewController: SelectMembersDelegate {
    func didSelectMembers(_ userIDs: [String]) {
        selectedMemberIDs = userIDs
        
        if userIDs.isEmpty {
            selectedMembersLabel.text = "未选择成员"
        } else {
            selectedMembersLabel.text = "已选择 \(userIDs.count) 名成员"
        }
    }
}


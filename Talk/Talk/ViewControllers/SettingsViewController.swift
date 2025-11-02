//
//  SettingsViewController.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit
import SwiftIM

/// 设置页
class SettingsViewController: UIViewController {
    
    // MARK: - Properties
    
    var onLogout: (() -> Void)?
    var onLogin: (() -> Void)?
    
    // MARK: - UI Components
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .talkTextSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var userIDTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "用户 ID"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var tokenTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Token（可选）"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var serverURLTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "IM 服务器地址"
        textField.borderStyle = .roundedRect
        textField.text = TalkConfig.imServerURL
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var loginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("登录", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.backgroundColor = .talkPrimary
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var logoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("登出", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var infoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .talkTextSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "提示：\n1. 用户 ID 可以是任意字符串\n2. Token 可以留空（演示模式）\n3. 确保 IM 服务器已启动"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        updateUI()
        
        // 添加连接状态监听
        IMClient.shared.addConnectionListener(self)
    }
    
    deinit {
        IMClient.shared.removeConnectionListener(self)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(statusLabel)
        contentView.addSubview(userIDTextField)
        contentView.addSubview(tokenTextField)
        contentView.addSubview(serverURLTextField)
        contentView.addSubview(loginButton)
        contentView.addSubview(logoutButton)
        contentView.addSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            userIDTextField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 30),
            userIDTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            userIDTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            userIDTextField.heightAnchor.constraint(equalToConstant: 44),
            
            tokenTextField.topAnchor.constraint(equalTo: userIDTextField.bottomAnchor, constant: 15),
            tokenTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            tokenTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tokenTextField.heightAnchor.constraint(equalToConstant: 44),
            
            serverURLTextField.topAnchor.constraint(equalTo: tokenTextField.bottomAnchor, constant: 15),
            serverURLTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            serverURLTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            serverURLTextField.heightAnchor.constraint(equalToConstant: 44),
            
            loginButton.topAnchor.constraint(equalTo: serverURLTextField.bottomAnchor, constant: 30),
            loginButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            
            logoutButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 15),
            logoutButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            logoutButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            logoutButton.heightAnchor.constraint(equalToConstant: 50),
            
            infoLabel.topAnchor.constraint(equalTo: logoutButton.bottomAnchor, constant: 30),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            infoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -30)
        ])
        
        // 添加点击手势关闭键盘
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupNavigationBar() {
        title = "设置"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }
    
    private func updateUI() {
        let isLoggedIn = IMClient.shared.isLoggedIn
        let isConnected = IMClient.shared.isConnected
        
        // 更新状态标签
        if isLoggedIn {
            let userID = IMClient.shared.getCurrentUserID() ?? "Unknown"
            let connectionStatus = isConnected ? "已连接" : "未连接"
            statusLabel.text = "当前用户: \(userID)\n状态: \(connectionStatus)"
            statusLabel.textColor = isConnected ? .systemGreen : .systemOrange
        } else {
            statusLabel.text = "未登录"
            statusLabel.textColor = .talkTextSecondary
        }
        
        // 更新按钮状态
        loginButton.isHidden = isLoggedIn
        logoutButton.isHidden = !isLoggedIn
        userIDTextField.isEnabled = !isLoggedIn
        tokenTextField.isEnabled = !isLoggedIn
        serverURLTextField.isEnabled = !isLoggedIn
        
        // 读取保存的用户信息
        if let savedUserID = UserDefaults.standard.string(forKey: UserDefaults_Keys.currentUserID) {
            userIDTextField.text = savedUserID
        }
        if let savedToken = UserDefaults.standard.string(forKey: UserDefaults_Keys.currentUserToken) {
            tokenTextField.text = savedToken
        }
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func loginButtonTapped() {
        guard let userID = userIDTextField.text, !userID.isEmpty else {
            showAlert(title: "提示", message: "请输入用户 ID")
            return
        }
        
        let token = tokenTextField.text?.isEmpty == false ? tokenTextField.text! : "demo_token_\(userID)"
        let serverURL = serverURLTextField.text?.isEmpty == false ? serverURLTextField.text! : TalkConfig.imServerURL
        
        // 显示加载指示器
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        loginButton.isEnabled = false
        
        // 更新配置（如果服务器地址变了）
        if serverURL != TalkConfig.imServerURL {
            // 重新初始化 SDK
            do {
                let config = IMConfig(
                    apiURL: TalkConfig.apiServerURL,
                    imURL: serverURL
                )
                try IMClient.shared.initialize(config: config)
            } catch {
                showAlert(title: "错误", message: "SDK 初始化失败: \(error.localizedDescription)")
                navigationItem.rightBarButtonItem = nil
                loginButton.isEnabled = true
                return
            }
        }
        
        // 登录
        IMClient.shared.login(userID: userID, token: token) { [weak self] result in
            DispatchQueue.main.async {
                self?.navigationItem.rightBarButtonItem = nil
                self?.loginButton.isEnabled = true
                
                switch result {
                case .success:
                    // 保存登录信息
                    UserDefaults.standard.set(userID, forKey: UserDefaults_Keys.currentUserID)
                    UserDefaults.standard.set(token, forKey: UserDefaults_Keys.currentUserToken)
                    UserDefaults.standard.set(true, forKey: UserDefaults_Keys.isLoggedIn)
                    
                    self?.updateUI()
                    self?.onLogin?()
                    self?.showAlert(title: "成功", message: "登录成功") {
                        self?.dismiss(animated: true)
                    }
                    
                case .failure(let error):
                    self?.showAlert(title: "登录失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func logoutButtonTapped() {
        let alert = UIAlertController(
            title: "确认登出",
            message: "登出后将清除本地数据",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        
        present(alert, animated: true)
    }
    
    private func performLogout() {
        IMClient.shared.logout { [weak self] result in
            DispatchQueue.main.async {
                // 清除保存的信息
                UserDefaults.standard.removeObject(forKey: UserDefaults_Keys.currentUserID)
                UserDefaults.standard.removeObject(forKey: UserDefaults_Keys.currentUserToken)
                UserDefaults.standard.set(false, forKey: UserDefaults_Keys.isLoggedIn)
                
                self?.updateUI()
                self?.onLogout?()
                
                switch result {
                case .success:
                    self?.showAlert(title: "成功", message: "已登出")
                    
                case .failure(let error):
                    self?.showAlert(title: "提示", message: "登出失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - IMConnectionListener

extension SettingsViewController: IMConnectionListener {
    func onConnectionStateChanged(_ state: IMConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    func onConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    func onDisconnected(error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
}


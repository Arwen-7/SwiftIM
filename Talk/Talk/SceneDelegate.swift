//
//  SceneDelegate.swift
//  Talk
//
//  Created by Arwen on 2025/11/2.
//

import UIKit
import SwiftIM

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // 初始化 SDK
        initializeSDK()
        
        // 创建窗口
        let window = UIWindow(windowScene: windowScene)
        
        // 创建根视图控制器
        let conversationListVC = ConversationListViewController()
        let navigationController = UINavigationController(rootViewController: conversationListVC)
        
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        
        self.window = window
    }
    
    private func initializeSDK() {
        // 配置 SDK
        let config = IMConfig(
            apiURL: TalkConfig.apiServerURL,
            imURL: TalkConfig.imServerURL
        )
        
        do {
            try IMClient.shared.initialize(config: config)
            print("✅ IM SDK 初始化成功")
            
            // 如果之前已登录，尝试自动登录
            if UserDefaults.standard.bool(forKey: UserDefaults_Keys.isLoggedIn),
               let userID = UserDefaults.standard.string(forKey: UserDefaults_Keys.currentUserID),
               let token = UserDefaults.standard.string(forKey: UserDefaults_Keys.currentUserToken) {
                
                IMClient.shared.login(userID: userID, token: token) { result in
                    switch result {
                    case .success:
                        print("✅ 自动登录成功")
                    case .failure(let error):
                        print("❌ 自动登录失败: \(error)")
                        // 清除登录状态
                        UserDefaults.standard.set(false, forKey: UserDefaults_Keys.isLoggedIn)
                    }
                }
            }
        } catch {
            print("❌ IM SDK 初始化失败: \(error)")
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}


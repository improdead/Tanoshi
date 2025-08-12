//
//  SceneDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            // Show onboarding for first-time users
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                let hosting = UIHostingController(rootView: OnboardingView { [weak self] in
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    // Swap to main interface once finished
                    if let strongWindow = self?.window {
                        self?.applyAppearance(to: strongWindow)
                        strongWindow.rootViewController = TabBarController()
                        strongWindow.makeKeyAndVisible()
                    }
                })
                window.rootViewController = hosting
            } else {
                window.rootViewController = TabBarController()
            }
            window.tintColor = .systemPink
            applyAppearance(to: window)

            self.window = window
            window.makeKeyAndVisible()
        }

        if let url = connectionOptions.urlContexts.first?.url,
           let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }

    let contentHideView: UIView = {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .systemBackground
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    func sceneWillEnterForeground(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        let incognitoEnabled = UserDefaults.standard.bool(forKey: "General.incognitoMode")
        if incognitoEnabled {
            (scene as? UIWindowScene)?.windows.first?.addSubview(contentHideView)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url, let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }
}

// MARK: - Appearance
private extension SceneDelegate {
    func applyAppearance(to window: UIWindow) {
        if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
            window.overrideUserInterfaceStyle = .unspecified
        } else {
            let appearance = UserDefaults.standard.integer(forKey: "General.appearance")
            window.overrideUserInterfaceStyle = (appearance == 0) ? .light : .dark
        }
    }
}

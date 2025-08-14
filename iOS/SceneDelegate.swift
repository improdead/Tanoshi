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
            // First-run onboarding
            if !UserDefaults.standard.bool(forKey: "Onboarding.didFinish") {
                let hosting = UIHostingController(rootView:
                    AnyView(
                        FirstRunOnboardingShimView(onFinish: {
                            UserDefaults.standard.set(true, forKey: "Onboarding.didFinish")
                            window.rootViewController = TabBarController()
                        })
                    )
                )
                window.rootViewController = hosting
            } else {
                window.rootViewController = TabBarController()
            }
            window.tintColor = .systemPink

            if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                window.overrideUserInterfaceStyle = .unspecified
            } else {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    window.overrideUserInterfaceStyle = .light
                } else {
                    window.overrideUserInterfaceStyle = .dark
                }
            }

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

// Inline lightweight onboarding to avoid project file edits
private struct FirstRunOnboardingShimView: View {
    let onFinish: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("WELCOME_TO_TANOSHI")).font(.largeTitle).bold()
            Text(NSLocalizedString("TANOSHI_ONBOARDING_WELCOME_BODY")).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            HStack(spacing: 16) {
                Image(systemName: "globe")
                Text(NSLocalizedString("ADD_SOURCES_BROWSE_AND_SAVE_FAVORITES"))
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Image(systemName: "book.pages")
                Text(NSLocalizedString("DELIGHTFUL_READER", comment: "Delightful Reader"))
            }
            .foregroundStyle(.secondary)
            Button(NSLocalizedString("GET_STARTED")) { onFinish() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

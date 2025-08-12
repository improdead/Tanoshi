//
//  Haptics.swift
//  Tanoshi
//
//  Simple, centralized haptic feedback helpers.
//

import UIKit

public enum Haptics {
    enum NotificationType {
        case success, warning, error
    }

    static func notify(_ type: NotificationType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        switch type {
            case .success: generator.notificationOccurred(.success)
            case .warning: generator.notificationOccurred(.warning)
            case .error: generator.notificationOccurred(.error)
        }
    }

    enum Impact { case light, medium, heavy, soft, rigid }

    static func impact(_ style: Impact) {
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            case .soft:
                if #available(iOS 13.0, *) { .soft } else { .light }
            case .rigid:
                if #available(iOS 13.0, *) { .rigid } else { .heavy }
        }
        let generator = UIImpactFeedbackGenerator(style: uiStyle)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}



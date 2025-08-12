//
//  EmptyStateView.swift
//  Tanoshi
//
//  A reusable empty/placeholder state with subtle motion and actions.
//

import SwiftUI
import UIKit

public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    @State private var animate = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 150, height: 150)
                    .scaleEffect(animate ? 1 : 0.96)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: animate)
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .scaleEffect(animate ? 1 : 0.985)
                    .animation(.spring(response: 0.8, dampingFraction: 0.9), value: animate)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 12) {
                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle) { UISelectionFeedbackGenerator().selectionChanged(); secondaryAction() }
                    }
                    if let primaryActionTitle, let primaryAction {
                        Button(primaryActionTitle) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); primaryAction() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .onAppear { animate = true }
    }
}



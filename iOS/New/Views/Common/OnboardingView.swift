//
//  OnboardingView.swift
//  Tanoshi
//
//  A welcoming, non-technical introduction that guides new users through
//  sources, browsing, reading, and privacy, with playful motion.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var pageIndex: Int = 0
    @State private var showContinueHint = false

    private let appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Tanoshi"

    struct Page: Identifiable, Equatable {
        let id = UUID()
        let symbol: String
        let title: String
        let message: String
        let accent: Color
    }

    private var pages: [Page] {
        [
            .init(
                symbol: "sparkles",
                title: "Welcome to \(appName)",
                message: "A clean, fast way to browse manga sources, track what you read, and enjoy a beautiful reader.",
                accent: .pink
            ),
            .init(
                symbol: "globe",
                title: "Add Sources",
                message: "Pick your favorite sources. You can change this anytime in Settings.",
                accent: .blue
            ),
            .init(
                symbol: "rectangle.grid.2x2",
                title: "Browse & Search",
                message: "Find new titles quickly. Use filters, search, and categories—no setup required.",
                accent: .purple
            ),
            .init(
                symbol: "book.pages",
                title: "Delightful Reader",
                message: "Smooth page turns, gestures, and an uncluttered layout. It just feels right.",
                accent: .green
            ),
            .init(
                symbol: "lock.shield",
                title: "Your Privacy",
                message: "You control what is saved. Incognito mode and history lock are one tap away.",
                accent: .teal
            )
        ]
    }

    var body: some View {
        ZStack {
            // Subtle animated gradient background
            AnimatedGradient()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 20)

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: pageIndex)

                Spacer()

                VStack(spacing: 12) {
                    if pageIndex < pages.count - 1 {
                        Button(action: goToNext) {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle(color: pages[pageIndex].accent))
                        .padding(.horizontal, 24)

                        Button(action: finish) {
                            Text("Skip for now")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 24)
                        .opacity(showContinueHint ? 1 : 0.8)
                    } else {
                        Button(action: finish) {
                            Text("Get Started")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle(color: pages[pageIndex].accent))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut.delay(0.8)) { showContinueHint = true }
        }
    }

    private func goToNext() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        withAnimation {
            pageIndex = min(pageIndex + 1, pages.count - 1)
        }
    }

    private func finish() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        onFinish()
    }
}

// MARK: - Components

private struct OnboardingPageView: View {
    let page: OnboardingView.Page
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.18))
                    .frame(width: 210, height: 210)
                    .scaleEffect(appear ? 1 : 0.9)
                    .blur(radius: 0.5)
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: appear)

                Image(systemName: page.symbol)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundColor(page.accent)
                    .scaleEffect(appear ? 1 : 0.92)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appear)
            }
            .padding(.bottom, 8)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .transition(.opacity)

            Text(page.message)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { appear = true }
        .onDisappear { appear = false }
        .padding(.vertical, 40)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: color.opacity(0.25), radius: 10, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.88), value: configuration.isPressed)
    }
}

// Animated soft gradient background
private struct AnimatedGradient: View {
    @State private var start = UnitPoint(x: 0, y: 0)
    @State private var end = UnitPoint(x: 1, y: 1)
    private let colors: [Color] = [
        .pink.opacity(0.20),
        .purple.opacity(0.18),
        .blue.opacity(0.18),
        .teal.opacity(0.18)
    ]
    var body: some View {
        LinearGradient(gradient: Gradient(colors: colors), startPoint: start, endPoint: end)
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    start = UnitPoint(x: 1, y: 0)
                    end = UnitPoint(x: 0, y: 1)
                }
            }
    }
}


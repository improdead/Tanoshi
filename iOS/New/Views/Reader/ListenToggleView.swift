import SwiftUI

// Compact icon-style listen toggle for the Reader toolbar.
// Appearance: a small capsule with an ear icon; filled when active.
// Tap toggles listening; optional tiny status dot indicates activity.
struct ListenToggleView: View {
    @ObservedObject private var vm: ReaderNarrationViewModel
    @State private var isOn: Bool = false
    @State private var showStatus: Bool = false

    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    // Internal initializer to avoid exposing internal types across module boundaries
    init(vm: ReaderNarrationViewModel? = nil, onStart: (() -> Void)? = nil, onStop: (() -> Void)? = nil) {
        self.vm = vm ?? ReaderNarrationViewModel()
        self.onStart = onStart
        self.onStop = onStop
    }

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Image(systemName: "ear")
                        .imageScale(.medium)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                }
                .foregroundColor(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color(UIColor.secondarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 1)
                )

                // Small status dot when there is any progress available
                if (vm.progress?.done ?? 0) > 0 {
                    Circle()
                        .fill(isOn ? Color.white.opacity(0.9) : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isOn ? "Listening On" : "Listening Off"))
        // Quick status on long press
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showStatus = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) { showStatus = false }
            }
        })
        .overlay(alignment: .top) {
            if showStatus {
                statusBubble
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .offset(y: -38)
            }
        }
        .onReceive(vm.$progress) { _ in
            // when user cancels remotely, reflect off state
            if vm.progress == nil { isOn = false }
        }
    }

    private func toggle() {
        isOn.toggle()
        if isOn {
            onStart?()
        } else {
            onStop?()
            vm.cancel()
        }
    }

    // MARK: - Status Bubble
    private var statusBubble: some View {
        let done = vm.progress?.done ?? vm.pages.filter { $0.state == .ready }.count
        let total = vm.progress?.total
        let anyReady = done > 0
        return HStack(spacing: 6) {
            Circle()
                .fill(anyReady ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)
            if let total {
                Text("\(done)/\(total) ready")
            } else {
                Text(anyReady ? "Ready" : "Waiting…")
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(UIColor.systemGray5))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 1)
        )
        .foregroundColor(.primary)
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

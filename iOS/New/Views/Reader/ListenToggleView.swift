import SwiftUI

// Minimal Listen toggle UI + status chips placeholder.
// Integration: place ListenToggleView inside your Reader UI toolbar/header where appropriate.

public struct ListenToggleView: View {
    @StateObject private var vm = ReaderNarrationViewModel()
    @State private var isOn: Bool = false

    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    public init(onStart: (() -> Void)? = nil, onStop: (() -> Void)? = nil) {
        self.onStart = onStart
        self.onStop = onStop
    }

    public var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                Text("Listen").font(.body)
            }
            .onChange(of: isOn) { newValue in
                if newValue {
                    // In production, the host screen should pass onStart to begin with real chapter/pages.
                    onStart?()
                } else {
                    onStop?()
                    vm.cancel()
                }
            }

            // Optional chip preview (ready count / total) when VM is used
            if let p = vm.progress {
                Text("\(p.done)/\(p.total)")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
        }
    }
}


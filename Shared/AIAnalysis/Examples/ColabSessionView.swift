//
//  ColabSessionView.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Session Management UI
//

import SwiftUI

struct ColabSessionView: View {
    @StateObject private var sessionManager = ColabSessionManager.shared
    @State private var newEndpointURL = ""
    @State private var showingURLInput = false
    @State private var isConnecting = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Session Status") {
                    HStack {
                        StatusIndicator(status: sessionManager.sessionStatus)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText)
                                .font(.headline)
                            if let endpoint = sessionManager.currentEndpoint {
                                Text(endpoint.absoluteString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
                
                if sessionManager.sessionStatus == .connected {
                    Section("Session Info") {
                        let info = sessionManager.getSessionInfo()
                        
                        if let uptime = info.formattedUptime {
                            HStack {
                                Text("Uptime")
                                Spacer()
                                Text(uptime)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let remaining = info.formattedRemainingTime {
                            HStack {
                                Text("Estimated Remaining")
                                Spacer()
                                Text(remaining)
                                    .foregroundColor(info.remainingTime ?? 0 < 3600 ? .orange : .secondary)
                            }
                        }
                        
                        if info.reconnectionAttempts > 0 {
                            HStack {
                                Text("Reconnection Attempts")
                                Spacer()
                                Text("\(info.reconnectionAttempts)")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Section("Actions") {
                    if sessionManager.sessionStatus == .disconnected || sessionManager.sessionStatus == .expired {
                        Button("Connect to New Session") {
                            showingURLInput = true
                        }
                        .disabled(isConnecting)
                    }
                    
                    if sessionManager.sessionStatus == .connected {
                        Button("Disconnect") {
                            sessionManager.endSession()
                        }
                        .foregroundColor(.red)
                    }
                    
                    if case .error = sessionManager.sessionStatus {
                        Button("Retry Connection") {
                            Task {
                                isConnecting = true
                                do {
                                    try await sessionManager.reconnectSession()
                                } catch {
                                    LogManager.logger.error("Manual reconnection failed: \(error)")
                                }
                                isConnecting = false
                            }
                        }
                        .disabled(isConnecting)
                    }
                }
                
                Section("Instructions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to set up Google Colab:")
                            .font(.headline)
                        
                        Text("1. Open Google Colab and create a new notebook")
                        Text("2. Copy and paste the setup code from the AI Analysis documentation")
                        Text("3. Run all cells to start the service")
                        Text("4. Copy the ngrok URL from the output")
                        Text("5. Paste the URL here to connect")
                        
                        Text("Note: Colab sessions expire after 12 hours or 90 minutes of inactivity.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Colab Session")
            .refreshable {
                // Refresh session status
                if sessionManager.sessionStatus == .connected {
                    do {
                        _ = try await ColabAPIClient.shared.healthCheck()
                    } catch {
                        LogManager.logger.error("Health check failed during refresh: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingURLInput) {
            URLInputView(
                currentURL: newEndpointURL,
                onSave: { url in
                    Task {
                        isConnecting = true
                        do {
                            guard let endpointURL = URL(string: url) else {
                                throw ColabSessionError.noEndpointConfigured
                            }
                            try await sessionManager.startSession(endpointURL: endpointURL)
                        } catch {
                            LogManager.logger.error("Failed to start session: \(error)")
                        }
                        isConnecting = false
                    }
                }
            )
        }
    }
    
    private var statusText: String {
        switch sessionManager.sessionStatus {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting..."
        case .expired:
            return "Session Expired"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct StatusIndicator: View {
    let status: ColabSessionManager.SessionStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 4)
                    .scaleEffect(animationScale)
                    .opacity(shouldAnimate ? 0.0 : 1.0)
                    .animation(
                        shouldAnimate ? .easeOut(duration: 1.0).repeatForever(autoreverses: false) : .none,
                        value: shouldAnimate
                    )
            )
    }
    
    private var statusColor: Color {
        switch status {
        case .disconnected:
            return .gray
        case .connecting, .reconnecting:
            return .orange
        case .connected:
            return .green
        case .expired:
            return .red
        case .error:
            return .red
        }
    }
    
    private var shouldAnimate: Bool {
        switch status {
        case .connecting, .reconnecting:
            return true
        default:
            return false
        }
    }
    
    private var animationScale: CGFloat {
        shouldAnimate ? 2.0 : 1.0
    }
}

struct URLInputView: View {
    @State var currentURL: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var isValidURL = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Colab Endpoint URL") {
                    TextField("https://xxxxx.ngrok.io", text: $currentURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onChange(of: currentURL) { _ in
                            validateURL()
                        }
                    
                    if !isValidURL {
                        Text("Please enter a valid URL")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Example URLs") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("https://abc123.ngrok.io")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("https://def456.ngrok-free.app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Instructions") {
                    Text("Copy the ngrok URL from your Google Colab notebook output. It should look like the examples above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Connect to Colab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Connect") {
                        onSave(currentURL)
                        dismiss()
                    }
                    .disabled(!isValidURL || currentURL.isEmpty)
                }
            }
        }
        .onAppear {
            validateURL()
        }
    }
    
    private func validateURL() {
        if currentURL.isEmpty {
            isValidURL = true
            return
        }
        
        isValidURL = URL(string: currentURL) != nil && 
                    (currentURL.hasPrefix("https://") || currentURL.hasPrefix("http://"))
    }
}

#Preview {
    ColabSessionView()
}
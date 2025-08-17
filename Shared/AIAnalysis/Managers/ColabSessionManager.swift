//
//  ColabSessionManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Session Management
//

import Foundation
import Combine

/// Manages Google Colab session lifecycle and automatic reconnection
actor ColabSessionManager {
    static let shared = ColabSessionManager()
    
    private let configManager = AIAnalysisConfigManager.shared
    private let apiClient = ColabAPIClient.shared
    
    // Session state
    // Plain stored properties; avoid @Published in actors
    private(set) var sessionStatus: SessionStatus = .disconnected
    private(set) var currentEndpoint: URL?
    private(set) var sessionStartTime: Date?
    private(set) var estimatedSessionExpiry: Date?
    
    // Health monitoring
    private var healthCheckTimer: Timer?
    private var reconnectionAttempts = 0
    private let maxReconnectionAttempts = 3
    
    // Session limits (Colab free tier)
    private let maxSessionDuration: TimeInterval = 12 * 60 * 60 // 12 hours
    private let idleTimeout: TimeInterval = 90 * 60 // 90 minutes
    
    private init() {}
    
    enum SessionStatus {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case expired
        case error(String)
    }
    
    // MARK: - Session Management
    
    func startSession(endpointURL: URL) async throws {
        sessionStatus = .connecting
        currentEndpoint = endpointURL
        
        // Update configuration
        var config = await configManager.colabConfiguration
        config = ColabConfiguration(
            endpointURL: endpointURL,
            apiKey: config.apiKey,
            timeout: config.timeout,
            maxRetries: config.maxRetries,
            batchSize: config.batchSize
        )
        await configManager.setColabConfiguration(config)
        
        do {
            // Test connection
            let healthResponse = try await apiClient.healthCheck()
            
            if healthResponse.status == "healthy" {
                sessionStatus = .connected
                sessionStartTime = Date()
                estimatedSessionExpiry = Date().addingTimeInterval(maxSessionDuration)
                reconnectionAttempts = 0
                
                // Start health monitoring
                startHealthMonitoring()
                
                LogManager.logger.info("Colab session started successfully")
            } else {
                throw ColabSessionError.unhealthyService
            }
        } catch {
            sessionStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    func reconnectSession() async throws {
        guard let endpoint = currentEndpoint else {
            throw ColabSessionError.noEndpointConfigured
        }
        
        guard reconnectionAttempts < maxReconnectionAttempts else {
            sessionStatus = .error("Max reconnection attempts reached")
            throw ColabSessionError.maxReconnectionAttemptsReached
        }
        
        sessionStatus = .reconnecting
        reconnectionAttempts += 1
        
        LogManager.logger.info("Attempting to reconnect to Colab session (attempt \(reconnectionAttempts))")
        
        // Wait before reconnecting
        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(reconnectionAttempts)) * 1_000_000_000))
        
        try await startSession(endpointURL: endpoint)
    }
    
    func endSession() {
        sessionStatus = .disconnected
        currentEndpoint = nil
        sessionStartTime = nil
        estimatedSessionExpiry = nil
        reconnectionAttempts = 0
        
        stopHealthMonitoring()
        
        LogManager.logger.info("Colab session ended")
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring() {
        stopHealthMonitoring()
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthCheck()
            }
        }
    }
    
    private func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func performHealthCheck() async {
        do {
            let healthResponse = try await apiClient.healthCheck()
            
            if healthResponse.status != "healthy" {
                LogManager.logger.warn("Colab service unhealthy: \(healthResponse.status)")
                
                // Attempt reconnection
                try await reconnectSession()
            } else {
                // Reset reconnection attempts on successful health check
                reconnectionAttempts = 0
            }
        } catch {
            LogManager.logger.error("Health check failed: \(error)")
            
            // Check if session might be expired
            if let startTime = sessionStartTime,
               Date().timeIntervalSince(startTime) > maxSessionDuration {
                sessionStatus = .expired
                LogManager.logger.warn("Colab session likely expired")
            } else {
                // Attempt reconnection
                do {
                    try await reconnectSession()
                } catch {
                    LogManager.logger.error("Reconnection failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Session Info
    
    func getSessionInfo() -> SessionInfo {
        let remainingTime: TimeInterval?
        if let expiry = estimatedSessionExpiry {
            remainingTime = max(0, expiry.timeIntervalSinceNow)
        } else {
            remainingTime = nil
        }
        
        let uptime: TimeInterval?
        if let startTime = sessionStartTime {
            uptime = Date().timeIntervalSince(startTime)
        } else {
            uptime = nil
        }
        
        return SessionInfo(
            status: sessionStatus,
            endpoint: currentEndpoint,
            startTime: sessionStartTime,
            estimatedExpiry: estimatedSessionExpiry,
            remainingTime: remainingTime,
            uptime: uptime,
            reconnectionAttempts: reconnectionAttempts
        )
    }
    
    func isSessionHealthy() -> Bool {
        return sessionStatus == .connected
    }
    
    func requiresNewSession() -> Bool {
        switch sessionStatus {
        case .disconnected, .expired, .error:
            return true
        case .connecting, .connected, .reconnecting:
            return false
        }
    }
    
    // MARK: - Automatic Session Management
    
    func ensureActiveSession() async throws {
        if requiresNewSession() {
            // Need to prompt user for new Colab URL
            throw ColabSessionError.sessionExpiredNeedsNewURL
        }
        
        if sessionStatus == .reconnecting {
            // Wait for reconnection to complete
            var attempts = 0
            while sessionStatus == .reconnecting && attempts < 30 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                attempts += 1
            }
            
            if sessionStatus != .connected {
                throw ColabSessionError.reconnectionFailed
            }
        }
    }
}

// MARK: - Supporting Types

struct SessionInfo {
    let status: ColabSessionManager.SessionStatus
    let endpoint: URL?
    let startTime: Date?
    let estimatedExpiry: Date?
    let remainingTime: TimeInterval?
    let uptime: TimeInterval?
    let reconnectionAttempts: Int
    
    var formattedRemainingTime: String? {
        guard let remaining = remainingTime else { return nil }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    var formattedUptime: String? {
        guard let uptime = uptime else { return nil }
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

enum ColabSessionError: LocalizedError {
    case noEndpointConfigured
    case unhealthyService
    case maxReconnectionAttemptsReached
    case sessionExpiredNeedsNewURL
    case reconnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .noEndpointConfigured:
            return "No Colab endpoint configured"
        case .unhealthyService:
            return "Colab service is not healthy"
        case .maxReconnectionAttemptsReached:
            return "Maximum reconnection attempts reached"
        case .sessionExpiredNeedsNewURL:
            return "Colab session expired. Please start a new Colab notebook and update the URL."
        case .reconnectionFailed:
            return "Failed to reconnect to Colab session"
        }
    }
}

// MARK: - Configuration Extension

extension AIAnalysisConfigManager {
    func setColabConfiguration(_ config: ColabConfiguration) async {
        colabConfiguration = config
    }
}
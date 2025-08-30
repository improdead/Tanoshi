//
//  Logger.swift
//  Aidoku
//
//  Created by Skitty on 5/24/22.
//

import Foundation

enum LogType {
    case `default`
    case info
    case debug
    case warning
    case error

    func toString() -> String {
        switch self {
        case .default:
            return ""
        case .info:
            return "INFO"
        case .debug:
            return "DEBUG"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }
}

class Logger {

    let store: LogStore

    var printLogs = true

    private var streamObserverId: UUID?
    var streamUrl: URL? {
        didSet {
            updateStreamUrl()
        }
    }

    deinit {
        if let streamObserverId = streamObserverId {
            store.removeObserver(id: streamObserverId)
        }
    }

    // Dedup state to avoid flooding logs with identical messages
    private var lastMessage: String?
    private var lastLevel: LogType = .default
    private var lastTimestamp: TimeInterval = 0
    private var repeatCount: Int = 0

    // Suppress identical messages within this window (seconds)
    private let dedupWindow: TimeInterval = 2.0

    init(store: LogStore = LogStore(), streamUrl: URL? = nil) {
        self.store = store
        self.streamUrl = streamUrl
        updateStreamUrl()
    }

    private func updateStreamUrl() {
        if let oldId = streamObserverId { store.removeObserver(id: oldId) }
        if let newUrl = streamUrl {
            streamObserverId = store.addObserver { entry in
                Task {
                    var request = URLRequest(url: newUrl)
                    request.httpBody = entry.formatted().data(using: .utf8)
                    request.httpMethod = "POST"
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        } else {
            streamObserverId = nil
        }
    }

    private func flushRepeatSummaryIfNeeded(now: TimeInterval) {
        if repeatCount > 0, let lastMessage {
            let summary = "(previous) \(lastMessage) — repeated \(repeatCount)x"
            if printLogs {
                let prefix = lastLevel != .default ? "[\(lastLevel.toString())] " : ""
                print("\(prefix)\(summary)")
            }
            store.addEntry(level: lastLevel, message: summary)
            repeatCount = 0
        }
    }

    func log(level: LogType = .default, _ message: String) {
        let now = Date().timeIntervalSince1970
        if let last = lastMessage, last == message {
            if now - lastTimestamp <= dedupWindow {
                repeatCount += 1
                lastTimestamp = now
                return
            } else {
                // Window elapsed; emit summary before logging again
                flushRepeatSummaryIfNeeded(now: now)
            }
        } else {
            // Different message; flush any pending summary
            flushRepeatSummaryIfNeeded(now: now)
        }

        if printLogs {
            let prefix = level != .default ? "[\(level.toString())] " : ""
            print("\(prefix)\(message)")
        }
        store.addEntry(level: level, message: message)
        lastMessage = message
        lastLevel = level
        lastTimestamp = now
    }

    func debug(_ message: String) {
        log(level: .debug, message)
    }

    func info(_ message: String) {
        log(level: .info, message)
    }

    func warn(_ message: String) {
        log(level: .warning, message)
    }

    func error(_ message: String) {
        log(level: .error, message)
    }
}

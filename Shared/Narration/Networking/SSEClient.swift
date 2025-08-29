import Foundation

// Simple Server-Sent Events (SSE) client for iOS 15+/macOS 12+ using URLSession bytes API.
// It parses `event:` and `data:` lines and invokes callbacks on the provided queue.

public final class TNSSEClient {
    public typealias EventHandler = (_ event: String, _ data: Data) -> Void
    public typealias ErrorHandler = (_ error: Error) -> Void

    private var task: Task<Void, Never>?
    private let callbackQueue: DispatchQueue

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    public func start(url: URL, lastEventID: String? = nil, headers: [String: String] = [:], onEvent: @escaping EventHandler, onError: @escaping ErrorHandler) {
        stop()
        task = Task {
            await stream(url: url, lastEventID: lastEventID, headers: headers, onEvent: onEvent, onError: onError)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func dispatch(_ block: @escaping () -> Void) {
        callbackQueue.async(execute: block)
    }

    private func stream(url: URL, lastEventID: String?, headers: [String: String], onEvent: @escaping EventHandler, onError: @escaping ErrorHandler) async {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let id = lastEventID { request.setValue(id, forHTTPHeaderField: "Last-Event-ID") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "TNSSE", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Bad SSE response"])
            }

            var currentEvent = "message"
            var currentData = Data()

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                if line.hasPrefix(":") { continue } // comment
                if line.isEmpty { // dispatch event
                    if !currentData.isEmpty {
                        let ev = currentEvent
                        let data = currentData
                        dispatch { onEvent(ev, data) }
                        currentData = Data()
                        currentEvent = "message"
                    }
                    continue
                }
                if line.hasPrefix("event:") {
                    let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    currentEvent = name.isEmpty ? "message" : name
                } else if line.hasPrefix("data:") {
                    var payload = line.dropFirst(5)
                    if payload.hasPrefix(" ") { payload = payload.dropFirst() }
                    if let d = String(payload).data(using: .utf8) {
                        if !currentData.isEmpty { currentData.append(0x0A) } // newline between multi-line data
                        currentData.append(d)
                    }
                }
            }
        } catch {
            if Task.isCancelled { return }
            dispatch { onError(error) }
        }
    }
}


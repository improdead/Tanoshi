import Foundation

// REST client for Tanoshi Narration API.
// Handles session start/next and snapshot.
// Robust error logging via LogManager.logger.

public enum TNNarrationError: Error, LocalizedError {
    case badURL
    case http(Int)
    case decode(String)
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Bad URL"
        case .http(let code): return "HTTP error (\(code))"
        case .decode(let msg): return "Decode error: \(msg)"
        case .other(let msg): return msg
        }
    }
}

public struct TNNarrationAPI {
    public var baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    private func makeRequest(path: String, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw TNNarrationError.badURL }
        var req = URLRequest(url: url)
        if let body = body {
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            req.httpMethod = "GET"
        }
        return req
    }

    public func startSession(_ payload: TNStartSessionRequest) async throws -> TNStartSessionResponse {
        do {
            let data = try JSONEncoder().encode(payload)
            let req = try makeRequest(path: "/v1/narration/session/start", body: data)
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw TNNarrationError.other("No HTTPURLResponse") }
            guard 200..<300 ~= http.statusCode else {
                LogManager.logger.error("startSession http=\(http.statusCode) body=\(String(data: respData, encoding: .utf8) ?? "<bin>")")
                throw TNNarrationError.http(http.statusCode)
            }
            return try JSONDecoder().decode(TNStartSessionResponse.self, from: respData)
        } catch let e as TNNarrationError {
            throw e
        } catch {
            LogManager.logger.error("startSession error: \(error)")
            throw TNNarrationError.other(error.localizedDescription)
        }
    }

    public func nextSession(_ payload: TNStartSessionRequest) async throws -> TNStartSessionResponse {
        do {
            let data = try JSONEncoder().encode(payload)
            let req = try makeRequest(path: "/v1/narration/session/next", body: data)
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw TNNarrationError.other("No HTTPURLResponse") }
            guard 200..<300 ~= http.statusCode else {
                LogManager.logger.error("nextSession http=\(http.statusCode) body=\(String(data: respData, encoding: .utf8) ?? "<bin>")")
                throw TNNarrationError.http(http.statusCode)
            }
            return try JSONDecoder().decode(TNStartSessionResponse.self, from: respData)
        } catch let e as TNNarrationError {
            throw e
        } catch {
            LogManager.logger.error("nextSession error: \(error)")
            throw TNNarrationError.other(error.localizedDescription)
        }
    }

    public func snapshot(jobID: String) async throws -> TNJobSnapshot {
        do {
            let req = try makeRequest(path: "/v1/narration/jobs/\(jobID)/snapshot")
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw TNNarrationError.other("No HTTPURLResponse") }
            guard 200..<300 ~= http.statusCode else {
                LogManager.logger.error("snapshot http=\(http.statusCode) body=\(String(data: respData, encoding: .utf8) ?? "<bin>")")
                throw TNNarrationError.http(http.statusCode)
            }
            return try JSONDecoder().decode(TNJobSnapshot.self, from: respData)
        } catch let e as TNNarrationError {
            throw e
        } catch {
            LogManager.logger.error("snapshot error: \(error)")
            throw TNNarrationError.other(error.localizedDescription)
        }
    }
}


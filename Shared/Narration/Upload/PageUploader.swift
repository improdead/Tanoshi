import Foundation

// Handles uploading PNG pages to presigned S3 URLs with strict Content-Type and size checks.
// Emits detailed log lines to aid debugging.

public enum TNUploadError: Error, LocalizedError {
    case invalidURL
    case tooLarge(max: Int, actual: Int)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid upload URL"
        case .tooLarge(let max, let actual): return "PNG exceeds max bytes (max=\(max), actual=\(actual))"
        case .http(let code, let body): return "Upload failed (\(code)): \(body)"
        }
    }
}

public struct TNPageUploader {
    public init() {}

    public func upload(pageData: Data, to plan: TNPagePut) async throws {
        guard let url = URL(string: plan.put_url) else { throw TNUploadError.invalidURL }
        if let max = plan.max_bytes, pageData.count > max { throw TNUploadError.tooLarge(max: max, actual: pageData.count) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.httpBody = pageData
        req.setValue(plan.content_type ?? "image/png", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw TNUploadError.http(-1, "no response") }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<bin>"
                LogManager.logger.error("upload_failed index=\(plan.index) http=\(http.statusCode) body=\(body)")
                throw TNUploadError.http(http.statusCode, body)
            }
        } catch {
            LogManager.logger.error("upload_error index=\(plan.index) err=\(error)")
            throw error
        }
    }
}


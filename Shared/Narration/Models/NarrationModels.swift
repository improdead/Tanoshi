import Foundation

// Shared models for Tanoshi Narration client
// These mirror the backend contracts in WARP.md. Keep fields Codable-compatible.

public struct TNVoicePack: Codable, Equatable {
    public var Narrator: String
    public var MC: String

    public init(Narrator: String, MC: String) {
        self.Narrator = Narrator
        self.MC = MC
    }
}

public struct TNWindow: Codable, Equatable {
    public var start_index: Int
    public var size: Int
    public init(start_index: Int = 0, size: Int = 20) {
        self.start_index = start_index
        self.size = size
    }
}

public struct TNClientInfo: Codable, Equatable {
    public var device: String
    public var app_version: String
    public init(device: String, app_version: String) {
        self.device = device
        self.app_version = app_version
    }
}

public struct TNPagePut: Codable, Equatable {
    public var index: Int
    public var put_url: String
    public var content_type: String?
    public var max_bytes: Int?
}

public struct TNUploadPlan: Codable, Equatable {
    public var mode: String
    public var pages: [TNPagePut]
}

public struct TNStartSessionRequest: Codable {
    public var chapter_id: String
    public var voice_pack: TNVoicePack
    public var window: TNWindow
    public var client: TNClientInfo
}

public struct TNStartSessionResponse: Codable {
    public var job_id: String
    public var upload: TNUploadPlan
    public var status_sse: String
    public var audio_url_template: String
    public var adPlan: [String: AnyCodable]?
}

public struct TNProgress: Codable, Equatable {
    public var done: Int
    public var total: Int
}

public enum TNPageState: String, Codable {
    case queued
    case extracting
    case tts
    case ready
    case error
}

public struct TNJobSnapshot: Codable {
    public var job_id: String
    public var pages: [TNPageSnapshot]
    public var progress: TNProgress
}

public struct TNPageSnapshot: Codable, Equatable {
    public var index: Int
    public var state: TNPageState
    public var audio: String?
    public var reason: String?
}

// Simple type-erased wrapper for adPlan map
public struct AnyCodable: Codable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal; return }
        if let dblVal = try? container.decode(Double.self) { value = dblVal; return }
        if let boolVal = try? container.decode(Bool.self) { value = boolVal; return }
        if let strVal = try? container.decode(String.self) { value = strVal; return }
        if let dictVal = try? container.decode([String: AnyCodable].self) { value = dictVal; return }
        if let arrVal = try? container.decode([AnyCodable].self) { value = arrVal; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        default:
            let ctx = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type")
            throw EncodingError.invalidValue(value, ctx)
        }
    }
}


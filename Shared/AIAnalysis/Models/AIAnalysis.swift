//
//  AIAnalysis.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import CoreGraphics

// MARK: - Core Analysis Models

struct AnalysisResult: Codable {
    let mangaId: String
    let chapterId: String
    let pages: [PageAnalysis]
    let transcript: [DialogueLine]
    let audioSegments: [AudioSegment]?
    let analysisDate: Date
    let version: String
}

struct PageAnalysis: Codable {
    let pageIndex: Int
    let textRegions: [TextRegion]
    let characterDetections: [CharacterDetection]
    let textCharacterAssociations: [Int: Int] // text_idx: char_idx
}

struct TextRegion: Codable {
    let id: Int
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let isEssential: Bool
}

struct CharacterDetection: Codable {
    let id: Int
    let name: String
    let boundingBox: CGRect
    let confidence: Float
}

struct DialogueLine: Codable {
    let pageIndex: Int
    let textId: Int
    let speaker: String
    let text: String
    let timestamp: TimeInterval?
}

struct AudioSegment: Codable {
    let dialogueId: String
    let audioData: Data
    let duration: TimeInterval
    let speaker: String
    let text: String
}

// MARK: - Character Bank Models

struct CharacterBank: Codable {
    let mangaId: String
    let characters: [CharacterInfo]
    let lastUpdated: Date
}

struct CharacterInfo: Codable {
    let id: String
    let name: String
    let referenceImages: [String] // File paths
    let confidence: Float
    let lastSeen: Date
}

// MARK: - Configuration Models

struct ColabConfiguration: Codable {
    let endpointURL: URL
    let apiKey: String?
    let timeout: TimeInterval
    let maxRetries: Int
    let batchSize: Int
    
    static let `default` = ColabConfiguration(
        endpointURL: URL(string: "https://example.ngrok.io")!,
        apiKey: nil,
        timeout: 300.0, // 5 minutes
        maxRetries: 3,
        batchSize: 10
    )
}

struct VoiceSettings: Codable {
    let language: String // Language code (en, es, fr, etc.)
    let defaultVoiceFile: String? // Base64 encoded audio file for default voice
    let characterVoiceFiles: [String: String] // character_name: base64_audio_file
    let characterVoiceSettings: [String: CharacterVoiceSettings] // character_name: voice_settings
    let globalVoiceSettings: GlobalVoiceSettings
    
    static let `default` = VoiceSettings(
        language: "en",
        defaultVoiceFile: nil,
        characterVoiceFiles: [:],
        characterVoiceSettings: [:],
        globalVoiceSettings: .default
    )
}

struct CharacterVoiceSettings: Codable {
    let pitch: Float // -1.0 to 1.0 (lower to higher pitch)
    let speed: Float // 0.5 to 2.0 (slower to faster)
    let emotion: VoiceEmotion
    let intensity: Float // 0.0 to 1.0 (calm to intense)
    let breathiness: Float // 0.0 to 1.0 (clear to breathy)
    
    static let `default` = CharacterVoiceSettings(
        pitch: 0.0,
        speed: 1.0,
        emotion: .neutral,
        intensity: 0.5,
        breathiness: 0.3
    )
}

struct GlobalVoiceSettings: Codable {
    let masterVolume: Float // 0.0 to 1.0
    let pauseBetweenDialogue: TimeInterval // Seconds between dialogue lines
    let pauseBetweenPages: TimeInterval // Seconds between pages
    let autoPageTurn: Bool // Enable automatic page turning
    let pageTransitionDelay: TimeInterval // Delay before turning page after audio ends
    
    static let `default` = GlobalVoiceSettings(
        masterVolume: 0.8,
        pauseBetweenDialogue: 0.5,
        pauseBetweenPages: 1.0,
        autoPageTurn: true,
        pageTransitionDelay: 1.5
    )
}

enum VoiceEmotion: String, Codable, CaseIterable {
    case neutral = "neutral"
    case happy = "happy"
    case sad = "sad"
    case angry = "angry"
    case excited = "excited"
    case calm = "calm"
    case mysterious = "mysterious"
    case dramatic = "dramatic"
    
    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .happy: return "Happy"
        case .sad: return "Sad"
        case .angry: return "Angry"
        case .excited: return "Excited"
        case .calm: return "Calm"
        case .mysterious: return "Mysterious"
        case .dramatic: return "Dramatic"
        }
    }
}

struct XTTSConfiguration: Codable {
    let voiceSettings: VoiceSettings
    let availableSpeakers: [String]
    let supportedLanguages: [String]
    
    static let `default` = XTTSConfiguration(
        voiceSettings: .default,
        availableSpeakers: [],
        supportedLanguages: ["en", "es", "fr", "de", "it", "pt", "pl", "tr", "ru", "nl", "cs", "ar", "zh-cn", "ja", "hu", "ko"]
    )
}

// MARK: - API Response Models

struct ColabAnalysisResponse: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let result: AnalysisResult?
    let error: String?
}

struct ColabAudioResponse: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let audioSegments: [AudioSegment]?
    let error: String?
}

struct ColabHealthResponse: Codable {
    let status: String
    let magiLoaded: Bool
    let ttsModelsLoaded: Int
    let xttsV2Loaded: Bool
    let availableSpeakers: [String]
    
    private enum CodingKeys: String, CodingKey {
        case status
        case magiLoaded = "magi_loaded"
        case ttsModelsLoaded = "tts_models_loaded"
        case xttsV2Loaded = "xtts_v2_loaded"
        case availableSpeakers = "available_speakers"
    }
}

// MARK: - Error Types

enum AIAnalysisError: LocalizedError {
    case networkUnavailable
    case endpointNotConfigured
    case invalidResponse
    case analysisTimeout
    case insufficientStorage
    case characterBankCorrupted
    case audioGenerationFailed
    case unsupportedFileFormat
    case jobNotFound
    case analysisInProgress
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return NSLocalizedString("NETWORK_UNAVAILABLE", comment: "Network connection unavailable")
        case .endpointNotConfigured:
            return NSLocalizedString("ENDPOINT_NOT_CONFIGURED", comment: "Google Colab endpoint not configured")
        case .invalidResponse:
            return NSLocalizedString("INVALID_RESPONSE", comment: "Invalid response from analysis service")
        case .analysisTimeout:
            return NSLocalizedString("ANALYSIS_TIMEOUT", comment: "Analysis request timed out")
        case .insufficientStorage:
            return NSLocalizedString("INSUFFICIENT_STORAGE", comment: "Insufficient storage for analysis cache")
        case .characterBankCorrupted:
            return NSLocalizedString("CHARACTER_BANK_CORRUPTED", comment: "Character bank data is corrupted")
        case .audioGenerationFailed:
            return NSLocalizedString("AUDIO_GENERATION_FAILED", comment: "Failed to generate audio")
        case .unsupportedFileFormat:
            return NSLocalizedString("UNSUPPORTED_FILE_FORMAT", comment: "Unsupported file format for analysis")
        case .jobNotFound:
            return NSLocalizedString("JOB_NOT_FOUND", comment: "Analysis job not found")
        case .analysisInProgress:
            return NSLocalizedString("ANALYSIS_IN_PROGRESS", comment: "Analysis is already in progress")
        }
    }
}

// MARK: - Emotional Context for Voice Generation

enum EmotionalContext: String, Codable {
    case neutral = "neutral"
    case happy = "happy"
    case sad = "sad"
    case angry = "angry"
    case excited = "excited"
    case questioning = "questioning"
    case whispering = "whispering"
    case shouting = "shouting"
}
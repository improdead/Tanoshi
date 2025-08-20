//
//  AIAnalysisConfigManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation

/// Manages configuration for AI analysis features
actor AIAnalysisConfigManager {
    static let shared = AIAnalysisConfigManager()
    
    private let userDefaults = UserDefaults.standard
    
    // Configuration keys
    private enum ConfigKeys {
        static let colabEndpointURL = "ai_analysis_colab_endpoint_url"
        static let colabAPIKey = "ai_analysis_colab_api_key"
        static let colabTimeout = "ai_analysis_colab_timeout"
        static let colabMaxRetries = "ai_analysis_colab_max_retries"
        static let colabBatchSize = "ai_analysis_colab_batch_size"
        static let voiceLanguage = "ai_analysis_voice_language"
        static let autoAnalysisEnabled = "ai_analysis_auto_enabled"
        static let cacheMaxSize = "ai_analysis_cache_max_size"
        static let analysisBatchSize = "ai_analysis_batch_size"
    }
    
    private init() {}
    
    // MARK: - Colab Configuration
    
    var colabConfiguration: ColabConfiguration {
        get {
            let urlString = userDefaults.string(forKey: ConfigKeys.colabEndpointURL) ?? ""
            let url = URL(string: urlString) ?? ColabConfiguration.default.endpointURL
            
            return ColabConfiguration(
                endpointURL: url,
                apiKey: userDefaults.string(forKey: ConfigKeys.colabAPIKey),
                timeout: userDefaults.double(forKey: ConfigKeys.colabTimeout) > 0 
                    ? userDefaults.double(forKey: ConfigKeys.colabTimeout) 
                    : ColabConfiguration.default.timeout,
                maxRetries: userDefaults.integer(forKey: ConfigKeys.colabMaxRetries) > 0 
                    ? userDefaults.integer(forKey: ConfigKeys.colabMaxRetries) 
                    : ColabConfiguration.default.maxRetries,
                batchSize: userDefaults.integer(forKey: ConfigKeys.colabBatchSize) > 0 
                    ? userDefaults.integer(forKey: ConfigKeys.colabBatchSize) 
                    : ColabConfiguration.default.batchSize
            )
        }
        set {
            userDefaults.set(newValue.endpointURL.absoluteString, forKey: ConfigKeys.colabEndpointURL)
            userDefaults.set(newValue.apiKey, forKey: ConfigKeys.colabAPIKey)
            userDefaults.set(newValue.timeout, forKey: ConfigKeys.colabTimeout)
            userDefaults.set(newValue.maxRetries, forKey: ConfigKeys.colabMaxRetries)
            userDefaults.set(newValue.batchSize, forKey: ConfigKeys.colabBatchSize)
        }
    }
    
    // MARK: - Voice Configuration
    
    var voiceSettings: VoiceSettings {
        get {
            let language = userDefaults.string(forKey: ConfigKeys.voiceLanguage) ?? VoiceSettings.default.language
            
            // Load character voice files from documents directory
            let characterVoiceFiles = loadCharacterVoiceFiles()
            let defaultVoiceFile = loadDefaultVoiceFile()
            let characterVoiceSettings = loadCharacterVoiceSettings()
            let globalVoiceSettings = loadGlobalVoiceSettings()
            
            return VoiceSettings(
                language: language,
                defaultVoiceFile: defaultVoiceFile,
                characterVoiceFiles: characterVoiceFiles,
                characterVoiceSettings: characterVoiceSettings,
                globalVoiceSettings: globalVoiceSettings
            )
        }
        set {
            userDefaults.set(newValue.language, forKey: ConfigKeys.voiceLanguage)
            saveCharacterVoiceFiles(newValue.characterVoiceFiles)
            saveDefaultVoiceFile(newValue.defaultVoiceFile)
            saveCharacterVoiceSettings(newValue.characterVoiceSettings)
            saveGlobalVoiceSettings(newValue.globalVoiceSettings)
        }
    }
    
    // MARK: - General Settings
    
    var isAutoAnalysisEnabled: Bool {
        get {
            userDefaults.bool(forKey: ConfigKeys.autoAnalysisEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.autoAnalysisEnabled)
        }
    }
    
    var cacheMaxSize: Int64 {
        get {
            let size = userDefaults.object(forKey: ConfigKeys.cacheMaxSize) as? Int64
            return size ?? 1024 * 1024 * 1024 // Default 1GB
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.cacheMaxSize)
        }
    }

    /// Maximum number of pages to process per batch when enabling listening. Default: 20.
    var analysisBatchSize: Int {
        get {
            let value = userDefaults.integer(forKey: ConfigKeys.analysisBatchSize)
            return value > 0 ? value : 20
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.analysisBatchSize)
        }
    }
    
    // MARK: - Validation
    
    func validateConfiguration() async throws {
        let config = colabConfiguration
        
        // Check if endpoint URL is valid
        guard config.endpointURL.scheme != nil else {
            throw AIAnalysisError.endpointNotConfigured
        }
        
        // Test connection to endpoint
        do {
            let healthURL = config.endpointURL.appendingPathComponent("health")
            let request = URLRequest(url: healthURL)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw AIAnalysisError.networkUnavailable
            }
        } catch {
            throw AIAnalysisError.networkUnavailable
        }
    }
    
    // MARK: - Voice File Management
    
    private func voiceFilesDirectory() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let voiceDir = documentsDir.appendingPathComponent("AIAnalysis/VoiceFiles", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: voiceDir, withIntermediateDirectories: true)
        
        return voiceDir
    }
    
    private func loadCharacterVoiceFiles() -> [String: String] {
        let voiceDir = voiceFilesDirectory()
        let characterVoicesFile = voiceDir.appendingPathComponent("character_voices.json")
        
        guard let data = try? Data(contentsOf: characterVoicesFile),
              let voices = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        
        return voices
    }
    
    private func saveCharacterVoiceFiles(_ voices: [String: String]) {
        let voiceDir = voiceFilesDirectory()
        let characterVoicesFile = voiceDir.appendingPathComponent("character_voices.json")
        
        guard let data = try? JSONEncoder().encode(voices) else { return }
        try? data.write(to: characterVoicesFile)
    }
    
    private func loadDefaultVoiceFile() -> String? {
        let voiceDir = voiceFilesDirectory()
        let defaultVoiceFile = voiceDir.appendingPathComponent("default_voice.txt")
        
        return try? String(contentsOf: defaultVoiceFile)
    }
    
    private func saveDefaultVoiceFile(_ voiceFile: String?) {
        let voiceDir = voiceFilesDirectory()
        let defaultVoiceFile = voiceDir.appendingPathComponent("default_voice.txt")
        
        if let voiceFile = voiceFile {
            try? voiceFile.write(to: defaultVoiceFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: defaultVoiceFile)
        }
    }
    
    private func loadCharacterVoiceSettings() -> [String: CharacterVoiceSettings] {
        let voiceDir = voiceFilesDirectory()
        let settingsFile = voiceDir.appendingPathComponent("character_voice_settings.json")
        
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode([String: CharacterVoiceSettings].self, from: data) else {
            return [:]
        }
        
        return settings
    }
    
    private func saveCharacterVoiceSettings(_ settings: [String: CharacterVoiceSettings]) {
        let voiceDir = voiceFilesDirectory()
        let settingsFile = voiceDir.appendingPathComponent("character_voice_settings.json")
        
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
    
    private func loadGlobalVoiceSettings() -> GlobalVoiceSettings {
        let voiceDir = voiceFilesDirectory()
        let settingsFile = voiceDir.appendingPathComponent("global_voice_settings.json")
        
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode(GlobalVoiceSettings.self, from: data) else {
            return .default
        }
        
        return settings
    }
    
    private func saveGlobalVoiceSettings(_ settings: GlobalVoiceSettings) {
        let voiceDir = voiceFilesDirectory()
        let settingsFile = voiceDir.appendingPathComponent("global_voice_settings.json")
        
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
    
    // MARK: - Reset Configuration
    
    func resetToDefaults() {
        userDefaults.removeObject(forKey: ConfigKeys.colabEndpointURL)
        userDefaults.removeObject(forKey: ConfigKeys.colabAPIKey)
        userDefaults.removeObject(forKey: ConfigKeys.colabTimeout)
        userDefaults.removeObject(forKey: ConfigKeys.colabMaxRetries)
        userDefaults.removeObject(forKey: ConfigKeys.colabBatchSize)
        userDefaults.removeObject(forKey: ConfigKeys.voiceLanguage)
        userDefaults.removeObject(forKey: ConfigKeys.autoAnalysisEnabled)
        userDefaults.removeObject(forKey: ConfigKeys.cacheMaxSize)
        
        // Clear voice files
        let voiceDir = voiceFilesDirectory()
        try? FileManager.default.removeItem(at: voiceDir)
    }
}
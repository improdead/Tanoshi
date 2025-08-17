//
//  ColabAPIClient.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import UIKit

/// Client for communicating with Google Colab AI analysis backend
actor ColabAPIClient {
    static let shared = ColabAPIClient()
    
    private let session = URLSession.shared
    private let configManager = AIAnalysisConfigManager.shared
    
    private init() {}
    
    // MARK: - Health Check
    
    func healthCheck() async throws -> ColabHealthResponse {
        let config = await configManager.colabConfiguration
        let healthURL = config.endpointURL.appendingPathComponent("health")
        
        let request = URLRequest.from(healthURL, method: "GET")
        
        do {
            let response: ColabHealthResponse = try await session.object(from: request)
            return response
        } catch {
            LogManager.logger.error("Health check failed: \(error)")
            throw AIAnalysisError.networkUnavailable
        }
    }
    
    // MARK: - Single Page Analysis
    
    func startSinglePageAnalysis(page: UIImage, characterBank: CharacterBank?) async throws -> String {
        let config = await configManager.colabConfiguration
        let analyzeURL = config.endpointURL.appendingPathComponent("analyze")
        
        // Convert single image to base64
        guard let pngData = page.pngData() else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        let base64Page = pngData.base64EncodedString()
        
        // Prepare character bank data
        var characterBankData: [String: Any] = [
            "images": [],
            "names": []
        ]
        
        if let characterBank = characterBank {
            let characterImages = try await loadCharacterImages(characterBank.characters)
            characterBankData = [
                "images": characterImages,
                "names": characterBank.characters.map { $0.name }
            ]
        }
        
        // Prepare request body for single page
        let requestBody: [String: Any] = [
            "pages": [base64Page], // Single page in array
            "characterBank": characterBankData
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIAnalysisError.invalidResponse
        }
        
        var request = URLRequest.from(analyzeURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                LogManager.logger.error("Single page analysis request failed with status: \(httpResponse.statusCode)")
                throw AIAnalysisError.networkUnavailable
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String else {
                throw AIAnalysisError.invalidResponse
            }
            
            LogManager.logger.info("Started single page analysis job: \(jobId)")
            return jobId
            
        } catch {
            LogManager.logger.error("Single page analysis request failed: \(error)")
            throw AIAnalysisError.networkUnavailable
        }
    }

    // MARK: - Analysis
    
    func startAnalysis(pages: [UIImage], characterBank: CharacterBank?) async throws -> String {
        let config = await configManager.colabConfiguration
        let analyzeURL = config.endpointURL.appendingPathComponent("analyze")
        
        // Convert images to base64
        let base64Pages = try await convertImagesToBase64(pages)
        
        // Prepare character bank data
        var characterBankData: [String: Any] = [
            "images": [],
            "names": []
        ]
        
        if let characterBank = characterBank {
            let characterImages = try await loadCharacterImages(characterBank.characters)
            characterBankData = [
                "images": characterImages,
                "names": characterBank.characters.map { $0.name }
            ]
        }
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "pages": base64Pages,
            "characterBank": characterBankData
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIAnalysisError.invalidResponse
        }
        
        var request = URLRequest.from(analyzeURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                LogManager.logger.error("Analysis request failed with status: \(httpResponse.statusCode)")
                throw AIAnalysisError.networkUnavailable
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String else {
                throw AIAnalysisError.invalidResponse
            }
            
            LogManager.logger.info("Started analysis job: \(jobId)")
            return jobId
            
        } catch {
            LogManager.logger.error("Analysis request failed: \(error)")
            throw AIAnalysisError.networkUnavailable
        }
    }
    
    func getAnalysisStatus(jobId: String) async throws -> ColabAnalysisResponse {
        let config = await configManager.colabConfiguration
        let statusURL = config.endpointURL.appendingPathComponent("status/\(jobId)")
        
        var request = URLRequest.from(statusURL, method: "GET")
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw AIAnalysisError.jobNotFound
                }
                throw AIAnalysisError.networkUnavailable
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let statusResponse = try decoder.decode(ColabAnalysisResponse.self, from: data)
            return statusResponse
            
        } catch let error as AIAnalysisError {
            throw error
        } catch {
            LogManager.logger.error("Status check failed: \(error)")
            throw AIAnalysisError.networkUnavailable
        }
    }
    
    func getAnalysisResult(jobId: String) async throws -> AnalysisResult {
        let config = await configManager.colabConfiguration
        let resultURL = config.endpointURL.appendingPathComponent("result/\(jobId)")
        
        var request = URLRequest.from(resultURL, method: "GET")
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw AIAnalysisError.jobNotFound
                }
                throw AIAnalysisError.networkUnavailable
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // Parse the raw result first to extract the nested structure
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIAnalysisError.invalidResponse
            }
            
            // Extract the actual result data
            guard let pages = json["pages"] as? [[String: Any]],
                  let transcript = json["transcript"] as? [[String: Any]] else {
                throw AIAnalysisError.invalidResponse
            }
            
            // Convert to our models
            let pageAnalyses = try parsePageAnalyses(pages)
            let dialogueLines = try parseDialogueLines(transcript)
            
            // Create result with placeholder values for required fields
            let result = AnalysisResult(
                mangaId: "", // Will be set by the caller
                chapterId: "", // Will be set by the caller
                pages: pageAnalyses,
                transcript: dialogueLines,
                audioSegments: nil, // Audio is generated separately
                analysisDate: Date(),
                version: json["version"] as? String ?? "1.0"
            )
            
            return result
            
        } catch let error as AIAnalysisError {
            throw error
        } catch {
            LogManager.logger.error("Result fetch failed: \(error)")
            throw AIAnalysisError.invalidResponse
        }
    }
    
    // MARK: - Page-Specific Audio Generation
    
    func generatePageAudio(dialogue: [DialogueLine], voiceSettings: VoiceSettings) async throws -> String {
        let config = await configManager.colabConfiguration
        let audioURL = config.endpointURL.appendingPathComponent("audio")
        
        // Prepare request body with emotional context
        let requestBody: [String: Any] = [
            "transcript": dialogue.map { dialogueLine in
                [
                    "pageIndex": dialogueLine.pageIndex,
                    "textId": dialogueLine.textId,
                    "speaker": dialogueLine.speaker,
                    "text": dialogueLine.text,
                    "emotion": detectEmotionForAPI(in: dialogueLine.text) // Add emotion detection
                ]
            },
            "voiceSettings": [
                "language": voiceSettings.language,
                "defaultVoiceFile": voiceSettings.defaultVoiceFile ?? NSNull(),
                "characterVoiceFiles": voiceSettings.characterVoiceFiles,
                "enableEmotionalVariation": true // Tell XTTS-v2 to use emotional context
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIAnalysisError.invalidResponse
        }
        
        var request = URLRequest.from(audioURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AIAnalysisError.audioGenerationFailed
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String else {
                throw AIAnalysisError.invalidResponse
            }
            
            LogManager.logger.info("Started page audio generation job: \(jobId)")
            return jobId
            
        } catch {
            LogManager.logger.error("Page audio generation request failed: \(error)")
            throw AIAnalysisError.audioGenerationFailed
        }
    }
    
    private func detectEmotionForAPI(in text: String) -> String {
        let lowercaseText = text.lowercased()
        
        // Enhanced emotion detection for API
        if lowercaseText.contains("!!!") || lowercaseText.contains("!!!!") {
            return "shouting"
        } else if lowercaseText.contains("!") || lowercaseText.contains("!!") {
            if lowercaseText.contains("no") || lowercaseText.contains("stop") || lowercaseText.contains("wait") {
                return "angry"
            } else {
                return "excited"
            }
        } else if lowercaseText.contains("?") {
            return "questioning"
        } else if lowercaseText.contains("...") || lowercaseText.contains("..") {
            if lowercaseText.contains("sigh") || lowercaseText.contains("sob") {
                return "sad"
            } else {
                return "whispering"
            }
        } else if lowercaseText.contains("haha") || lowercaseText.contains("hehe") || lowercaseText.contains("laugh") {
            return "happy"
        } else {
            return "neutral"
        }
    }

    // MARK: - Audio Generation
    
    func generateAudio(transcript: [DialogueLine], voiceSettings: VoiceSettings) async throws -> String {
        let config = await configManager.colabConfiguration
        let audioURL = config.endpointURL.appendingPathComponent("audio")
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "transcript": transcript.map { dialogue in
                [
                    "pageIndex": dialogue.pageIndex,
                    "textId": dialogue.textId,
                    "speaker": dialogue.speaker,
                    "text": dialogue.text
                ]
            },
            "voiceSettings": [
                "language": voiceSettings.language,
                "defaultVoiceFile": voiceSettings.defaultVoiceFile ?? NSNull(),
                "characterVoiceFiles": voiceSettings.characterVoiceFiles
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIAnalysisError.invalidResponse
        }
        
        var request = URLRequest.from(audioURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AIAnalysisError.audioGenerationFailed
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String else {
                throw AIAnalysisError.invalidResponse
            }
            
            LogManager.logger.info("Started audio generation job: \(jobId)")
            return jobId
            
        } catch {
            LogManager.logger.error("Audio generation request failed: \(error)")
            throw AIAnalysisError.audioGenerationFailed
        }
    }
    
    func getAudioResult(jobId: String) async throws -> [AudioSegment] {
        let config = await configManager.colabConfiguration
        let resultURL = config.endpointURL.appendingPathComponent("audio/result/\(jobId)")
        
        var request = URLRequest.from(resultURL, method: "GET")
        
        // Add API key if configured
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw AIAnalysisError.jobNotFound
                }
                throw AIAnalysisError.audioGenerationFailed
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioSegmentsData = json["audioSegments"] as? [[String: Any]] else {
                throw AIAnalysisError.invalidResponse
            }
            
            let audioSegments = try parseAudioSegments(audioSegmentsData)
            return audioSegments
            
        } catch let error as AIAnalysisError {
            throw error
        } catch {
            LogManager.logger.error("Audio result fetch failed: \(error)")
            throw AIAnalysisError.audioGenerationFailed
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertImagesToBase64(_ images: [UIImage]) async throws -> [String] {
        return try await withThrowingTaskGroup(of: String?.self) { group in
            for image in images {
                group.addTask {
                    guard let pngData = image.pngData() else { return nil }
                    return pngData.base64EncodedString()
                }
            }
            
            var base64Images: [String] = []
            for try await base64String in group {
                if let base64String = base64String {
                    base64Images.append(base64String)
                }
            }
            
            return base64Images
        }
    }
    
    private func loadCharacterImages(_ characters: [CharacterInfo]) async throws -> [String] {
        var base64Images: [String] = []
        
        for character in characters {
            for imagePath in character.referenceImages {
                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let imageURL = documentsDir.appendingPathComponent(imagePath)
                
                if let imageData = try? Data(contentsOf: imageURL) {
                    base64Images.append(imageData.base64EncodedString())
                }
            }
        }
        
        return base64Images
    }
    
    private func parsePageAnalyses(_ pagesData: [[String: Any]]) throws -> [PageAnalysis] {
        return try pagesData.enumerated().map { index, pageData in
            let textRegions = try parseTextRegions(pageData["textRegions"] as? [[String: Any]] ?? [])
            let characterDetections = try parseCharacterDetections(pageData["characterDetections"] as? [[String: Any]] ?? [])
            let associations = pageData["textCharacterAssociations"] as? [String: Int] ?? [:]
            
            // Convert string keys to int keys
            let intAssociations = Dictionary(uniqueKeysWithValues: associations.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
            
            return PageAnalysis(
                pageIndex: index,
                textRegions: textRegions,
                characterDetections: characterDetections,
                textCharacterAssociations: intAssociations
            )
        }
    }
    
    private func parseTextRegions(_ regionsData: [[String: Any]]) throws -> [TextRegion] {
        return regionsData.compactMap { regionData in
            guard let id = regionData["id"] as? Int,
                  let text = regionData["text"] as? String else {
                return nil
            }
            
            let boundingBox = parseBoundingBox(regionData["boundingBox"] as? [String: Any])
            let confidence = regionData["confidence"] as? Float ?? 1.0
            let isEssential = regionData["isEssential"] as? Bool ?? true
            
            return TextRegion(
                id: id,
                text: text,
                boundingBox: boundingBox,
                confidence: confidence,
                isEssential: isEssential
            )
        }
    }
    
    private func parseCharacterDetections(_ detectionsData: [[String: Any]]) throws -> [CharacterDetection] {
        return detectionsData.compactMap { detectionData in
            guard let id = detectionData["id"] as? Int,
                  let name = detectionData["name"] as? String else {
                return nil
            }
            
            let boundingBox = parseBoundingBox(detectionData["boundingBox"] as? [String: Any])
            let confidence = detectionData["confidence"] as? Float ?? 1.0
            
            return CharacterDetection(
                id: id,
                name: name,
                boundingBox: boundingBox,
                confidence: confidence
            )
        }
    }
    
    private func parseDialogueLines(_ transcriptData: [[String: Any]]) throws -> [DialogueLine] {
        return transcriptData.compactMap { dialogueData in
            guard let pageIndex = dialogueData["pageIndex"] as? Int,
                  let textId = dialogueData["textId"] as? Int,
                  let speaker = dialogueData["speaker"] as? String,
                  let text = dialogueData["text"] as? String else {
                return nil
            }
            
            let timestamp = dialogueData["timestamp"] as? TimeInterval
            
            return DialogueLine(
                pageIndex: pageIndex,
                textId: textId,
                speaker: speaker,
                text: text,
                timestamp: timestamp
            )
        }
    }
    
    private func parseAudioSegments(_ segmentsData: [[String: Any]]) throws -> [AudioSegment] {
        return segmentsData.compactMap { segmentData in
            guard let dialogueId = segmentData["dialogueId"] as? String,
                  let audioDataString = segmentData["audioData"] as? String,
                  let audioData = Data(base64Encoded: audioDataString),
                  let duration = segmentData["duration"] as? TimeInterval,
                  let speaker = segmentData["speaker"] as? String,
                  let text = segmentData["text"] as? String else {
                return nil
            }
            
            return AudioSegment(
                dialogueId: dialogueId,
                audioData: audioData,
                duration: duration,
                speaker: speaker,
                text: text
            )
        }
    }
    
    private func parseBoundingBox(_ boxData: [String: Any]?) -> CGRect {
        guard let boxData = boxData,
              let x = boxData["x"] as? Double,
              let y = boxData["y"] as? Double,
              let width = boxData["width"] as? Double,
              let height = boxData["height"] as? Double else {
            return .zero
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
//
//  CharacterBankManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import UIKit

/// Manages character reference images and names per manga series
actor CharacterBankManager {
    static let shared = CharacterBankManager()
    
    private let coreDataManager = CoreDataManager.shared
    
    private init() {}
    
    // MARK: - Character Bank Operations
    
    func getCharacterBank(mangaId: String) async -> CharacterBank? {
        return await coreDataManager.getCharacterBank(mangaId: mangaId)
    }
    
    func createCharacterBank(mangaId: String) async -> CharacterBank {
        let characterBank = CharacterBank(
            mangaId: mangaId,
            characters: [],
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(characterBank)
        return characterBank
    }
    
    func addCharacter(mangaId: String, name: String, referenceImages: [UIImage]) async throws {
        // Get or create character bank
        var characterBank = await getCharacterBank(mangaId: mangaId) ?? await createCharacterBank(mangaId: mangaId)
        
        // Check if character already exists
        if characterBank.characters.contains(where: { $0.name == name }) {
            throw AIAnalysisError.characterBankCorrupted // Reusing error for "character already exists"
        }
        
        // Save reference images to disk
        let imagePaths = try await saveCharacterImages(mangaId: mangaId, characterName: name, images: referenceImages)
        
        // Create character info
        let characterInfo = CharacterInfo(
            id: UUID().uuidString,
            name: name,
            referenceImages: imagePaths,
            confidence: 1.0,
            lastSeen: Date()
        )
        
        // Add to character bank
        var updatedCharacters = characterBank.characters
        updatedCharacters.append(characterInfo)
        
        let updatedBank = CharacterBank(
            mangaId: mangaId,
            characters: updatedCharacters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(updatedBank)
        
        LogManager.logger.info("Added character '\(name)' to manga '\(mangaId)' with \(referenceImages.count) reference images")
    }
    
    func updateCharacter(mangaId: String, characterId: String, name: String? = nil, images: [UIImage]? = nil) async throws {
        guard var characterBank = await getCharacterBank(mangaId: mangaId) else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        guard let characterIndex = characterBank.characters.firstIndex(where: { $0.id == characterId }) else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        var character = characterBank.characters[characterIndex]
        
        // Update name if provided
        if let name = name {
            character = CharacterInfo(
                id: character.id,
                name: name,
                referenceImages: character.referenceImages,
                confidence: character.confidence,
                lastSeen: character.lastSeen
            )
        }
        
        // Update images if provided
        if let images = images {
            // Remove old images
            await removeCharacterImages(character.referenceImages)
            
            // Save new images
            let imagePaths = try await saveCharacterImages(mangaId: mangaId, characterName: character.name, images: images)
            
            character = CharacterInfo(
                id: character.id,
                name: character.name,
                referenceImages: imagePaths,
                confidence: character.confidence,
                lastSeen: Date()
            )
        }
        
        // Update character bank
        var updatedCharacters = characterBank.characters
        updatedCharacters[characterIndex] = character
        
        let updatedBank = CharacterBank(
            mangaId: mangaId,
            characters: updatedCharacters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(updatedBank)
        
        LogManager.logger.info("Updated character '\(character.name)' in manga '\(mangaId)'")
    }
    
    func removeCharacter(mangaId: String, characterId: String) async throws {
        guard var characterBank = await getCharacterBank(mangaId: mangaId) else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        guard let characterIndex = characterBank.characters.firstIndex(where: { $0.id == characterId }) else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        let character = characterBank.characters[characterIndex]
        
        // Remove character images from disk
        await removeCharacterImages(character.referenceImages)
        
        // Remove from character bank
        var updatedCharacters = characterBank.characters
        updatedCharacters.remove(at: characterIndex)
        
        let updatedBank = CharacterBank(
            mangaId: mangaId,
            characters: updatedCharacters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(updatedBank)
        
        LogManager.logger.info("Removed character '\(character.name)' from manga '\(mangaId)'")
    }
    
    // MARK: - Import/Export
    
    func exportCharacterBank(mangaId: String) async throws -> Data {
        guard let characterBank = await getCharacterBank(mangaId: mangaId) else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        // Create export structure with embedded images
        var exportData: [String: Any] = [
            "mangaId": characterBank.mangaId,
            "lastUpdated": characterBank.lastUpdated.timeIntervalSince1970,
            "characters": []
        ]
        
        var charactersData: [[String: Any]] = []
        
        for character in characterBank.characters {
            var characterData: [String: Any] = [
                "id": character.id,
                "name": character.name,
                "confidence": character.confidence,
                "lastSeen": character.lastSeen.timeIntervalSince1970,
                "images": []
            ]
            
            // Load and encode images
            var imagesData: [String] = []
            for imagePath in character.referenceImages {
                if let imageData = await loadImageData(imagePath) {
                    imagesData.append(imageData.base64EncodedString())
                }
            }
            characterData["images"] = imagesData
            
            charactersData.append(characterData)
        }
        
        exportData["characters"] = charactersData
        
        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    func importCharacterBank(mangaId: String, data: Data) async throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        guard let charactersData = json["characters"] as? [[String: Any]] else {
            throw AIAnalysisError.characterBankCorrupted
        }
        
        var characters: [CharacterInfo] = []
        
        for characterData in charactersData {
            guard let id = characterData["id"] as? String,
                  let name = characterData["name"] as? String,
                  let confidence = characterData["confidence"] as? Float,
                  let lastSeenTimestamp = characterData["lastSeen"] as? TimeInterval,
                  let imagesData = characterData["images"] as? [String] else {
                continue
            }
            
            // Decode and save images
            var imagePaths: [String] = []
            for (index, imageBase64) in imagesData.enumerated() {
                if let imageData = Data(base64Encoded: imageBase64),
                   let image = UIImage(data: imageData) {
                    do {
                        let imagePath = try await saveCharacterImage(
                            mangaId: mangaId,
                            characterName: name,
                            image: image,
                            index: index
                        )
                        imagePaths.append(imagePath)
                    } catch {
                        LogManager.logger.error("Failed to save imported character image: \(error)")
                    }
                }
            }
            
            let character = CharacterInfo(
                id: id,
                name: name,
                referenceImages: imagePaths,
                confidence: confidence,
                lastSeen: Date(timeIntervalSince1970: lastSeenTimestamp)
            )
            
            characters.append(character)
        }
        
        let characterBank = CharacterBank(
            mangaId: mangaId,
            characters: characters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(characterBank)
        
        LogManager.logger.info("Imported character bank for manga '\(mangaId)' with \(characters.count) characters")
    }
    
    // MARK: - File Management
    
    private func characterBankDirectory(mangaId: String) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let characterBankDir = documentsDir
            .appendingPathComponent("AIAnalysis", isDirectory: true)
            .appendingPathComponent("CharacterBanks", isDirectory: true)
            .appendingPathComponent(mangaId, isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: characterBankDir, withIntermediateDirectories: true)
        
        return characterBankDir
    }
    
    private func saveCharacterImages(mangaId: String, characterName: String, images: [UIImage]) async throws -> [String] {
        let characterDir = characterBankDirectory(mangaId: mangaId)
            .appendingPathComponent(characterName.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        
        // Create character directory
        try FileManager.default.createDirectory(at: characterDir, withIntermediateDirectories: true)
        
        var imagePaths: [String] = []
        
        for (index, image) in images.enumerated() {
            let imagePath = try await saveCharacterImage(
                mangaId: mangaId,
                characterName: characterName,
                image: image,
                index: index
            )
            imagePaths.append(imagePath)
        }
        
        return imagePaths
    }
    
    private func saveCharacterImage(mangaId: String, characterName: String, image: UIImage, index: Int) async throws -> String {
        let characterDir = characterBankDirectory(mangaId: mangaId)
            .appendingPathComponent(characterName.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        
        // Create character directory
        try FileManager.default.createDirectory(at: characterDir, withIntermediateDirectories: true)
        
        let imageFileName = "reference_\(index).png"
        let imageURL = characterDir.appendingPathComponent(imageFileName)
        
        guard let pngData = image.pngData() else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        try pngData.write(to: imageURL)
        
        // Return relative path from documents directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = imageURL.path.replacingOccurrences(of: documentsDir.path + "/", with: "")
        
        return relativePath
    }
    
    private func removeCharacterImages(_ imagePaths: [String]) async {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        for imagePath in imagePaths {
            let imageURL = documentsDir.appendingPathComponent(imagePath)
            try? FileManager.default.removeItem(at: imageURL)
        }
    }
    
    private func loadImageData(_ imagePath: String) async -> Data? {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDir.appendingPathComponent(imagePath)
        
        return try? Data(contentsOf: imageURL)
    }
    
    // MARK: - Validation
    
    func validateCharacterBank(mangaId: String) async -> Bool {
        guard let characterBank = await getCharacterBank(mangaId: mangaId) else {
            return true // No character bank is valid
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        for character in characterBank.characters {
            for imagePath in character.referenceImages {
                let imageURL = documentsDir.appendingPathComponent(imagePath)
                if !FileManager.default.fileExists(atPath: imageURL.path) {
                    LogManager.logger.warn("Missing character image: \(imagePath)")
                    return false
                }
            }
        }
        
        return true
    }
    
    func repairCharacterBank(mangaId: String) async throws {
        guard var characterBank = await getCharacterBank(mangaId: mangaId) else {
            return
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var updatedCharacters: [CharacterInfo] = []
        
        for character in characterBank.characters {
            let validImagePaths = character.referenceImages.filter { imagePath in
                let imageURL = documentsDir.appendingPathComponent(imagePath)
                return FileManager.default.fileExists(atPath: imageURL.path)
            }
            
            // Only keep characters that have at least one valid image
            if !validImagePaths.isEmpty {
                let updatedCharacter = CharacterInfo(
                    id: character.id,
                    name: character.name,
                    referenceImages: validImagePaths,
                    confidence: character.confidence,
                    lastSeen: character.lastSeen
                )
                updatedCharacters.append(updatedCharacter)
            }
        }
        
        let repairedBank = CharacterBank(
            mangaId: mangaId,
            characters: updatedCharacters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(repairedBank)
        
        LogManager.logger.info("Repaired character bank for manga '\(mangaId)': \(characterBank.characters.count) -> \(updatedCharacters.count) characters")
    }
    
    // MARK: - Cleanup
    
    func removeCharacterBank(mangaId: String) async {
        // Remove from Core Data
        await coreDataManager.deleteCharacterBank(mangaId: mangaId)
        
        // Remove files from disk
        let characterBankDir = characterBankDirectory(mangaId: mangaId)
        try? FileManager.default.removeItem(at: characterBankDir)
        
        LogManager.logger.info("Removed character bank for manga '\(mangaId)'")
    }
}
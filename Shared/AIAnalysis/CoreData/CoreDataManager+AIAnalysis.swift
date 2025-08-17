//
//  CoreDataManager+AIAnalysis.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import CoreData

extension CoreDataManager {
    
    // MARK: - AI Analysis Results
    
    func saveAnalysisResult(_ result: AnalysisResult) async {
        await container.performBackgroundTask { context in
            // Check if analysis result already exists
            let fetchRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "mangaId == %@ AND chapterId == %@",
                result.mangaId,
                result.chapterId
            )
            
            let existingResult = try? context.fetch(fetchRequest).first
            let analysisObject = existingResult ?? AIAnalysisResultObject(context: context)
            
            // Update properties
            analysisObject.mangaId = result.mangaId
            analysisObject.chapterId = result.chapterId
            analysisObject.analysisDate = result.analysisDate
            analysisObject.version = result.version
            
            // Encode complex data as JSON
            if let pagesData = try? JSONEncoder().encode(result.pages) {
                analysisObject.pagesData = pagesData
            }
            
            if let transcriptData = try? JSONEncoder().encode(result.transcript) {
                analysisObject.transcriptData = transcriptData
            }
            
            if let audioSegments = result.audioSegments,
               let audioData = try? JSONEncoder().encode(audioSegments) {
                analysisObject.audioSegmentsData = audioData
            }
            
            // Link to chapter if it exists
            let chapterFetch: NSFetchRequest<ChapterObject> = ChapterObject.fetchRequest()
            chapterFetch.predicate = NSPredicate(
                format: "id == %@ AND mangaId == %@",
                result.chapterId,
                result.mangaId
            )
            
            if let chapter = try? context.fetch(chapterFetch).first {
                analysisObject.chapter = chapter
            }
            
            try? context.save()
        }
    }
    
    func getAnalysisResult(mangaId: String, chapterId: String) async -> AnalysisResult? {
        return await container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "mangaId == %@ AND chapterId == %@",
                mangaId,
                chapterId
            )
            
            guard let analysisObject = try? context.fetch(fetchRequest).first else {
                return nil
            }
            
            // Decode complex data
            var pages: [PageAnalysis] = []
            if let pagesData = analysisObject.pagesData {
                pages = (try? JSONDecoder().decode([PageAnalysis].self, from: pagesData)) ?? []
            }
            
            var transcript: [DialogueLine] = []
            if let transcriptData = analysisObject.transcriptData {
                transcript = (try? JSONDecoder().decode([DialogueLine].self, from: transcriptData)) ?? []
            }
            
            var audioSegments: [AudioSegment]?
            if let audioData = analysisObject.audioSegmentsData {
                audioSegments = try? JSONDecoder().decode([AudioSegment].self, from: audioData)
            }
            
            return AnalysisResult(
                mangaId: analysisObject.mangaId ?? "",
                chapterId: analysisObject.chapterId ?? "",
                pages: pages,
                transcript: transcript,
                audioSegments: audioSegments,
                analysisDate: analysisObject.analysisDate ?? Date(),
                version: analysisObject.version ?? "1.0"
            )
        }
    }
    
    func deleteAnalysisResult(mangaId: String, chapterId: String) async {
        await container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "mangaId == %@ AND chapterId == %@",
                mangaId,
                chapterId
            )
            
            if let analysisObject = try? context.fetch(fetchRequest).first {
                context.delete(analysisObject)
                try? context.save()
            }
        }
    }
    
    // MARK: - Character Banks
    
    func saveCharacterBank(_ characterBank: CharacterBank) async {
        await container.performBackgroundTask { context in
            // Check if character bank already exists
            let fetchRequest: NSFetchRequest<CharacterBankObject> = CharacterBankObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "mangaId == %@", characterBank.mangaId)
            
            let existingBank = try? context.fetch(fetchRequest).first
            let bankObject = existingBank ?? CharacterBankObject(context: context)
            
            // Update properties
            bankObject.mangaId = characterBank.mangaId
            bankObject.lastUpdated = characterBank.lastUpdated
            
            // Encode characters data
            if let charactersData = try? JSONEncoder().encode(characterBank.characters) {
                bankObject.charactersData = charactersData
            }
            
            // Link to manga if it exists
            let mangaFetch: NSFetchRequest<MangaObject> = MangaObject.fetchRequest()
            mangaFetch.predicate = NSPredicate(format: "id == %@", characterBank.mangaId)
            
            if let manga = try? context.fetch(mangaFetch).first {
                bankObject.manga = manga
            }
            
            try? context.save()
        }
    }
    
    func getCharacterBank(mangaId: String) async -> CharacterBank? {
        return await container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<CharacterBankObject> = CharacterBankObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "mangaId == %@", mangaId)
            
            guard let bankObject = try? context.fetch(fetchRequest).first else {
                return nil
            }
            
            // Decode characters data
            var characters: [CharacterInfo] = []
            if let charactersData = bankObject.charactersData {
                characters = (try? JSONDecoder().decode([CharacterInfo].self, from: charactersData)) ?? []
            }
            
            return CharacterBank(
                mangaId: bankObject.mangaId ?? "",
                characters: characters,
                lastUpdated: bankObject.lastUpdated ?? Date()
            )
        }
    }
    
    func deleteCharacterBank(mangaId: String) async {
        await container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<CharacterBankObject> = CharacterBankObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "mangaId == %@", mangaId)
            
            if let bankObject = try? context.fetch(fetchRequest).first {
                context.delete(bankObject)
                try? context.save()
            }
        }
    }
    
    // MARK: - Cache Management
    
    func getAnalysisCacheSize() async -> Int64 {
        return await container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            
            guard let results = try? context.fetch(fetchRequest) else {
                return 0
            }
            
            var totalSize: Int64 = 0
            for result in results {
                if let pagesData = result.pagesData {
                    totalSize += Int64(pagesData.count)
                }
                if let transcriptData = result.transcriptData {
                    totalSize += Int64(transcriptData.count)
                }
                if let audioData = result.audioSegmentsData {
                    totalSize += Int64(audioData.count)
                }
            }
            
            return totalSize
        }
    }
    
    func cleanupOldAnalysisResults(olderThan timeInterval: TimeInterval) async {
        await container.performBackgroundTask { context in
            let cutoffDate = Date().addingTimeInterval(-timeInterval)
            
            let fetchRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "analysisDate < %@", cutoffDate as NSDate)
            
            if let oldResults = try? context.fetch(fetchRequest) {
                for result in oldResults {
                    context.delete(result)
                }
                try? context.save()
            }
        }
    }
    
    func clearAllAnalysisCache() async {
        await container.performBackgroundTask { context in
            let analysisRequest: NSFetchRequest<AIAnalysisResultObject> = AIAnalysisResultObject.fetchRequest()
            let characterBankRequest: NSFetchRequest<CharacterBankObject> = CharacterBankObject.fetchRequest()
            
            if let analysisResults = try? context.fetch(analysisRequest) {
                for result in analysisResults {
                    context.delete(result)
                }
            }
            
            if let characterBanks = try? context.fetch(characterBankRequest) {
                for bank in characterBanks {
                    context.delete(bank)
                }
            }
            
            try? context.save()
        }
    }
}
//
//  AIAnalysisManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import UIKit
import ZIPFoundation
import CoreData
#if canImport(PDFKit)
import PDFKit
#endif

/// Central coordinator for all AI analysis operations with automatic processing
actor AIAnalysisManager {
    static let shared = AIAnalysisManager()
    
    private let colabClient = ColabAPIClient.shared
    private let characterBankManager = CharacterBankManager.shared
    private let cacheManager = AnalysisCacheManager.shared
    private let configManager = AIAnalysisConfigManager.shared
    private let coreDataManager = CoreDataManager.shared
    private let sessionManager = ColabSessionManager.shared
    
    // Active analysis jobs
    private var activeJobs: [String: AnalysisJob] = [:]
    
    // Progress tracking
    // NOTE: Using plain stored properties; @Published is not valid in an actor context.
    // If UI observation is needed in the future, expose async accessors/streams.
    private var analysisProgress: [String: Double] = [:] // mangaId:chapterId -> progress
    private var isAnalyzing: [String: Bool] = [:] // mangaId:chapterId -> isActive
    
    private init() {}
    
    // MARK: - Main Analysis Interface
    
    /// Automatically analyze a full chapter (works with all manga sources)
    func analyzeChapterAutomatically(mangaId: String, chapterId: String) async throws -> AnalysisResult {
        let cacheKey = "\(mangaId):\(chapterId)"
        
        // Check if already cached
        if let cachedResult = await cacheManager.getCachedResult(mangaId: mangaId, chapterId: chapterId) {
            LogManager.logger.info("Using cached analysis for \(cacheKey)")
            return cachedResult
        }
        
        // Check if analysis is already in progress
        if isAnalyzing[cacheKey] == true {
            throw AIAnalysisError.analysisInProgress
        }
        
        // Check if auto-analysis is enabled
        let autoAnalysisEnabled = await configManager.isAutoAnalysisEnabled
        if !autoAnalysisEnabled {
            throw AIAnalysisError.endpointNotConfigured
        }
        
        return try await analyzeFullChapter(mangaId: mangaId, chapterId: chapterId)
    }
    
    /// Manually analyze a full chapter (works with all manga sources)
    func analyzeFullChapter(mangaId: String, chapterId: String) async throws -> AnalysisResult {
        let cacheKey = "\(mangaId):\(chapterId)"
        
        // Validate configuration
        try await configManager.validateConfiguration()
        
        // Set analysis state
        isAnalyzing[cacheKey] = true
        analysisProgress[cacheKey] = 0.0
        
        defer {
            isAnalyzing[cacheKey] = false
            analysisProgress[cacheKey] = nil
        }
        
        do {
            LogManager.logger.info("Starting full chapter AI analysis for \(cacheKey)")
            
            // Step 1: Extract pages from chapter (10% progress)
            analysisProgress[cacheKey] = 0.1
            let pages = try await extractPagesFromChapter(mangaId: mangaId, chapterId: chapterId)
            
            // Step 2: Get character bank (20% progress)
            analysisProgress[cacheKey] = 0.2
            let characterBank = await characterBankManager.getCharacterBank(mangaId: mangaId)
            
            // Step 3: Start analysis job (30% progress)
            analysisProgress[cacheKey] = 0.3
            let jobId = try await colabClient.startAnalysis(pages: pages, characterBank: characterBank)
            
            // Step 4: Poll for completion (30-80% progress)
            let result = try await pollAnalysisCompletion(jobId: jobId, cacheKey: cacheKey)
            
            // Step 5: Cache result (90% progress)
            analysisProgress[cacheKey] = 0.9
            await cacheManager.cacheAnalysisResult(result, mangaId: mangaId, chapterId: chapterId)
            
            // Step 6: Complete (100% progress)
            analysisProgress[cacheKey] = 1.0
            
            LogManager.logger.info("Completed full chapter AI analysis for \(cacheKey)")
            return result
            
        } catch {
            LogManager.logger.error("Full chapter AI analysis failed for \(cacheKey): \(error)")
            throw error
        }
    }
    
    /// Automatically analyze a single page when user navigates to it
    func analyzePageAutomatically(mangaId: String, chapterId: String, pageIndex: Int) async throws -> PageAnalysis? {
        let cacheKey = "\(mangaId):\(chapterId)"
        
        // Check if full chapter analysis is cached
        if let cachedResult = await cacheManager.getCachedResult(mangaId: mangaId, chapterId: chapterId) {
            LogManager.logger.info("Using cached page analysis for \(cacheKey) page \(pageIndex)")
            return cachedResult.pages.first { $0.pageIndex == pageIndex }
        }
        
        // Check if auto-analysis is enabled
        let autoAnalysisEnabled = await configManager.isAutoAnalysisEnabled
        if !autoAnalysisEnabled {
            throw AIAnalysisError.endpointNotConfigured
        }
        
        return try await analyzeSinglePage(mangaId: mangaId, chapterId: chapterId, pageIndex: pageIndex)
    }
    
    /// Analyze a single page independently
    func analyzeSinglePage(mangaId: String, chapterId: String, pageIndex: Int) async throws -> PageAnalysis {
        let pageKey = "\(mangaId):\(chapterId):\(pageIndex)"
        
        // Check if this specific page is being analyzed
        if isAnalyzing[pageKey] == true {
            throw AIAnalysisError.analysisInProgress
        }
        
        // Validate configuration
        try await configManager.validateConfiguration()
        
        // Set analysis state
        isAnalyzing[pageKey] = true
        analysisProgress[pageKey] = 0.0
        
        defer {
            isAnalyzing[pageKey] = false
            analysisProgress[pageKey] = nil
        }
        
        do {
            LogManager.logger.info("Starting AI analysis for page \(pageIndex) of \(mangaId):\(chapterId)")
            
            // Step 1: Extract single page (20% progress)
            analysisProgress[pageKey] = 0.2
            let page = try await extractSinglePage(mangaId: mangaId, chapterId: chapterId, pageIndex: pageIndex)
            
            // Step 2: Get character bank (40% progress)
            analysisProgress[pageKey] = 0.4
            let characterBank = await characterBankManager.getCharacterBank(mangaId: mangaId)
            
            // Step 3: Start analysis job for single page (60% progress)
            analysisProgress[pageKey] = 0.6
            let jobId = try await colabClient.startSinglePageAnalysis(page: page, characterBank: characterBank)
            
            // Step 4: Poll for completion (60-90% progress)
            let pageAnalysis = try await pollSinglePageCompletion(jobId: jobId, pageKey: pageKey)
            
            // Step 5: Cache result (100% progress)
            analysisProgress[pageKey] = 1.0
            await cacheSinglePageResult(mangaId: mangaId, chapterId: chapterId, pageAnalysis: pageAnalysis)
            
            LogManager.logger.info("Completed AI analysis for page \(pageIndex) of \(mangaId):\(chapterId)")
            return pageAnalysis
            
        } catch {
            LogManager.logger.error("AI analysis failed for page \(pageIndex): \(error)")
            throw error
        }
    }
    
    /// Manually trigger analysis for a chapter
    func analyzeChapter(mangaId: String, chapterId: String) async throws -> AnalysisResult {
        let cacheKey = "\(mangaId):\(chapterId)"
        
        // Validate configuration
        try await configManager.validateConfiguration()
        
        // Set analysis state
        isAnalyzing[cacheKey] = true
        analysisProgress[cacheKey] = 0.0
        
        defer {
            isAnalyzing[cacheKey] = false
            analysisProgress[cacheKey] = nil
        }
        
        do {
            LogManager.logger.info("Starting AI analysis for \(cacheKey)")
            
            // Step 0: Ensure active Colab session (5% progress)
            analysisProgress[cacheKey] = 0.05
            try await sessionManager.ensureActiveSession()
            
            // Step 1: Extract pages from chapter (10% progress)
            analysisProgress[cacheKey] = 0.1
            let pages = try await extractPagesFromChapter(mangaId: mangaId, chapterId: chapterId)
            
            // Step 2: Get character bank (20% progress)
            analysisProgress[cacheKey] = 0.2
            let characterBank = await characterBankManager.getCharacterBank(mangaId: mangaId)
            
            // Step 3: Start analysis job (30% progress)
            analysisProgress[cacheKey] = 0.3
            let jobId = try await colabClient.startAnalysis(pages: pages, characterBank: characterBank)
            
            // Step 4: Poll for completion (30-80% progress)
            let result = try await pollAnalysisCompletion(jobId: jobId, cacheKey: cacheKey)
            
            // Step 5: Cache result (90% progress)
            analysisProgress[cacheKey] = 0.9
            await cacheManager.cacheAnalysisResult(result, mangaId: mangaId, chapterId: chapterId)
            
            // Step 6: Complete (100% progress)
            analysisProgress[cacheKey] = 1.0
            
            LogManager.logger.info("Completed AI analysis for \(cacheKey)")
            return result
            
        } catch {
            LogManager.logger.error("AI analysis failed for \(cacheKey): \(error)")
            throw error
        }
    }
    
    /// Get cached analysis result if available
    func getAnalysisResult(mangaId: String, chapterId: String) async -> AnalysisResult? {
        return await cacheManager.getCachedResult(mangaId: mangaId, chapterId: chapterId)
    }
    
    /// Generate audio for existing analysis result
    func generateAudio(mangaId: String, chapterId: String) async throws -> [AudioSegment] {
        let voiceSettings = await configManager.voiceSettings
        return try await generateAudioWithSettings(mangaId: mangaId, chapterId: chapterId, voiceSettings: voiceSettings)
    }
    
    /// Generate audio with custom voice settings
    func generateAudioWithSettings(mangaId: String, chapterId: String, voiceSettings: VoiceSettings) async throws -> [AudioSegment] {
        guard let analysisResult = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId) else {
            throw AIAnalysisError.jobNotFound
        }
        
        // Check if audio already exists with same settings (could implement settings hash comparison)
        if let existingAudio = analysisResult.audioSegments {
            return existingAudio
        }
        
        // Start audio generation job
        let jobId = try await colabClient.generateAudio(transcript: analysisResult.transcript, voiceSettings: voiceSettings)
        
        // Poll for completion
        let audioSegments = try await pollAudioCompletion(jobId: jobId)
        
        // Update cached result with audio
        let updatedResult = AnalysisResult(
            mangaId: analysisResult.mangaId,
            chapterId: analysisResult.chapterId,
            pages: analysisResult.pages,
            transcript: analysisResult.transcript,
            audioSegments: audioSegments,
            analysisDate: analysisResult.analysisDate,
            version: analysisResult.version
        )
        
        await cacheManager.cacheAnalysisResult(updatedResult, mangaId: mangaId, chapterId: chapterId)
        
        return audioSegments
    }
    
    /// Generate audio for a specific page with emotional context
    func generatePageAudio(mangaId: String, chapterId: String, pageIndex: Int, pageAnalysis: PageAnalysis) async throws -> [AudioSegment] {
        // Check if audio already exists for this page
        if let cachedResult = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId),
           let existingAudio = cachedResult.audioSegments {
            let pageAudio = existingAudio.filter { segment in
                let components = segment.dialogueId.split(separator: "_")
                return components.first == String(pageIndex)
            }
            if !pageAudio.isEmpty {
                return pageAudio
            }
        }
        
        // Create dialogue lines for this page
        let pageDialogue = createDialogueFromPageAnalysis(pageAnalysis, pageIndex: pageIndex)
        
        if pageDialogue.isEmpty {
            return [] // No dialogue on this page
        }
        
        let voiceSettings = await configManager.voiceSettings
        
        // Enhance voice settings with emotional context
        let enhancedVoiceSettings = await enhanceVoiceSettingsWithEmotion(
            voiceSettings: voiceSettings,
            dialogue: pageDialogue,
            pageAnalysis: pageAnalysis
        )
        
        // Start audio generation job for this page only
        let jobId = try await colabClient.generatePageAudio(
            dialogue: pageDialogue,
            voiceSettings: enhancedVoiceSettings
        )
        
        // Poll for completion
        let audioSegments = try await pollAudioCompletion(jobId: jobId)
        
        // Update cached result with new audio
        await updateCachedResultWithPageAudio(
            mangaId: mangaId,
            chapterId: chapterId,
            pageIndex: pageIndex,
            audioSegments: audioSegments,
            dialogue: pageDialogue
        )
        
        return audioSegments
    }
    
    /// Get audio for current page only (for reader integration)
    func getPageAudio(mangaId: String, chapterId: String, pageIndex: Int) async -> [AudioSegment] {
        guard let cachedResult = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId),
              let audioSegments = cachedResult.audioSegments else {
            return []
        }
        
        // Filter audio segments for current page
        return audioSegments.filter { segment in
            let components = segment.dialogueId.split(separator: "_")
            return components.first == String(pageIndex)
        }
    }
    
    // MARK: - Character Bank Management
    
    func updateCharacterBank(mangaId: String, characters: [CharacterInfo]) async {
        let characterBank = CharacterBank(
            mangaId: mangaId,
            characters: characters,
            lastUpdated: Date()
        )
        
        await coreDataManager.saveCharacterBank(characterBank)
        
        // Invalidate cached analyses for this manga since character bank changed
        await cacheManager.clearCache(mangaId: mangaId)
        
        LogManager.logger.info("Updated character bank for \(mangaId), cleared cached analyses")
    }
    
    // MARK: - Single Page Processing
    
    private func extractSinglePage(mangaId: String, chapterId: String, pageIndex: Int) async throws -> UIImage {
        // Try local (PDF/CBZ) first
        if let archivePath = await LocalFileDataManager.shared.fetchChapterArchivePath(mangaId: mangaId, chapterId: chapterId) {
            let documentsDir = FileManager.default.documentDirectory
            let fileURL = documentsDir.appendingPathComponent(archivePath)
            let fileExtension = fileURL.pathExtension.lowercased()
            
            if fileExtension == "pdf" {
                return try await extractSinglePageFromPDF(fileURL, pageIndex: pageIndex)
            } else if ["cbz", "zip"].contains(fileExtension) {
                return try await extractSinglePageFromArchive(fileURL, pageIndex: pageIndex)
            } else {
                throw AIAnalysisError.unsupportedFileFormat
            }
        }
        
        // Fallback to online source single-page extraction
        return try await extractSinglePageFromOnlineChapter(mangaId: mangaId, chapterId: chapterId, pageIndex: pageIndex)
    }
    
    private func extractSinglePageFromPDF(_ pdfURL: URL, pageIndex: Int) async throws -> UIImage {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: pdfURL) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        guard pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        // Render page at high resolution for better OCR
        let pageSize = page.bounds(for: .mediaBox).size
        let scale: CGFloat = 2.0 // 2x resolution
        let renderSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        
        let image = page.thumbnail(of: renderSize, for: .mediaBox)
        LogManager.logger.info("Extracted page \(pageIndex) from PDF")
        return image
        #else
        throw AIAnalysisError.unsupportedFileFormat
        #endif
    }
    
    private func extractSinglePageFromArchive(_ archiveURL: URL, pageIndex: Int) async throws -> UIImage {
        guard let archive = try? Archive(url: archiveURL, accessMode: .read) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        // Find image entries
        let imageEntries = archive
            .filter { entry in
                let ext = String(entry.path.lowercased().split(separator: ".").last ?? "")
                return LocalFileManager.allowedImageExtensions.contains(ext)
            }
            .sorted { $0.path < $1.path }
        
        guard pageIndex < imageEntries.count else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let entry = imageEntries[pageIndex]
        var imageData = Data()
        
        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
            
            guard let image = UIImage(data: imageData) else {
                throw AIAnalysisError.unsupportedFileFormat
            }
            
            LogManager.logger.info("Extracted page \(pageIndex) from archive")
            return image
        } catch {
            LogManager.logger.error("Failed to extract page \(pageIndex): \(error)")
            throw AIAnalysisError.unsupportedFileFormat
        }
    }
    
    private func extractSinglePageFromOnlineChapter(
        mangaId: String,
        chapterId: String,
        pageIndex: Int
    ) async throws -> UIImage {
        // Fetch manga and chapter to resolve source
        guard let manga = await getMangaObject(mangaId: mangaId),
              let chapter = await getChapterObject(mangaId: mangaId, chapterId: chapterId),
              let sourceId = manga.sourceId,
              let source = SourceManager.shared.sources.first(where: { $0.key == sourceId }) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        // Convert to runner types
        let runnerManga = manga.toAidokuManga()
        let runnerChapter = chapter.toAidokuChapter()
        
        // Get page list and download only the requested page
        let pages = try await source.getPageList(manga: runnerManga, chapter: runnerChapter)
        guard pageIndex >= 0, pageIndex < pages.count else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let page = pages[pageIndex]
        if let image = await self.downloadPageImage(page, source: source) {
            return image
        }
        throw AIAnalysisError.unsupportedFileFormat
    }
    
    private func createDialogueFromPageAnalysis(_ pageAnalysis: PageAnalysis, pageIndex: Int) -> [DialogueLine] {
        var dialogue: [DialogueLine] = []
        
        for textRegion in pageAnalysis.textRegions where textRegion.isEssential {
            // Determine speaker from character associations
            let speaker = pageAnalysis.textCharacterAssociations[textRegion.id]
                .flatMap { charId in
                    pageAnalysis.characterDetections.first { $0.id == charId }?.name
                } ?? "unknown"
            
            let dialogueLine = DialogueLine(
                pageIndex: pageIndex,
                textId: textRegion.id,
                speaker: speaker,
                text: textRegion.text,
                timestamp: nil
            )
            
            dialogue.append(dialogueLine)
        }
        
        return dialogue
    }
    
    private func enhanceVoiceSettingsWithEmotion(
        voiceSettings: VoiceSettings,
        dialogue: [DialogueLine],
        pageAnalysis: PageAnalysis
    ) async -> VoiceSettings {
        // Analyze text for emotional context
        var enhancedCharacterVoices: [String: String] = [:]
        
        for dialogueLine in dialogue {
            let emotion = detectEmotion(in: dialogueLine.text)
            let baseVoice = voiceSettings.characterVoiceFiles[dialogueLine.speaker] ?? voiceSettings.defaultVoiceFile
            
            // Create emotional variant if XTTS-v2 supports it
            let emotionalVoice = createEmotionalVoiceVariant(baseVoice: baseVoice, emotion: emotion)
            enhancedCharacterVoices[dialogueLine.speaker] = emotionalVoice
        }
        
        return VoiceSettings(
            language: voiceSettings.language,
            defaultVoiceFile: voiceSettings.defaultVoiceFile,
            characterVoiceFiles: enhancedCharacterVoices
        )
    }
    
    private func detectEmotion(in text: String) -> EmotionalContext {
        let lowercaseText = text.lowercased()
        
        // Simple emotion detection based on text patterns
        if lowercaseText.contains("!") || lowercaseText.contains("!!") {
            if lowercaseText.contains("no") || lowercaseText.contains("stop") || lowercaseText.contains("wait") {
                return .angry
            } else {
                return .excited
            }
        } else if lowercaseText.contains("?") {
            return .questioning
        } else if lowercaseText.contains("...") || lowercaseText.contains("..") {
            return .sad
        } else if lowercaseText.contains("haha") || lowercaseText.contains("hehe") {
            return .happy
        } else {
            return .neutral
        }
    }
    
    private func createEmotionalVoiceVariant(baseVoice: String?, emotion: EmotionalContext) -> String? {
        // For now, return base voice. In future, could modify voice parameters
        // based on emotion if XTTS-v2 supports it through additional parameters
        return baseVoice
    }
    
    private func cacheSinglePageResult(mangaId: String, chapterId: String, pageAnalysis: PageAnalysis) async {
        // Get existing cached result or create new one
        var cachedResult = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId)
        
        if cachedResult == nil {
            // Create new result with this page
            cachedResult = AnalysisResult(
                mangaId: mangaId,
                chapterId: chapterId,
                pages: [pageAnalysis],
                transcript: createDialogueFromPageAnalysis(pageAnalysis, pageIndex: pageAnalysis.pageIndex),
                audioSegments: nil,
                analysisDate: Date(),
                version: "1.0"
            )
        } else {
            // Update existing result with new page
            var updatedPages = cachedResult!.pages
            
            // Remove existing page analysis if present
            updatedPages.removeAll { $0.pageIndex == pageAnalysis.pageIndex }
            updatedPages.append(pageAnalysis)
            updatedPages.sort { $0.pageIndex < $1.pageIndex }
            
            // Update transcript
            var updatedTranscript = cachedResult!.transcript
            updatedTranscript.removeAll { $0.pageIndex == pageAnalysis.pageIndex }
            updatedTranscript.append(contentsOf: createDialogueFromPageAnalysis(pageAnalysis, pageIndex: pageAnalysis.pageIndex))
            updatedTranscript.sort { $0.pageIndex < $1.pageIndex || ($0.pageIndex == $1.pageIndex && $0.textId < $1.textId) }
            
            cachedResult = AnalysisResult(
                mangaId: cachedResult!.mangaId,
                chapterId: cachedResult!.chapterId,
                pages: updatedPages,
                transcript: updatedTranscript,
                audioSegments: cachedResult!.audioSegments,
                analysisDate: cachedResult!.analysisDate,
                version: cachedResult!.version
            )
        }
        
        await cacheManager.cacheAnalysisResult(cachedResult!, mangaId: mangaId, chapterId: chapterId)
    }
    
    private func updateCachedResultWithPageAudio(
        mangaId: String,
        chapterId: String,
        pageIndex: Int,
        audioSegments: [AudioSegment],
        dialogue: [DialogueLine]
    ) async {
        guard var cachedResult = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId) else {
            return
        }
        
        // Update audio segments
        var updatedAudioSegments = cachedResult.audioSegments ?? []
        
        // Remove existing audio for this page
        updatedAudioSegments.removeAll { segment in
            let components = segment.dialogueId.split(separator: "_")
            return components.first == String(pageIndex)
        }
        
        // Add new audio segments
        updatedAudioSegments.append(contentsOf: audioSegments)
        updatedAudioSegments.sort { $0.dialogueId < $1.dialogueId }
        
        let updatedResult = AnalysisResult(
            mangaId: cachedResult.mangaId,
            chapterId: cachedResult.chapterId,
            pages: cachedResult.pages,
            transcript: cachedResult.transcript,
            audioSegments: updatedAudioSegments,
            analysisDate: cachedResult.analysisDate,
            version: cachedResult.version
        )
        
        await cacheManager.cacheAnalysisResult(updatedResult, mangaId: mangaId, chapterId: chapterId)
    }
    
    private func pollSinglePageCompletion(jobId: String, pageKey: String) async throws -> PageAnalysis {
        let maxAttempts = 30 // 2.5 minutes with 5-second intervals
        let pollInterval: TimeInterval = 5.0
        
        for attempt in 0..<maxAttempts {
            let response = try await colabClient.getAnalysisStatus(jobId: jobId)
            
            // Update progress (60% + 30% of analysis progress)
            let analysisProgress = 0.6 + (response.progress * 0.3)
            self.analysisProgress[pageKey] = analysisProgress
            
            switch response.status {
            case "completed":
                if let result = response.result, let pageAnalysis = result.pages.first {
                    return pageAnalysis
                } else {
                    // Fetch result separately and get first page
                    let result = try await colabClient.getAnalysisResult(jobId: jobId)
                    guard let pageAnalysis = result.pages.first else {
                        throw AIAnalysisError.invalidResponse
                    }
                    return pageAnalysis
                }
                
            case "failed":
                let errorMessage = response.error ?? "Unknown analysis error"
                LogManager.logger.error("Page analysis job failed: \(errorMessage)")
                throw AIAnalysisError.invalidResponse
                
            case "processing", "pending":
                // Continue polling
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                
            default:
                LogManager.logger.warn("Unknown analysis status: \(response.status)")
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
        
        throw AIAnalysisError.analysisTimeout
    }

    // MARK: - Page Extraction
    
    private func extractPagesFromChapter(mangaId: String, chapterId: String) async throws -> [UIImage] {
        // First, try to get the source and chapter information
        guard let manga = await getMangaObject(mangaId: mangaId),
              let chapter = await getChapterObject(mangaId: mangaId, chapterId: chapterId) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let sourceId = manga.sourceId ?? ""
        
        // Handle different source types
        if sourceId == LocalSourceRunner.sourceKey {
            // Local files (PDF/CBZ)
            return try await extractPagesFromLocalChapter(mangaId: mangaId, chapterId: chapterId)
        } else {
            // Online sources
            return try await extractPagesFromOnlineChapter(sourceId: sourceId, manga: manga, chapter: chapter)
        }
    }
    
    private func extractPagesFromLocalChapter(mangaId: String, chapterId: String) async throws -> [UIImage] {
        // Get chapter file path from LocalFileDataManager
        guard let archivePath = await LocalFileDataManager.shared.fetchChapterArchivePath(mangaId: mangaId, chapterId: chapterId) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let documentsDir = FileManager.default.documentDirectory
        let fileURL = documentsDir.appendingPathComponent(archivePath)
        let fileExtension = fileURL.pathExtension.lowercased()
        
        if fileExtension == "pdf" {
            return try await extractPagesFromPDF(fileURL)
        } else if ["cbz", "zip"].contains(fileExtension) {
            return try await extractPagesFromArchive(fileURL)
        } else {
            throw AIAnalysisError.unsupportedFileFormat
        }
    }
    
    private func extractPagesFromOnlineChapter(sourceId: String, manga: MangaObject, chapter: ChapterObject) async throws -> [UIImage] {
        // Get the source
        guard let source = SourceManager.shared.sources.first(where: { $0.key == sourceId }) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        // Convert to AidokuRunner types
        let runnerManga = manga.toAidokuManga()
        let runnerChapter = chapter.toAidokuChapter()
        
        // Get pages from the source
        let pages = try await source.getPageList(manga: runnerManga, chapter: runnerChapter)
        
        // Download and convert pages to UIImages
        return try await downloadPagesAsImages(pages, source: source)
    }
    
    private func extractPagesFromPDF(_ pdfURL: URL) async throws -> [UIImage] {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: pdfURL) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let pageCount = document.pageCount
        var pages: [UIImage] = []
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Render page at high resolution for better OCR
            let pageSize = page.bounds(for: .mediaBox).size
            let scale: CGFloat = 2.0 // 2x resolution
            let renderSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
            
            let image = page.thumbnail(of: renderSize, for: .mediaBox)
            pages.append(image)
        }
        
        LogManager.logger.info("Extracted \(pages.count) pages from PDF")
        return pages
        #else
        throw AIAnalysisError.unsupportedFileFormat
        #endif
    }
    
    private func extractPagesFromArchive(_ archiveURL: URL) async throws -> [UIImage] {
        // This would use the existing ZIP extraction logic from LocalFileManager
        // For now, we'll implement a simplified version
        
        guard let archive = try? Archive(url: archiveURL, accessMode: .read) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        // Find image entries
        let imageEntries = archive
            .filter { entry in
                let ext = String(entry.path.lowercased().split(separator: ".").last ?? "")
                return LocalFileManager.allowedImageExtensions.contains(ext)
            }
            .sorted { $0.path < $1.path }
        
        var pages: [UIImage] = []
        
        for entry in imageEntries {
            var imageData = Data()
            do {
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
                
                if let image = UIImage(data: imageData) {
                    pages.append(image)
                }
            } catch {
                LogManager.logger.warn("Failed to extract image \(entry.path): \(error)")
            }
        }
        
        LogManager.logger.info("Extracted \(pages.count) pages from archive")
        return pages
    }
    
    // MARK: - Job Polling
    
    private func pollAnalysisCompletion(jobId: String, cacheKey: String) async throws -> AnalysisResult {
        let maxAttempts = 60 // 5 minutes with 5-second intervals
        let pollInterval: TimeInterval = 5.0
        
        for attempt in 0..<maxAttempts {
            let response = try await colabClient.getAnalysisStatus(jobId: jobId)
            
            // Update progress (30% + 50% of analysis progress)
            let analysisProgress = 0.3 + (response.progress * 0.5)
            self.analysisProgress[cacheKey] = analysisProgress
            
            switch response.status {
            case "completed":
                if let result = response.result {
                    return result
                } else {
                    // Fetch result separately
                    return try await colabClient.getAnalysisResult(jobId: jobId)
                }
                
            case "failed":
                let errorMessage = response.error ?? "Unknown analysis error"
                LogManager.logger.error("Analysis job failed: \(errorMessage)")
                throw AIAnalysisError.invalidResponse
                
            case "processing", "pending":
                // Continue polling
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                
            default:
                LogManager.logger.warn("Unknown analysis status: \(response.status)")
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
        
        throw AIAnalysisError.analysisTimeout
    }
    
    private func pollAudioCompletion(jobId: String) async throws -> [AudioSegment] {
        let maxAttempts = 30 // 2.5 minutes with 5-second intervals
        let pollInterval: TimeInterval = 5.0
        
        for _ in 0..<maxAttempts {
            let audioSegments = try await colabClient.getAudioResult(jobId: jobId)
            return audioSegments
        }
        
        throw AIAnalysisError.audioGenerationFailed
    }
    
    // MARK: - Batch Operations
    
    /// Analyze multiple chapters in batch
    func analyzeMangaBatch(mangaId: String, chapterIds: [String]) async throws -> [String: AnalysisResult] {
        var results: [String: AnalysisResult] = [:]
        
        // Process chapters concurrently but limit concurrency
        let maxConcurrentAnalyses = 3
        
        for chapterBatch in chapterIds.chunked(into: maxConcurrentAnalyses) {
            try await withThrowingTaskGroup(of: (String, AnalysisResult).self) { group in
                for chapterId in chapterBatch {
                    group.addTask {
                        let result = try await self.analyzeChapter(mangaId: mangaId, chapterId: chapterId)
                        return (chapterId, result)
                    }
                }
                
                for try await (chapterId, result) in group {
                    results[chapterId] = result
                }
            }
        }
        
        return results
    }
    
    // MARK: - Preparation (Bootstrap first N pages)
    
    /// Ensure at least `minimumPages` pages are analyzed (and optionally have audio) before reading starts.
    /// Returns when the cache contains analyses for at least the requested number of pages.
    func prepareFirstPages(
        mangaId: String,
        chapterId: String,
        minimumPages: Int,
        generateAudio: Bool,
        progress: ((Int, Int) -> Void)? = nil
    ) async {
        let target = max(0, minimumPages)
        guard target > 0 else { return }

        // Helper to compute pages prepared (analysis + audio) among [0..maxIndex]
        func computePreparedCount(maxIndex: Int) async -> Int {
            guard let result = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId) else { return 0 }
            let analyzed = Set(result.pages.map { $0.pageIndex }.filter { $0 >= 0 && $0 <= maxIndex })
            let audioPages: Set<Int> = {
                guard let segments = result.audioSegments else { return [] }
                let indices: [Int] = segments.compactMap { seg in
                    let first = seg.dialogueId.split(separator: "_").first
                    return first.flatMap { Int($0) }
                }
                return Set(indices.filter { $0 >= 0 && $0 <= maxIndex })
            }()
            let required = Set(0...maxIndex)
            let ready = required.intersection(analyzed).intersection(audioPages)
            return ready.count
        }

        // Short-circuit if already satisfied
        let maxIndex = target - 1
        var preparedCount = await computePreparedCount(maxIndex: maxIndex)
        if preparedCount >= target { progress?(preparedCount, target); return }

        // Attempt sequential bootstrap of the first N pages (small, avoids concurrency thrash)
        var pageIndex = 0
        while preparedCount < target && pageIndex <= maxIndex {
            do {
                // Skip if we already have this page
                if let cached = await getAnalysisResult(mangaId: mangaId, chapterId: chapterId),
                   cached.pages.contains(where: { $0.pageIndex == pageIndex }) {
                    preparedCount = await computePreparedCount(maxIndex: maxIndex)
                    progress?(min(preparedCount, target), target)
                    pageIndex += 1
                    continue
                }

                // Analyze single page (works for local and online sources)
                let pageAnalysis = try await analyzeSinglePage(
                    mangaId: mangaId,
                    chapterId: chapterId,
                    pageIndex: pageIndex
                )

                // Optionally generate audio for this page
                if generateAudio {
                    _ = try? await generatePageAudio(
                        mangaId: mangaId,
                        chapterId: chapterId,
                        pageIndex: pageIndex,
                        pageAnalysis: pageAnalysis
                    )
                }
            } catch {
                // If a page is in progress elsewhere or fails, move on to next index
                // This keeps UI unblocked and still reaches the target as best effort
            }

            // Update prepared count from cache
            preparedCount = await computePreparedCount(maxIndex: maxIndex)
            progress?(min(preparedCount, target), target)
            pageIndex += 1
        }
    }
    
    // MARK: - Health Check
    
    func checkServiceHealth() async throws -> ColabHealthResponse {
        return try await colabClient.healthCheck()
    }
    
    // MARK: - Progress Tracking
    
    func getAnalysisProgress(mangaId: String, chapterId: String) -> Double? {
        let cacheKey = "\(mangaId):\(chapterId)"
        return analysisProgress[cacheKey]
    }
    
    func isAnalysisInProgress(mangaId: String, chapterId: String) -> Bool {
        let cacheKey = "\(mangaId):\(chapterId)"
        return isAnalyzing[cacheKey] ?? false
    }
    
    // MARK: - Helper Methods for Online Sources
    
    private func getMangaObject(mangaId: String) async -> MangaObject? {
        return await coreDataManager.container.performBackgroundTask { context in
            let request: NSFetchRequest<MangaObject> = MangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", mangaId)
            request.fetchLimit = 1
            
            return try? context.fetch(request).first
        }
    }
    
    private func getChapterObject(mangaId: String, chapterId: String) async -> ChapterObject? {
        return await coreDataManager.container.performBackgroundTask { context in
            let request: NSFetchRequest<ChapterObject> = ChapterObject.fetchRequest()
            request.predicate = NSPredicate(format: "mangaId == %@ AND id == %@", mangaId, chapterId)
            request.fetchLimit = 1
            
            return try? context.fetch(request).first
        }
    }
    
    private func downloadPagesAsImages(_ pages: [AidokuRunner.Page], source: AidokuRunner.Source) async throws -> [UIImage] {
        var images: [UIImage] = []
        
        // Process pages in batches to avoid overwhelming the server
        let batchSize = 5
        let batches = pages.chunked(into: batchSize)
        
        for batch in batches {
            let batchImages = try await withThrowingTaskGroup(of: UIImage?.self) { group in
                for page in batch {
                    group.addTask {
                        return await self.downloadPageImage(page, source: source)
                    }
                }
                
                var results: [UIImage] = []
                for try await image in group {
                    if let image = image {
                        results.append(image)
                    }
                }
                return results
            }
            
            images.append(contentsOf: batchImages)
            
            // Add small delay between batches to be respectful to servers
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        LogManager.logger.info("Downloaded \(images.count) pages from online source")
        return images
    }
    
    private func downloadPageImage(_ page: AidokuRunner.Page, source: AidokuRunner.Source) async -> UIImage? {
        do {
            switch page.content {
            case .url(let url):
                // Download image from URL
                let (data, _) = try await URLSession.shared.data(from: url)
                return UIImage(data: data)
                
            case .base64(let base64String):
                // Decode base64 image
                guard let data = Data(base64Encoded: base64String) else { return nil }
                return UIImage(data: data)
                
            case .zipFile(let zipURL, let filePath):
                // Extract from ZIP file (similar to local handling)
                return extractImageFromZip(zipURL: zipURL, filePath: filePath)
                
            case .data(let data):
                // Direct image data
                return UIImage(data: data)
                
            @unknown default:
                LogManager.logger.warn("Unknown page content type")
                return nil
            }
        } catch {
            LogManager.logger.error("Failed to download page image: \(error)")
            return nil
        }
    }
    
    private func extractImageFromZip(zipURL: URL, filePath: String) -> UIImage? {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            guard let entry = archive[filePath] else { return nil }
            
            var imageData = Data()
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
            
            return UIImage(data: imageData)
        } catch {
            LogManager.logger.error("Failed to extract image from zip: \(error)")
            return nil
        }
    }
}

// MARK: - Analysis Job Model

private struct AnalysisJob {
    let id: String
    let mangaId: String
    let chapterId: String
    let startTime: Date
    var progress: Double
    var status: String
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
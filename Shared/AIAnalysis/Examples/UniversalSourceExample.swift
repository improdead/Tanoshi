//
//  UniversalSourceExample.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Universal Source Support Example
//

import Foundation
import SwiftUI

/// Example showing how AI analysis works with all manga sources
@MainActor
class UniversalSourceExample: ObservableObject {
    @Published var analysisResults: [String: AnalysisResult] = [:]
    @Published var analysisProgress: [String: Double] = [:]
    @Published var isAnalyzing: [String: Bool] = [:]
    
    private let aiManager = AIAnalysisManager.shared
    
    // MARK: - Universal Analysis Examples
    
    /// Analyze a local PDF manga
    func analyzeLocalPDFManga() async {
        let mangaId = "local_one_piece"
        let chapterId = "chapter_1001"
        
        await analyzeChapter(
            mangaId: mangaId,
            chapterId: chapterId,
            description: "Local PDF: One Piece Chapter 1001"
        )
    }
    
    /// Analyze an online manga from MangaDex
    func analyzeOnlineManga() async {
        let mangaId = "mangadex_naruto_123"
        let chapterId = "chapter_700"
        
        await analyzeChapter(
            mangaId: mangaId,
            chapterId: chapterId,
            description: "Online: Naruto Chapter 700 from MangaDex"
        )
    }
    
    /// Analyze manga from Komga server
    func analyzeKomgaManga() async {
        let mangaId = "komga_attack_on_titan"
        let chapterId = "chapter_139"
        
        await analyzeChapter(
            mangaId: mangaId,
            chapterId: chapterId,
            description: "Komga Server: Attack on Titan Chapter 139"
        )
    }
    
    /// Analyze manga from any custom source
    func analyzeCustomSourceManga() async {
        let mangaId = "custom_demon_slayer"
        let chapterId = "chapter_205"
        
        await analyzeChapter(
            mangaId: mangaId,
            chapterId: chapterId,
            description: "Custom Source: Demon Slayer Chapter 205"
        )
    }
    
    // MARK: - Universal Analysis Method
    
    private func analyzeChapter(mangaId: String, chapterId: String, description: String) async {
        let cacheKey = "\(mangaId):\(chapterId)"
        
        isAnalyzing[cacheKey] = true
        analysisProgress[cacheKey] = 0.0
        
        do {
            LogManager.logger.info("Starting analysis: \(description)")
            
            // The AI manager automatically detects source type and handles appropriately
            let result = try await aiManager.analyzeChapterAutomatically(mangaId: mangaId, chapterId: chapterId)
            
            analysisResults[cacheKey] = result
            analysisProgress[cacheKey] = 1.0
            
            LogManager.logger.info("Completed analysis: \(description)")
            LogManager.logger.info("Found \(result.transcript.count) dialogue lines")
            
        } catch {
            LogManager.logger.error("Failed to analyze \(description): \(error)")
            analysisProgress[cacheKey] = 0.0
        }
        
        isAnalyzing[cacheKey] = false
    }
    
    // MARK: - Batch Analysis
    
    /// Analyze multiple chapters from different sources simultaneously
    func analyzeMixedSources() async {
        let chapters = [
            ("local_manga_1", "chapter_1", "Local PDF Chapter"),
            ("online_manga_2", "chapter_5", "Online Manga Chapter"),
            ("komga_manga_3", "chapter_10", "Komga Server Chapter")
        ]
        
        await withTaskGroup(of: Void.self) { group in
            for (mangaId, chapterId, description) in chapters {
                group.addTask {
                    await self.analyzeChapter(mangaId: mangaId, chapterId: chapterId, description: description)
                }
            }
        }
        
        LogManager.logger.info("Completed batch analysis of mixed sources")
    }
    
    // MARK: - Source Type Detection Example
    
    func demonstrateSourceDetection() async {
        // The system automatically detects and handles different source types:
        
        // 1. Local PDF files
        // - Extracts pages using PDFKit
        // - Processes directly from file system
        
        // 2. Online manga sources
        // - Downloads images from URLs
        // - Handles rate limiting and retries
        // - Supports various image formats
        
        // 3. Archive files (CBZ, ZIP)
        // - Extracts images from compressed archives
        // - Maintains page order
        
        // 4. API-based sources (Komga, etc.)
        // - Fetches pages through API calls
        // - Handles authentication if needed
        
        // 5. Base64 encoded images
        // - Decodes embedded image data
        // - Processes in-memory images
        
        LogManager.logger.info("AI Analysis supports all these source types automatically!")
    }
}

// MARK: - SwiftUI Example View

struct UniversalSourceAnalysisView: View {
    @StateObject private var example = UniversalSourceExample()
    
    var body: some View {
        NavigationView {
            List {
                Section("Source Type Examples") {
                    AnalysisButton(
                        title: "Local PDF Manga",
                        description: "Analyze local PDF file",
                        action: { await example.analyzeLocalPDFManga() }
                    )
                    
                    AnalysisButton(
                        title: "Online Manga",
                        description: "Analyze from manga website",
                        action: { await example.analyzeOnlineManga() }
                    )
                    
                    AnalysisButton(
                        title: "Komga Server",
                        description: "Analyze from Komga server",
                        action: { await example.analyzeKomgaManga() }
                    )
                    
                    AnalysisButton(
                        title: "Custom Source",
                        description: "Analyze from custom source",
                        action: { await example.analyzeCustomSourceManga() }
                    )
                }
                
                Section("Batch Operations") {
                    AnalysisButton(
                        title: "Mixed Sources Batch",
                        description: "Analyze multiple sources simultaneously",
                        action: { await example.analyzeMixedSources() }
                    )
                }
                
                Section("Analysis Results") {
                    ForEach(Array(example.analysisResults.keys), id: \.self) { key in
                        AnalysisResultRow(
                            key: key,
                            result: example.analysisResults[key]!,
                            progress: example.analysisProgress[key] ?? 0.0,
                            isAnalyzing: example.isAnalyzing[key] ?? false
                        )
                    }
                }
            }
            .navigationTitle("Universal AI Analysis")
            .onAppear {
                Task {
                    await example.demonstrateSourceDetection()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct AnalysisButton: View {
    let title: String
    let description: String
    let action: () async -> Void
    
    var body: some View {
        Button(action: { Task { await action() } }) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AnalysisResultRow: View {
    let key: String
    let result: AnalysisResult
    let progress: Double
    let isAnalyzing: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(key)
                .font(.headline)
            
            if isAnalyzing {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Analyzing... \(Int(progress * 100))%")
                    .font(.caption)
            } else {
                Text("\(result.transcript.count) dialogue lines found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let audioSegments = result.audioSegments {
                    Text("\(audioSegments.count) audio segments generated")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Integration Examples

extension UniversalSourceExample {
    
    /// Example: Integrate with existing manga reader for any source
    func integrateWithReader(mangaId: String, chapterId: String) async {
        // This works regardless of source type:
        // - Local PDF files
        // - Online manga websites  
        // - Komga servers
        // - Custom APIs
        // - Any other supported source
        
        do {
            let result = try await aiManager.analyzeChapterAutomatically(mangaId: mangaId, chapterId: chapterId)
            
            // Use the analysis result for:
            // - Text overlay on manga pages
            // - Character identification
            // - Audio narration with character voices
            // - Auto page turning synchronized with audio
            
            LogManager.logger.info("Analysis ready for reader integration")
            
        } catch {
            LogManager.logger.error("Analysis failed: \(error)")
        }
    }
    
    /// Example: Handle different page formats automatically
    func handleMixedPageFormats() async {
        // The system automatically handles:
        // - JPEG images from online sources
        // - PNG images from local files
        // - WebP images from modern websites
        // - Base64 encoded images from APIs
        // - PDF pages rendered as images
        // - Images extracted from ZIP/CBZ archives
        
        LogManager.logger.info("All page formats supported automatically!")
    }
}
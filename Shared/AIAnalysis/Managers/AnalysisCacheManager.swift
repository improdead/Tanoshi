//
//  AnalysisCacheManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import CryptoKit

/// Manages local storage and retrieval of analysis results with LRU eviction
actor AnalysisCacheManager {
    static let shared = AnalysisCacheManager()
    
    private let coreDataManager = CoreDataManager.shared
    private let configManager = AIAnalysisConfigManager.shared
    
    // LRU tracking
    private var accessOrder: [String] = [] // Keys in access order (most recent last)
    private let maxCacheEntries = 100 // Maximum number of cached analyses
    
    private init() {
        Task {
            await loadAccessOrder()
        }
    }
    
    // MARK: - Cache Operations
    
    func cacheAnalysisResult(_ result: AnalysisResult, mangaId: String, chapterId: String) async {
        // Create result with proper IDs
        let resultWithIds = AnalysisResult(
            mangaId: mangaId,
            chapterId: chapterId,
            pages: result.pages,
            transcript: result.transcript,
            audioSegments: result.audioSegments,
            analysisDate: result.analysisDate,
            version: result.version
        )
        
        // Encrypt sensitive data if needed
        let encryptedResult = await encryptAnalysisResult(resultWithIds)
        
        // Save to Core Data
        await coreDataManager.saveAnalysisResult(encryptedResult)
        
        // Update LRU order
        let cacheKey = "\(mangaId):\(chapterId)"
        updateAccessOrder(cacheKey)
        
        // Check cache size and evict if necessary
        await enforceCacheLimits()
        
        LogManager.logger.info("Cached analysis result for \(mangaId):\(chapterId)")
    }
    
    func getCachedResult(mangaId: String, chapterId: String) async -> AnalysisResult? {
        guard let encryptedResult = await coreDataManager.getAnalysisResult(mangaId: mangaId, chapterId: chapterId) else {
            return nil
        }
        
        // Update LRU order
        let cacheKey = "\(mangaId):\(chapterId)"
        updateAccessOrder(cacheKey)
        
        // Decrypt result if needed
        let result = await decryptAnalysisResult(encryptedResult)
        
        LogManager.logger.info("Retrieved cached analysis result for \(mangaId):\(chapterId)")
        return result
    }
    
    func clearCache(mangaId: String) async {
        // Remove all analysis results for the manga
        let allResults = await getAllCachedResults()
        
        for result in allResults where result.mangaId == mangaId {
            await coreDataManager.deleteAnalysisResult(mangaId: result.mangaId, chapterId: result.chapterId)
            
            let cacheKey = "\(result.mangaId):\(result.chapterId)"
            accessOrder.removeAll { $0 == cacheKey }
        }
        
        await saveAccessOrder()
        
        LogManager.logger.info("Cleared cache for manga: \(mangaId)")
    }
    
    func getCacheSize() async -> Int64 {
        return await coreDataManager.getAnalysisCacheSize()
    }
    
    func cleanupOldCache(olderThan timeInterval: TimeInterval) async {
        await coreDataManager.cleanupOldAnalysisResults(olderThan: timeInterval)
        
        // Update access order by removing deleted entries
        let remainingResults = await getAllCachedResults()
        let remainingKeys = Set(remainingResults.map { "\($0.mangaId):\($0.chapterId)" })
        
        accessOrder = accessOrder.filter { remainingKeys.contains($0) }
        await saveAccessOrder()
        
        LogManager.logger.info("Cleaned up cache entries older than \(timeInterval) seconds")
    }
    
    func clearAllCache() async {
        await coreDataManager.clearAllAnalysisCache()
        accessOrder.removeAll()
        await saveAccessOrder()
        
        LogManager.logger.info("Cleared all analysis cache")
    }
    
    // MARK: - Cache Management
    
    private func enforceCacheLimits() async {
        let maxSize = await configManager.cacheMaxSize
        let currentSize = await getCacheSize()
        
        // Check size limit
        if currentSize > maxSize {
            await evictLeastRecentlyUsed(targetSize: maxSize * 8 / 10) // Evict to 80% of max size
        }
        
        // Check entry count limit
        if accessOrder.count > maxCacheEntries {
            let entriesToRemove = accessOrder.count - maxCacheEntries
            await evictOldestEntries(count: entriesToRemove)
        }
    }
    
    private func evictLeastRecentlyUsed(targetSize: Int64) async {
        let currentSize = await getCacheSize()
        var sizeToFree = currentSize - targetSize
        
        // Start from least recently used (beginning of array)
        var indicesToRemove: [Int] = []
        
        for (index, cacheKey) in accessOrder.enumerated() {
            if sizeToFree <= 0 { break }
            
            let components = cacheKey.split(separator: ":")
            guard components.count == 2 else { continue }
            
            let mangaId = String(components[0])
            let chapterId = String(components[1])
            
            if let result = await coreDataManager.getAnalysisResult(mangaId: mangaId, chapterId: chapterId) {
                // Estimate size of this entry
                let entrySize = estimateResultSize(result)
                
                await coreDataManager.deleteAnalysisResult(mangaId: mangaId, chapterId: chapterId)
                sizeToFree -= entrySize
                indicesToRemove.append(index)
                
                LogManager.logger.info("Evicted cache entry: \(cacheKey)")
            }
        }
        
        // Remove from access order (in reverse order to maintain indices)
        for index in indicesToRemove.reversed() {
            accessOrder.remove(at: index)
        }
        
        await saveAccessOrder()
    }
    
    private func evictOldestEntries(count: Int) async {
        let entriesToRemove = Array(accessOrder.prefix(count))
        
        for cacheKey in entriesToRemove {
            let components = cacheKey.split(separator: ":")
            guard components.count == 2 else { continue }
            
            let mangaId = String(components[0])
            let chapterId = String(components[1])
            
            await coreDataManager.deleteAnalysisResult(mangaId: mangaId, chapterId: chapterId)
            accessOrder.removeAll { $0 == cacheKey }
            
            LogManager.logger.info("Evicted old cache entry: \(cacheKey)")
        }
        
        await saveAccessOrder()
    }
    
    private func updateAccessOrder(_ cacheKey: String) {
        // Remove if already exists
        accessOrder.removeAll { $0 == cacheKey }
        
        // Add to end (most recently used)
        accessOrder.append(cacheKey)
        
        Task {
            await saveAccessOrder()
        }
    }
    
    // MARK: - Encryption
    
    private func encryptAnalysisResult(_ result: AnalysisResult) async -> AnalysisResult {
        // For now, return as-is. In production, you might want to encrypt sensitive data
        // like character names or dialogue text for privacy
        return result
    }
    
    private func decryptAnalysisResult(_ result: AnalysisResult) async -> AnalysisResult {
        // For now, return as-is. This would decrypt data encrypted by encryptAnalysisResult
        return result
    }
    
    // MARK: - Persistence
    
    private func accessOrderFilePath() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir
            .appendingPathComponent("AIAnalysis", isDirectory: true)
            .appendingPathComponent("cache_access_order.json")
    }
    
    private func loadAccessOrder() async {
        let filePath = accessOrderFilePath()
        
        guard let data = try? Data(contentsOf: filePath),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            accessOrder = []
            return
        }
        
        accessOrder = order
    }
    
    private func saveAccessOrder() async {
        let filePath = accessOrderFilePath()
        
        // Create directory if needed
        let directory = filePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        guard let data = try? JSONEncoder().encode(accessOrder) else {
            return
        }
        
        try? data.write(to: filePath)
    }
    
    // MARK: - Utilities
    
    private func getAllCachedResults() async -> [AnalysisResult] {
        // This would need to be implemented in CoreDataManager to fetch all results
        // For now, we'll track them through access order
        var results: [AnalysisResult] = []
        
        for cacheKey in accessOrder {
            let components = cacheKey.split(separator: ":")
            guard components.count == 2 else { continue }
            
            let mangaId = String(components[0])
            let chapterId = String(components[1])
            
            if let result = await coreDataManager.getAnalysisResult(mangaId: mangaId, chapterId: chapterId) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private func estimateResultSize(_ result: AnalysisResult) -> Int64 {
        // Rough estimation of memory usage
        var size: Int64 = 0
        
        // Pages data
        size += Int64(result.pages.count * 1000) // Rough estimate per page
        
        // Transcript data
        for dialogue in result.transcript {
            size += Int64(dialogue.text.utf8.count)
            size += Int64(dialogue.speaker.utf8.count)
        }
        
        // Audio segments (largest component)
        if let audioSegments = result.audioSegments {
            for segment in audioSegments {
                size += Int64(segment.audioData.count)
            }
        }
        
        return size
    }
    
    // MARK: - Cache Statistics
    
    func getCacheStatistics() async -> CacheStatistics {
        let totalSize = await getCacheSize()
        let maxSize = await configManager.cacheMaxSize
        let entryCount = accessOrder.count
        
        let allResults = await getAllCachedResults()
        let mangaCount = Set(allResults.map { $0.mangaId }).count
        
        let oldestEntry = allResults.min { $0.analysisDate < $1.analysisDate }
        let newestEntry = allResults.max { $0.analysisDate < $1.analysisDate }
        
        return CacheStatistics(
            totalSize: totalSize,
            maxSize: maxSize,
            entryCount: entryCount,
            mangaCount: mangaCount,
            oldestEntryDate: oldestEntry?.analysisDate,
            newestEntryDate: newestEntry?.analysisDate,
            hitRate: 0.0 // Would need to track hits/misses to calculate
        )
    }
}

// MARK: - Cache Statistics Model

struct CacheStatistics {
    let totalSize: Int64
    let maxSize: Int64
    let entryCount: Int
    let mangaCount: Int
    let oldestEntryDate: Date?
    let newestEntryDate: Date?
    let hitRate: Double
    
    var usagePercentage: Double {
        guard maxSize > 0 else { return 0.0 }
        return Double(totalSize) / Double(maxSize) * 100.0
    }
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedMaxSize: String {
        ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
    }
}
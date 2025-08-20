//
//  AudioPlaybackManager.swift
//  Aidoku
//
//  Created by AI Analysis Feature
//

import Foundation
import AVFoundation
import Combine

// MARK: - Page Delegate Protocol

protocol AudioPlaybackPageDelegate: AnyObject {
    func audioPlaybackShouldTurnToPage(_ pageIndex: Int)
    func audioPlaybackDidFinishPage(_ pageIndex: Int)
    func audioPlaybackDidStartPage(_ pageIndex: Int)
}

/// Manages audio playback with synchronized text highlighting for manga dialogue
@MainActor
class AudioPlaybackManager: NSObject, ObservableObject {
    static let shared = AudioPlaybackManager()
    
    // Published properties for UI binding
    @Published var isPlaying: Bool = false
    @Published var currentSegmentIndex: Int = 0
    @Published var playbackProgress: Double = 0.0
    @Published var playbackRate: Float = 1.0
    @Published var currentDialogue: DialogueLine?
    @Published var currentPageIndex: Int = 0
    @Published var shouldAutoTurnPage: Bool = false
    
    // Auto page turn settings
    @Published var autoPageTurnEnabled: Bool = true
    @Published var pageTransitionDelay: TimeInterval = 1.5
    
    // Audio playback
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    // Current playlist
    private var audioSegments: [AudioSegment] = []
    private var transcript: [DialogueLine] = []
    var voiceSettings: VoiceSettings?
    
    // Page management
    private var pageDialogueMap: [Int: [Int]] = [:] // pageIndex: [segmentIndices]
    private var currentPageSegments: [Int] = []
    private var pageTransitionTimer: Timer?
    
    // Temporary audio files
    private var tempAudioFiles: [URL] = []
    
    // Delegate for page turning
    weak var pageDelegate: AudioPlaybackPageDelegate?
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        cleanupTempFiles()
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            LogManager.logger.error("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Page-Specific Playback Control
    
    func playPageAudio(_ segments: [AudioSegment], transcript: [DialogueLine], pageIndex: Int) async {
        // Filter segments for current page only
        let pageSegments = segments.filter { segment in
            let components = segment.dialogueId.split(separator: "_")
            return components.first == String(pageIndex)
        }
        
        let pageTranscript = transcript.filter { $0.pageIndex == pageIndex }
        
        self.audioSegments = pageSegments
        self.transcript = pageTranscript
        
        guard !pageSegments.isEmpty else {
            LogManager.logger.info("No audio segments for page \(pageIndex)")
            return
        }
        
        // Start from the beginning of page audio
        currentSegmentIndex = 0
        await playCurrentSegment()
        
        LogManager.logger.info("Started playing audio for page \(pageIndex) with \(pageSegments.count) segments")
    }
    
    func playTranscript(_ segments: [AudioSegment], transcript: [DialogueLine], voiceSettings: VoiceSettings? = nil) async {
        self.audioSegments = segments
        self.transcript = transcript
        self.voiceSettings = voiceSettings
        
        guard !segments.isEmpty else {
            LogManager.logger.warn("No audio segments to play")
            return
        }
        
        // Build page-to-dialogue mapping
        buildPageDialogueMapping()
        
        // Start from the beginning
        currentSegmentIndex = 0
        currentPageIndex = transcript.first?.pageIndex ?? 0
        
        // Notify delegate about starting page
        pageDelegate?.audioPlaybackDidStartPage(currentPageIndex)
        
        await playCurrentSegment()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopPlaybackTimer()
        
        LogManager.logger.info("Audio playback paused")
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startPlaybackTimer()
        
        LogManager.logger.info("Audio playback resumed")
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentSegmentIndex = 0
        playbackProgress = 0.0
        currentDialogue = nil
        stopPlaybackTimer()
        
        LogManager.logger.info("Audio playback stopped")
    }
    
    func seek(to segmentIndex: Int) async {
        guard segmentIndex >= 0 && segmentIndex < audioSegments.count else {
            return
        }
        
        let wasPlaying = isPlaying
        stop()
        
        currentSegmentIndex = segmentIndex
        
        if wasPlaying {
            await playCurrentSegment()
        }
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate)) // Clamp between 0.5x and 2.0x
        audioPlayer?.rate = playbackRate
        
        LogManager.logger.info("Playback rate set to \(playbackRate)x")
    }
    
    func skipToNext() async {
        guard currentSegmentIndex < audioSegments.count - 1 else {
            stop()
            return
        }
        
        await seek(to: currentSegmentIndex + 1)
    }
    
    func skipToPrevious() async {
        guard currentSegmentIndex > 0 else {
            return
        }
        
        await seek(to: currentSegmentIndex - 1)
    }
    
    // MARK: - Private Playback Methods
    
    private func playCurrentSegment() async {
        guard currentSegmentIndex < audioSegments.count else {
            // Finished all segments
            await handlePlaybackComplete()
            return
        }
        
        let segment = audioSegments[currentSegmentIndex]
        
        // Update current dialogue and check for page changes
        updateCurrentDialogue(for: segment)
        await checkForPageTransition()
        
        do {
            // Create temporary audio file with voice settings applied
            let tempURL = try await createTempAudioFile(from: segment.audioData, applySettings: true)
            tempAudioFiles.append(tempURL)
            
            // Create audio player
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.rate = playbackRate
            audioPlayer?.enableRate = true
            
            // Apply voice settings
            if let settings = voiceSettings {
                audioPlayer?.volume = settings.globalVoiceSettings.masterVolume
            }
            
            // Start playback
            audioPlayer?.play()
            isPlaying = true
            startPlaybackTimer()
            
            LogManager.logger.info("Playing audio segment \(currentSegmentIndex + 1)/\(audioSegments.count): \(segment.speaker)")
            
        } catch {
            LogManager.logger.error("Failed to play audio segment: \(error)")
            await skipToNext()
        }
    }
    
    private func updateCurrentDialogue(for segment: AudioSegment) {
        // Find matching dialogue line
        let dialogueComponents = segment.dialogueId.split(separator: "_")
        guard dialogueComponents.count >= 2,
              let pageIndex = Int(dialogueComponents[0]),
              let textId = Int(dialogueComponents[1]) else {
            return
        }
        
        currentDialogue = transcript.first { dialogue in
            dialogue.pageIndex == pageIndex && dialogue.textId == textId
        }
    }
    
    private func createTempAudioFile(from audioData: Data, applySettings: Bool = false) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        
        // For now, just write the audio data directly
        // In a more advanced implementation, you could apply voice settings here
        // by processing the audio data with Core Audio or similar frameworks
        try audioData.write(to: tempURL)
        return tempURL
    }
    
    // MARK: - Page Management
    
    private func buildPageDialogueMapping() {
        pageDialogueMap.removeAll()
        
        for (index, segment) in audioSegments.enumerated() {
            // Extract page index from dialogue ID
            let dialogueComponents = segment.dialogueId.split(separator: "_")
            guard dialogueComponents.count >= 2,
                  let pageIndex = Int(dialogueComponents[0]) else {
                continue
            }
            
            if pageDialogueMap[pageIndex] == nil {
                pageDialogueMap[pageIndex] = []
            }
            pageDialogueMap[pageIndex]?.append(index)
        }
        
        LogManager.logger.info("Built page dialogue mapping: \(pageDialogueMap)")
    }
    
    private func checkForPageTransition() async {
        guard let currentDialogue = currentDialogue else { return }
        
        let newPageIndex = currentDialogue.pageIndex
        
        if newPageIndex != currentPageIndex {
            // Page changed
            let previousPageIndex = currentPageIndex
            currentPageIndex = newPageIndex
            
            // Notify delegate about page change
            pageDelegate?.audioPlaybackDidFinishPage(previousPageIndex)
            pageDelegate?.audioPlaybackDidStartPage(currentPageIndex)
            
            // Trigger auto page turn if enabled
            if autoPageTurnEnabled && voiceSettings?.globalVoiceSettings.autoPageTurn == true {
                scheduleAutoPageTurn()
            }
        }
    }
    
    private func scheduleAutoPageTurn() {
        // Cancel any existing timer
        pageTransitionTimer?.invalidate()
        
        let delay = voiceSettings?.globalVoiceSettings.pageTransitionDelay ?? pageTransitionDelay
        
        pageTransitionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.shouldAutoTurnPage = true
                self.pageDelegate?.audioPlaybackShouldTurnToPage(self.currentPageIndex)
                
                // Reset the flag after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.shouldAutoTurnPage = false
                }
            }
        }
    }
    
    private func handlePlaybackComplete() async {
        // Notify delegate about finishing the last page
        pageDelegate?.audioPlaybackDidFinishPage(currentPageIndex)
        
        stop()
        LogManager.logger.info("Audio playbook completed")
    }
    
    // MARK: - Page Control Methods
    
    func enableAutoPageTurn(_ enabled: Bool) {
        autoPageTurnEnabled = enabled
        if !enabled {
            pageTransitionTimer?.invalidate()
            pageTransitionTimer = nil
        }
    }
    
    func setPageTransitionDelay(_ delay: TimeInterval) {
        pageTransitionDelay = max(0.5, min(5.0, delay)) // Clamp between 0.5 and 5 seconds
    }
    
    func jumpToPage(_ pageIndex: Int) async {
        guard let segmentIndices = pageDialogueMap[pageIndex],
              let firstSegmentIndex = segmentIndices.first else {
            LogManager.logger.warn("No audio segments found for page \(pageIndex)")
            return
        }
        
        await seek(to: firstSegmentIndex)
    }
    
    func getAvailablePages() -> [Int] {
        return Array(pageDialogueMap.keys).sorted()
    }
    
    // MARK: - Progress Tracking
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackProgress()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackProgress() {
        guard let player = audioPlayer else {
            playbackProgress = 0.0
            return
        }
        
        let segmentProgress = player.duration > 0 ? player.currentTime / player.duration : 0.0
        let overallProgress = (Double(currentSegmentIndex) + segmentProgress) / Double(audioSegments.count)
        
        playbackProgress = overallProgress
    }
    
    // MARK: - Cleanup
    
    private func cleanupTempFiles() {
        for tempURL in tempAudioFiles {
            try? FileManager.default.removeItem(at: tempURL)
        }
        tempAudioFiles.removeAll()
    }
    
    // MARK: - Public Utilities
    
    func getTotalDuration() -> TimeInterval {
        return audioSegments.reduce(0) { $0 + $1.duration }
    }
    
    func getCurrentSegment() -> AudioSegment? {
        guard currentSegmentIndex < audioSegments.count else { return nil }
        return audioSegments[currentSegmentIndex]
    }
    
    func getSegmentAtIndex(_ index: Int) -> AudioSegment? {
        guard index >= 0 && index < audioSegments.count else { return nil }
        return audioSegments[index]
    }
    
    func getPlaybackInfo() -> PlaybackInfo {
        return PlaybackInfo(
            isPlaying: isPlaying,
            currentSegmentIndex: currentSegmentIndex,
            totalSegments: audioSegments.count,
            playbackProgress: playbackProgress,
            playbackRate: playbackRate,
            currentDialogue: currentDialogue,
            currentPageIndex: currentPageIndex,
            totalPages: pageDialogueMap.keys.count,
            totalDuration: getTotalDuration(),
            autoPageTurnEnabled: autoPageTurnEnabled,
            shouldAutoTurnPage: shouldAutoTurnPage
        )
    }
    
    // MARK: - Voice Settings
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        voiceSettings = settings
        
        // Update current playback settings
        autoPageTurnEnabled = settings.globalVoiceSettings.autoPageTurn
        pageTransitionDelay = settings.globalVoiceSettings.pageTransitionDelay
        
        // Update audio player volume if currently playing
        audioPlayer?.volume = settings.globalVoiceSettings.masterVolume
    }
    
    func getCharacterVoiceSettings(for characterName: String) -> CharacterVoiceSettings {
        return voiceSettings?.characterVoiceSettings[characterName] ?? .default
    }
    
    func setCharacterVoiceSettings(_ settings: CharacterVoiceSettings, for characterName: String) {
        guard var currentSettings = voiceSettings else { return }
        
        currentSettings.characterVoiceSettings[characterName] = settings
        voiceSettings = currentSettings
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            // Add pause between dialogue if configured
            let pauseDuration = voiceSettings?.globalVoiceSettings.pauseBetweenDialogue ?? 0.5
            
            if pauseDuration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                    Task {
                        await self.skipToNext()
                    }
                }
            } else {
                Task {
                    await skipToNext()
                }
            }
        } else {
            LogManager.logger.warn("Audio playback finished unsuccessfully")
            stop()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        LogManager.logger.error("Audio decode error: \(error?.localizedDescription ?? "Unknown error")")
        stop()
    }
}

// MARK: - Supporting Models

struct PlaybackInfo {
    let isPlaying: Bool
    let currentSegmentIndex: Int
    let totalSegments: Int
    let playbackProgress: Double
    let playbackRate: Float
    let currentDialogue: DialogueLine?
    let currentPageIndex: Int
    let totalPages: Int
    let totalDuration: TimeInterval
    let autoPageTurnEnabled: Bool
    let shouldAutoTurnPage: Bool
    
    var formattedProgress: String {
        let current = Int(playbackProgress * totalDuration)
        let total = Int(totalDuration)
        return "\(formatTime(current)) / \(formatTime(total))"
    }
    
    var pageProgress: String {
        return "Page \(currentPageIndex + 1) of \(totalPages)"
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Audio Generation Integration

extension AudioPlaybackManager {
    /// Generate and play audio for an analysis result
    func generateAndPlayAudio(for analysisResult: AnalysisResult, voiceSettings: VoiceSettings? = nil) async throws {
        let aiManager = AIAnalysisManager.shared
        
        // Generate audio if not already available
        let audioSegments: [AudioSegment]
        if let existingAudio = analysisResult.audioSegments {
            audioSegments = existingAudio
        } else {
            audioSegments = try await aiManager.generateAudio(
                mangaId: analysisResult.mangaId,
                chapterId: analysisResult.chapterId
            )
        }
        
        // Get voice settings if not provided
        let settings = voiceSettings ?? await AIAnalysisConfigManager.shared.voiceSettings
        
        // Start playback with voice settings
        await playTranscript(audioSegments, transcript: analysisResult.transcript, voiceSettings: settings)
    }
    
    /// Check if audio is available for an analysis result
    func hasAudio(for analysisResult: AnalysisResult) -> Bool {
        return analysisResult.audioSegments != nil && !analysisResult.audioSegments!.isEmpty
    }
    
    /// Generate audio with custom voice settings
    func generateAudioWithSettings(for analysisResult: AnalysisResult, voiceSettings: VoiceSettings) async throws -> [AudioSegment] {
        let aiManager = AIAnalysisManager.shared
        
        // Always regenerate audio with new settings
        return try await aiManager.generateAudioWithSettings(
            mangaId: analysisResult.mangaId,
            chapterId: analysisResult.chapterId,
            voiceSettings: voiceSettings
        )
    }
}
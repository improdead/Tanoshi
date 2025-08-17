//
//  AIAnalysisReaderIntegration.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Example Integration
//

import Foundation
import SwiftUI

/// Example of how to integrate AI analysis with manga reader
@MainActor
class AIAnalysisReaderIntegration: ObservableObject {
    @Published var currentPageIndex: Int = 0
    @Published var isAudioPlaying: Bool = false
    @Published var showAnalysisOverlay: Bool = false
    @Published var analysisResult: AnalysisResult?
    
    private let aiManager = AIAnalysisManager.shared
    private let audioManager = AudioPlaybackManager.shared
    
    private let mangaId: String
    private let chapterId: String
    
    init(mangaId: String, chapterId: String) {
        self.mangaId = mangaId
        self.chapterId = chapterId
        
        // Set up audio playback delegate
        audioManager.pageDelegate = self
        
        // Load analysis if available
        Task {
            await loadAnalysis()
        }
    }
    
    // MARK: - Analysis Loading
    
    private func loadAnalysis() async {
        // Check for cached analysis first
        if let cached = await aiManager.getAnalysisResult(mangaId: mangaId, chapterId: chapterId) {
            analysisResult = cached
            return
        }
        
        // Trigger automatic analysis (works with all sources: local PDFs, online manga, etc.)
        do {
            let result = try await aiManager.analyzeChapterAutomatically(mangaId: mangaId, chapterId: chapterId)
            analysisResult = result
        } catch {
            LogManager.logger.error("Failed to analyze chapter: \(error)")
        }
    }
    
    // MARK: - Audio Playback
    
    func startAudioPlayback() async {
        guard let result = analysisResult else { return }
        
        do {
            try await audioManager.generateAndPlayAudio(for: result)
            isAudioPlaying = true
        } catch {
            LogManager.logger.error("Failed to start audio playback: \(error)")
        }
    }
    
    func pauseAudioPlayback() {
        audioManager.pause()
        isAudioPlaying = false
    }
    
    func resumeAudioPlayback() {
        audioManager.resume()
        isAudioPlaying = true
    }
    
    func stopAudioPlayback() {
        audioManager.stop()
        isAudioPlaying = false
    }
    
    // MARK: - Page Navigation
    
    func goToPage(_ pageIndex: Int) {
        currentPageIndex = pageIndex
        
        // If audio is playing, jump to that page's audio
        if isAudioPlaying {
            Task {
                await audioManager.jumpToPage(pageIndex)
            }
        }
    }
    
    func nextPage() {
        let maxPage = analysisResult?.pages.count ?? 1
        if currentPageIndex < maxPage - 1 {
            goToPage(currentPageIndex + 1)
        }
    }
    
    func previousPage() {
        if currentPageIndex > 0 {
            goToPage(currentPageIndex - 1)
        }
    }
    
    // MARK: - Analysis Overlay
    
    func toggleAnalysisOverlay() {
        showAnalysisOverlay.toggle()
    }
    
    func getTextRegionsForCurrentPage() -> [TextRegion] {
        guard let result = analysisResult,
              currentPageIndex < result.pages.count else {
            return []
        }
        
        return result.pages[currentPageIndex].textRegions
    }
    
    func getCharacterDetectionsForCurrentPage() -> [CharacterDetection] {
        guard let result = analysisResult,
              currentPageIndex < result.pages.count else {
            return []
        }
        
        return result.pages[currentPageIndex].characterDetections
    }
    
    // MARK: - Voice Settings
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        audioManager.updateVoiceSettings(settings)
    }
    
    func setCharacterVoice(_ characterName: String, voiceFile: String) async {
        let configManager = AIAnalysisConfigManager.shared
        var currentSettings = await configManager.voiceSettings
        
        currentSettings.characterVoiceFiles[characterName] = voiceFile
        await configManager.setVoiceSettings(currentSettings)
        
        // Update audio manager
        audioManager.updateVoiceSettings(currentSettings)
    }
    
    func setCharacterVoiceSettings(_ characterName: String, settings: CharacterVoiceSettings) {
        audioManager.setCharacterVoiceSettings(settings, for: characterName)
    }
    
    func getCurrentVoiceSettings() -> VoiceSettings {
        return audioManager.voiceSettings ?? .default
    }
}

// MARK: - Audio Playback Page Delegate

extension AIAnalysisReaderIntegration: AudioPlaybackPageDelegate {
    func audioPlaybackShouldTurnToPage(_ pageIndex: Int) {
        // Auto-turn page when audio indicates
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPageIndex = pageIndex
        }
    }
    
    func audioPlaybackDidFinishPage(_ pageIndex: Int) {
        // Optional: Add visual feedback when page audio finishes
        LogManager.logger.info("Finished audio for page \(pageIndex)")
    }
    
    func audioPlaybackDidStartPage(_ pageIndex: Int) {
        // Optional: Add visual feedback when page audio starts
        LogManager.logger.info("Started audio for page \(pageIndex)")
    }
}

// MARK: - SwiftUI View Example

struct AIAnalysisReaderView: View {
    @StateObject private var integration: AIAnalysisReaderIntegration
    @State private var showVoiceSettings = false
    
    init(mangaId: String, chapterId: String) {
        _integration = StateObject(wrappedValue: AIAnalysisReaderIntegration(mangaId: mangaId, chapterId: chapterId))
    }
    
    var body: some View {
        ZStack {
            // Main manga reader view
            MangaPageView(
                pageIndex: integration.currentPageIndex,
                mangaId: integration.mangaId,
                chapterId: integration.chapterId
            )
            
            // Analysis overlay
            if integration.showAnalysisOverlay {
                AnalysisOverlayView(
                    textRegions: integration.getTextRegionsForCurrentPage(),
                    characterDetections: integration.getCharacterDetectionsForCurrentPage()
                )
            }
            
            // Audio controls
            VStack {
                Spacer()
                if integration.analysisResult != nil {
                    AudioControlsView(
                        isPlaying: integration.isAudioPlaying,
                        onPlay: { await integration.startAudioPlayback() },
                        onPause: { integration.pauseAudioPlayback() },
                        onStop: { integration.stopAudioPlayback() }
                    )
                }
            }
            
            // Navigation controls
            HStack {
                Button(action: { integration.previousPage() }) {
                    Image(systemName: "chevron.left")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .disabled(integration.currentPageIndex <= 0)
                
                Spacer()
                
                Button(action: { integration.nextPage() }) {
                    Image(systemName: "chevron.right")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .disabled(integration.currentPageIndex >= (integration.analysisResult?.pages.count ?? 1) - 1)
            }
            .padding()
            
            // Loading indicator
            if integration.analysisResult == nil {
                VStack {
                    ProgressView("Analyzing manga...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text("Extracting text and identifying characters...")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.top)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { integration.toggleAnalysisOverlay() }) {
                        Label("Toggle Analysis", systemImage: integration.showAnalysisOverlay ? "eye.slash" : "eye")
                    }
                    
                    Button(action: { showVoiceSettings = true }) {
                        Label("Voice Settings", systemImage: "speaker.wave.2")
                    }
                    
                    if integration.analysisResult != nil {
                        Button(action: {
                            Task { await integration.startAudioPlayback() }
                        }) {
                            Label("Start Audio", systemImage: "play.circle")
                        }
                        .disabled(integration.isAudioPlaying)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsView(
                initialSettings: integration.getCurrentVoiceSettings(),
                onSave: { settings in
                    integration.updateVoiceSettings(settings)
                }
            )
        }
    }
}

// MARK: - Real Implementation Views

struct MangaPageView: View {
    let pageIndex: Int
    @State private var pageImage: UIImage?
    @State private var isLoading = true
    
    private let mangaId: String
    private let chapterId: String
    
    init(pageIndex: Int, mangaId: String, chapterId: String) {
        self.pageIndex = pageIndex
        self.mangaId = mangaId
        self.chapterId = chapterId
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading page...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = pageImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipped()
            } else {
                Text("Failed to load page")
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            loadPage()
        }
        .onChange(of: pageIndex) { _ in
            loadPage()
        }
    }
    
    private func loadPage() {
        isLoading = true
        
        Task {
            do {
                // Get pages from LocalFileManager
                let pages = await LocalFileManager.shared.fetchPages(mangaId: mangaId, chapterId: chapterId)
                
                guard pageIndex < pages.count else {
                    await MainActor.run {
                        isLoading = false
                        pageImage = nil
                    }
                    return
                }
                
                let page = pages[pageIndex]
                let image = try await loadImageFromPage(page)
                
                await MainActor.run {
                    pageImage = image
                    isLoading = false
                }
            } catch {
                LogManager.logger.error("Failed to load page \(pageIndex): \(error)")
                await MainActor.run {
                    isLoading = false
                    pageImage = nil
                }
            }
        }
    }
    
    private func loadImageFromPage(_ page: AidokuRunner.Page) async throws -> UIImage {
        switch page.content {
        case .url(let url):
            if url.scheme == "aidoku-pdf" {
                // Handle PDF page rendering
                return try await renderPDFPage(from: url)
            } else {
                // Handle regular URL
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    throw AIAnalysisError.unsupportedFileFormat
                }
                return image
            }
            
        case .zipFile(let url, let filePath):
            // Extract from ZIP file
            return try await extractImageFromZip(zipURL: url, filePath: filePath)
            
        case .data(let data):
            guard let image = UIImage(data: data) else {
                throw AIAnalysisError.unsupportedFileFormat
            }
            return image
        }
    }
    
    private func renderPDFPage(from url: URL) async throws -> UIImage {
        #if canImport(PDFKit)
        // Parse PDF URL to get page index
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pageQuery = components.queryItems?.first(where: { $0.name == "page" }),
              let pageIndexString = pageQuery.value,
              let pdfPageIndex = Int(pageIndexString) else {
            throw AIAnalysisError.invalidResponse
        }
        
        // Get PDF path from URL
        let pdfPath = url.path.replacingOccurrences(of: "aidoku-pdf://", with: "")
        let documentsDir = FileManager.default.documentDirectory
        let pdfURL = documentsDir.appendingPathComponent(pdfPath)
        
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: pdfPageIndex) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        let pageSize = page.bounds(for: .mediaBox).size
        let scale: CGFloat = 2.0
        let renderSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        
        return page.thumbnail(of: renderSize, for: .mediaBox)
        #else
        throw AIAnalysisError.unsupportedFileFormat
        #endif
    }
    
    private func extractImageFromZip(zipURL: URL, filePath: String) async throws -> UIImage {
        guard let archive = try? Archive(url: zipURL, accessMode: .read) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        guard let entry = archive[filePath] else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        var imageData = Data()
        _ = try archive.extract(entry) { data in
            imageData.append(data)
        }
        
        guard let image = UIImage(data: imageData) else {
            throw AIAnalysisError.unsupportedFileFormat
        }
        
        return image
    }
}

struct AnalysisOverlayView: View {
    let textRegions: [TextRegion]
    let characterDetections: [CharacterDetection]
    @State private var selectedRegion: TextRegion?
    @State private var selectedCharacter: CharacterDetection?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Text region overlays
                ForEach(textRegions.indices, id: \.self) { index in
                    let region = textRegions[index]
                    let scaledBox = scaleRect(region.boundingBox, to: geometry.size)
                    
                    Rectangle()
                        .stroke(selectedRegion?.id == region.id ? Color.yellow : Color.blue, lineWidth: 2)
                        .frame(width: scaledBox.width, height: scaledBox.height)
                        .position(x: scaledBox.midX, y: scaledBox.midY)
                        .onTapGesture {
                            selectedRegion = region
                            selectedCharacter = nil
                        }
                        .overlay(
                            // Show text content on tap
                            Group {
                                if selectedRegion?.id == region.id {
                                    VStack {
                                        Text(region.text)
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.blue.opacity(0.9))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                        
                                        Text("Confidence: \(String(format: "%.1f%%", region.confidence * 100))")
                                            .font(.caption2)
                                            .padding(2)
                                            .background(Color.blue.opacity(0.7))
                                            .foregroundColor(.white)
                                            .cornerRadius(2)
                                    }
                                    .position(x: scaledBox.midX, y: scaledBox.minY - 30)
                                }
                            }
                        )
                }
                
                // Character detection overlays
                ForEach(characterDetections.indices, id: \.self) { index in
                    let detection = characterDetections[index]
                    let scaledBox = scaleRect(detection.boundingBox, to: geometry.size)
                    
                    Rectangle()
                        .stroke(selectedCharacter?.id == detection.id ? Color.orange : Color.red, lineWidth: 2)
                        .frame(width: scaledBox.width, height: scaledBox.height)
                        .position(x: scaledBox.midX, y: scaledBox.midY)
                        .onTapGesture {
                            selectedCharacter = detection
                            selectedRegion = nil
                        }
                        .overlay(
                            VStack {
                                Text(detection.name)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(4)
                                    .background(Color.red.opacity(0.9))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                
                                if selectedCharacter?.id == detection.id {
                                    Text("Confidence: \(String(format: "%.1f%%", detection.confidence * 100))")
                                        .font(.caption2)
                                        .padding(2)
                                        .background(Color.red.opacity(0.7))
                                        .foregroundColor(.white)
                                        .cornerRadius(2)
                                }
                            }
                            .position(x: scaledBox.midX, y: scaledBox.minY - 20)
                        )
                }
                
                // Clear selection on background tap
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRegion = nil
                        selectedCharacter = nil
                    }
            }
        }
    }
    
    private func scaleRect(_ rect: CGRect, to size: CGSize) -> CGRect {
        // Scale bounding box coordinates to match the view size
        // This assumes the original coordinates are normalized (0-1) or need scaling
        let scaleX = size.width
        let scaleY = size.height
        
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

struct AudioControlsView: View {
    let isPlaying: Bool
    let onPlay: () async -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    
    @StateObject private var audioManager = AudioPlaybackManager.shared
    @State private var showingSpeedPicker = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            if audioManager.isPlaying {
                VStack(spacing: 4) {
                    ProgressView(value: audioManager.playbackProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    
                    HStack {
                        Text(formatTime(audioManager.playbackProgress * audioManager.getTotalDuration()))
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if let dialogue = audioManager.currentDialogue {
                            Text(dialogue.speaker)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.yellow)
                        }
                        
                        Spacer()
                        
                        Text(formatTime(audioManager.getTotalDuration()))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Main controls
            HStack(spacing: 20) {
                // Previous page
                Button(action: {
                    Task { await audioManager.skipToPrevious() }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .disabled(!isPlaying)
                
                // Play/Pause
                Button(action: {
                    if isPlaying {
                        onPause()
                    } else {
                        Task { await onPlay() }
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                // Stop
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                // Next page
                Button(action: {
                    Task { await audioManager.skipToNext() }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .disabled(!isPlaying)
                
                // Speed control
                Button(action: { showingSpeedPicker.toggle() }) {
                    Text("\(String(format: "%.1f", audioManager.playbackRate))x")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(4)
                }
            }
            
            // Auto page turn indicator
            if audioManager.autoPageTurnEnabled {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Auto Page Turn")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .actionSheet(isPresented: $showingSpeedPicker) {
            ActionSheet(
                title: Text("Playback Speed"),
                buttons: [
                    .default(Text("0.5x")) { audioManager.setPlaybackRate(0.5) },
                    .default(Text("0.75x")) { audioManager.setPlaybackRate(0.75) },
                    .default(Text("1.0x")) { audioManager.setPlaybackRate(1.0) },
                    .default(Text("1.25x")) { audioManager.setPlaybackRate(1.25) },
                    .default(Text("1.5x")) { audioManager.setPlaybackRate(1.5) },
                    .default(Text("2.0x")) { audioManager.setPlaybackRate(2.0) },
                    .cancel()
                ]
            )
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct VoiceSettingsView: View {
    let onSave: (VoiceSettings) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var voiceSettings: VoiceSettings
    @State private var selectedCharacter: String?
    
    init(initialSettings: VoiceSettings = .default, onSave: @escaping (VoiceSettings) -> Void) {
        _voiceSettings = State(initialValue: initialSettings)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Global Audio Settings") {
                    HStack {
                        Text("Master Volume")
                        Spacer()
                        Slider(value: Binding(
                            get: { voiceSettings.globalVoiceSettings.masterVolume },
                            set: { newValue in
                                voiceSettings = VoiceSettings(
                                    language: voiceSettings.language,
                                    defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                    characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                    characterVoiceSettings: voiceSettings.characterVoiceSettings,
                                    globalVoiceSettings: GlobalVoiceSettings(
                                        masterVolume: newValue,
                                        pauseBetweenDialogue: voiceSettings.globalVoiceSettings.pauseBetweenDialogue,
                                        pauseBetweenPages: voiceSettings.globalVoiceSettings.pauseBetweenPages,
                                        autoPageTurn: voiceSettings.globalVoiceSettings.autoPageTurn,
                                        pageTransitionDelay: voiceSettings.globalVoiceSettings.pageTransitionDelay
                                    )
                                )
                            }
                        ), in: 0...1)
                        .frame(width: 100)
                        
                        Text("\(Int(voiceSettings.globalVoiceSettings.masterVolume * 100))%")
                            .frame(width: 40)
                    }
                    
                    Toggle("Auto Page Turn", isOn: Binding(
                        get: { voiceSettings.globalVoiceSettings.autoPageTurn },
                        set: { newValue in
                            voiceSettings = VoiceSettings(
                                language: voiceSettings.language,
                                defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                characterVoiceSettings: voiceSettings.characterVoiceSettings,
                                globalVoiceSettings: GlobalVoiceSettings(
                                    masterVolume: voiceSettings.globalVoiceSettings.masterVolume,
                                    pauseBetweenDialogue: voiceSettings.globalVoiceSettings.pauseBetweenDialogue,
                                    pauseBetweenPages: voiceSettings.globalVoiceSettings.pauseBetweenPages,
                                    autoPageTurn: newValue,
                                    pageTransitionDelay: voiceSettings.globalVoiceSettings.pageTransitionDelay
                                )
                            )
                        }
                    ))
                    
                    if voiceSettings.globalVoiceSettings.autoPageTurn {
                        HStack {
                            Text("Page Turn Delay")
                            Spacer()
                            Slider(value: Binding(
                                get: { voiceSettings.globalVoiceSettings.pageTransitionDelay },
                                set: { newValue in
                                    voiceSettings = VoiceSettings(
                                        language: voiceSettings.language,
                                        defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                        characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                        characterVoiceSettings: voiceSettings.characterVoiceSettings,
                                        globalVoiceSettings: GlobalVoiceSettings(
                                            masterVolume: voiceSettings.globalVoiceSettings.masterVolume,
                                            pauseBetweenDialogue: voiceSettings.globalVoiceSettings.pauseBetweenDialogue,
                                            pauseBetweenPages: voiceSettings.globalVoiceSettings.pauseBetweenPages,
                                            autoPageTurn: voiceSettings.globalVoiceSettings.autoPageTurn,
                                            pageTransitionDelay: newValue
                                        )
                                    )
                                }
                            ), in: 0.5...5.0)
                            .frame(width: 100)
                            
                            Text("\(String(format: "%.1f", voiceSettings.globalVoiceSettings.pageTransitionDelay))s")
                                .frame(width: 40)
                        }
                    }
                    
                    HStack {
                        Text("Pause Between Dialogue")
                        Spacer()
                        Slider(value: Binding(
                            get: { voiceSettings.globalVoiceSettings.pauseBetweenDialogue },
                            set: { newValue in
                                voiceSettings = VoiceSettings(
                                    language: voiceSettings.language,
                                    defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                    characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                    characterVoiceSettings: voiceSettings.characterVoiceSettings,
                                    globalVoiceSettings: GlobalVoiceSettings(
                                        masterVolume: voiceSettings.globalVoiceSettings.masterVolume,
                                        pauseBetweenDialogue: newValue,
                                        pauseBetweenPages: voiceSettings.globalVoiceSettings.pauseBetweenPages,
                                        autoPageTurn: voiceSettings.globalVoiceSettings.autoPageTurn,
                                        pageTransitionDelay: voiceSettings.globalVoiceSettings.pageTransitionDelay
                                    )
                                )
                            }
                        ), in: 0...3.0)
                        .frame(width: 100)
                        
                        Text("\(String(format: "%.1f", voiceSettings.globalVoiceSettings.pauseBetweenDialogue))s")
                            .frame(width: 40)
                    }
                }
                
                Section("Language") {
                    Picker("Language", selection: Binding(
                        get: { voiceSettings.language },
                        set: { newValue in
                            voiceSettings = VoiceSettings(
                                language: newValue,
                                defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                characterVoiceSettings: voiceSettings.characterVoiceSettings,
                                globalVoiceSettings: voiceSettings.globalVoiceSettings
                            )
                        }
                    )) {
                        Text("English").tag("en")
                        Text("Japanese").tag("ja")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Chinese").tag("zh-cn")
                        Text("Korean").tag("ko")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Character Voice Settings") {
                    ForEach(Array(voiceSettings.characterVoiceSettings.keys.sorted()), id: \.self) { characterName in
                        NavigationLink(destination: CharacterVoiceDetailView(
                            characterName: characterName,
                            settings: voiceSettings.characterVoiceSettings[characterName] ?? .default,
                            onSave: { newSettings in
                                var updatedCharacterSettings = voiceSettings.characterVoiceSettings
                                updatedCharacterSettings[characterName] = newSettings
                                
                                voiceSettings = VoiceSettings(
                                    language: voiceSettings.language,
                                    defaultVoiceFile: voiceSettings.defaultVoiceFile,
                                    characterVoiceFiles: voiceSettings.characterVoiceFiles,
                                    characterVoiceSettings: updatedCharacterSettings,
                                    globalVoiceSettings: voiceSettings.globalVoiceSettings
                                )
                            }
                        )) {
                            HStack {
                                Text(characterName)
                                Spacer()
                                let settings = voiceSettings.characterVoiceSettings[characterName] ?? .default
                                Text(settings.emotion.displayName)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if voiceSettings.characterVoiceSettings.isEmpty {
                        Text("No character voices configured")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(voiceSettings)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CharacterVoiceDetailView: View {
    let characterName: String
    @State private var settings: CharacterVoiceSettings
    let onSave: (CharacterVoiceSettings) -> Void
    @Environment(\.dismiss) private var dismiss
    
    init(characterName: String, settings: CharacterVoiceSettings, onSave: @escaping (CharacterVoiceSettings) -> Void) {
        self.characterName = characterName
        _settings = State(initialValue: settings)
        self.onSave = onSave
    }
    
    var body: some View {
        Form {
            Section("Voice Characteristics") {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Slider(value: $settings.pitch, in: -1...1)
                        .frame(width: 150)
                    Text(settings.pitch > 0 ? "Higher" : settings.pitch < 0 ? "Lower" : "Normal")
                        .frame(width: 60)
                        .font(.caption)
                }
                
                HStack {
                    Text("Speed")
                    Spacer()
                    Slider(value: $settings.speed, in: 0.5...2.0)
                        .frame(width: 150)
                    Text("\(String(format: "%.1f", settings.speed))x")
                        .frame(width: 60)
                        .font(.caption)
                }
                
                HStack {
                    Text("Intensity")
                    Spacer()
                    Slider(value: $settings.intensity, in: 0...1)
                        .frame(width: 150)
                    Text("\(Int(settings.intensity * 100))%")
                        .frame(width: 60)
                        .font(.caption)
                }
                
                HStack {
                    Text("Breathiness")
                    Spacer()
                    Slider(value: $settings.breathiness, in: 0...1)
                        .frame(width: 150)
                    Text("\(Int(settings.breathiness * 100))%")
                        .frame(width: 60)
                        .font(.caption)
                }
            }
            
            Section("Emotion") {
                Picker("Emotion", selection: $settings.emotion) {
                    ForEach(VoiceEmotion.allCases, id: \.self) { emotion in
                        Text(emotion.displayName).tag(emotion)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle(characterName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    onSave(settings)
                    dismiss()
                }
            }
        }
    }
}
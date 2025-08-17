# AI Manga Analysis Feature

This folder contains all components for the AI-powered manga analysis feature that integrates with Google Colab backend services.

## 📁 Folder Structure

All AI analysis components are now organized in `Shared/AIAnalysis/`:

### `/Models`
- **AIAnalysis.swift** - Core data models, error types, and configuration structures
  - `AnalysisResult`, `PageAnalysis`, `TextRegion`, `CharacterDetection`
  - `DialogueLine`, `AudioSegment`, `CharacterBank`, `CharacterInfo`
  - `VoiceSettings`, `CharacterVoiceSettings`, `GlobalVoiceSettings`
  - `ColabConfiguration`, `XTTSConfiguration`, `AIAnalysisError`

### `/Managers`
- **AIAnalysisManager.swift** - Main coordinator for automatic analysis workflow
- **AIAnalysisConfigManager.swift** - Configuration and settings management
- **ColabAPIClient.swift** - HTTP client for Google Colab communication
- **CharacterBankManager.swift** - Character reference image management
- **AnalysisCacheManager.swift** - Smart caching with LRU eviction
- **AudioPlaybackManager.swift** - Audio playback with auto page turning
- **ColabSessionManager.swift** - Session management for Colab connections

### `/CoreData`
- **CoreDataManager+AIAnalysis.swift** - Database persistence extensions
  - Extends existing CoreDataManager with AI analysis methods
  - Handles `AIAnalysisResult` and `CharacterBank` entities

### `/Examples`
- **AIAnalysisReaderIntegration.swift** - Complete manga reader integration example
- **ColabSessionView.swift** - Session management UI example

## 🚀 Features

### Universal Source Support
- **Local Files**: PDF and CBZ/ZIP manga files
- **Online Sources**: All supported manga websites and APIs
- **Mixed Sources**: Komga servers, external APIs, etc.
- **Automatic Detection**: System automatically handles different source types

### Automatic Analysis
- Universal page extraction (PDF, online images, archives)
- Character recognition and dialogue extraction
- Automatic caching for offline access
- Background processing with progress tracking

### Voice Synthesis & Playback
- Character-specific voice settings (pitch, speed, emotion, intensity, breathiness)
- Auto page turning synchronized with audio
- Configurable pauses and transitions
- Multiple voice emotions (neutral, happy, sad, angry, excited, calm, mysterious, dramatic)

### Smart Caching
- LRU cache eviction policy
- Configurable storage limits
- Encrypted sensitive data storage
- Automatic cleanup and maintenance

### Character Bank Management
- Per-manga character reference images
- Import/export functionality
- Validation and corruption detection
- File-based persistence

## 🔧 Configuration

The system uses `AIAnalysisConfigManager` for all settings:

```swift
// Configure Colab endpoint
let config = ColabConfiguration(
    endpointURL: URL(string: "https://your-ngrok-url.ngrok.io")!,
    apiKey: nil,
    timeout: 300.0,
    maxRetries: 3,
    batchSize: 10
)

// Configure voice settings
let voiceSettings = VoiceSettings(
    language: "en",
    defaultVoiceFile: nil,
    characterVoiceFiles: [:],
    characterVoiceSettings: [:],
    globalVoiceSettings: GlobalVoiceSettings(
        masterVolume: 0.8,
        pauseBetweenDialogue: 0.5,
        pauseBetweenPages: 1.0,
        autoPageTurn: true,
        pageTransitionDelay: 1.5
    )
)
```

## 🎵 Voice Control

### Character-Specific Settings
```swift
let characterSettings = CharacterVoiceSettings(
    pitch: 0.2,        // -1.0 to 1.0
    speed: 1.1,        // 0.5 to 2.0
    emotion: .excited, // 8 different emotions
    intensity: 0.8,    // 0.0 to 1.0
    breathiness: 0.2   // 0.0 to 1.0
)
```

### Auto Page Turning
- Pages automatically turn when audio completes
- Configurable delay before page transitions
- Manual override available
- Smooth animated transitions

## 🔄 Universal Workflow

1. **User opens any manga chapter** (local PDF, online source, etc.)
2. **System detects source type** automatically
3. **Pages extracted** based on source:
   - **Local**: PDF/CBZ files processed directly
   - **Online**: Images downloaded from manga websites
   - **API**: Pages fetched through source APIs
4. **Sent to Colab** for MagiV2 processing
5. **Results cached** locally for offline access
6. **Audio generated** with XTTS-v2 voice synthesis
7. **Playback starts** with synchronized page turning

### Source Type Handling
- **Local Sources**: Direct file processing (PDF, CBZ, ZIP)
- **Online Sources**: Batch downloading with rate limiting
- **API Sources**: Komga, external manga APIs
- **Mixed Content**: Handles different page formats automatically

## 🗄️ Core Data Schema

New entities added in version 0.7.2:
- **AIAnalysisResult** - Stores analysis results per chapter
- **CharacterBank** - Stores character reference data per manga

## 📱 UI Integration

Use `AIAnalysisReaderIntegration` as a reference for integrating with manga readers:

```swift
let integration = AIAnalysisReaderIntegration(mangaId: "manga123", chapterId: "chapter1")
integration.pageDelegate = yourReaderViewController

// Start audio playback
await integration.startAudioPlayback()

// Enable auto page turning
integration.audioManager.enableAutoPageTurn(true)
```

## 🔧 Backend Setup

See `.kiro/specs/ai-manga-analysis/google-colab-setup.txt` for complete Google Colab backend setup with MagiV2 and XTTS-v2.

## 📋 Requirements

- iOS 15.0+
- PDFKit (for PDF processing)
- AVFoundation (for audio playback)
- Core Data (for persistence)
- Network connectivity (for analysis, cached results work offline)

## 🐛 Error Handling

All operations use `AIAnalysisError` enum for consistent error handling:
- Network unavailable
- Endpoint not configured
- Analysis timeout
- Insufficient storage
- Character bank corruption
- Audio generation failures

## 🔒 Privacy & Security

- Character bank data stays local
- Analysis results cached with encryption option
- Optional data anonymization
- Configurable cache limits and cleanup
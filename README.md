# Tanoshi
A revolutionary manga reading application with AI-powered narration for iOS and iPadOS.

## Features
- [x] No ads
- [x] Robust WASM source system
- [x] Online reading through external sources
- [x] Downloads
- [x] Tracker integration (AniList, MyAnimeList)
- [x] AI-powered manga narration with voice synthesis
- [x] Smart text recognition and speaker identification
- [x] Real-time audio synchronization with panel highlighting
- [x] Cloud and on-device TTS support

## AI Narration System

Tanoshi features an advanced AI narration system that transforms manga reading into an immersive audio-visual experience.

### Workflow: page → speech (high-level)
```mermaid
flowchart TD
  A[User opens chapter/page] --> B{Is structured text available?}
  B -->|Yes| C[Use structured text parser]
  B -->|No| D[Run OCR Vision/Tesseract]
  D --> C
  C --> E[Text segmentation: narration / dialogue / SFX cues]
  E --> F[Speaker assignment heuristics/ML]
  F --> G[Generate SSML per-utterance]
  G --> H{Voice type?}
  H -->|On-device| I[AVSpeechSynthesizer Audio Pipeline]
  H -->|Cloud| J[Cloud TTS stream Audio Pipeline]
  I --> K[SFX Manager Mixer]
  J --> K
  K --> L[Audio Playback Panel Highlighting sync]
  L --> M[Cache audio metadata files]
  M --> N[User controls: pause/seek/voice settings]
```

### System design component diagram
```mermaid
graph LR
  subgraph Device["Tanoshi iPad/iPhone"]
    UI[UI: Reader + Narration Controls]
    OCR[OCR: Vision / Tesseract]
    Parser[Text Parser & Segmentation]
    SpeakerID[Speaker Attribution Heuristics/CoreML]
    TTS_local[AVSpeechSynthesizer Adapter]
    AudioMgr[Audio Manager & Mixer]
    Cache[Local Cache: Audio files & metadata]
    Sync[Sync: Highlighting & timestamps]
  end

  subgraph Cloud["Optional Cloud"]
    TTS_cloud[Cloud TTS OpenAI/Google/AWS]
    MLService[Optional ML Inference Server]
    Storage[Cloud caching / S3]
  end

  UI --> Parser
  OCR --> Parser
  Parser --> SpeakerID
  SpeakerID --> TTS_local
  SpeakerID --> TTS_cloud
  TTS_local --> AudioMgr
  TTS_cloud --> AudioMgr
  AudioMgr --> Sync
  AudioMgr --> Cache
  Cache --> UI
  UI --> AudioMgr
  MLService --> SpeakerID
  TTS_cloud --> Storage
```

## Installation

For detailed installation instructions, check out the releases page.

### Manual Installation

The latest ipa file will always be available from the releases page.

## Contributing

Tanoshi is actively developed with cutting-edge AI features. This project is open source and welcomes contributions.

This repo is licensed under GPLv3. All code is original and written specifically for this project.

## License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

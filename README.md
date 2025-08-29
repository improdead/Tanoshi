# Aidoku (Tanoshi)
A free and open source manga reading application for iOS, iPadOS, and macOS with AI-powered narration.

## Features
- [x] No ads
- [x] Robust WASM source system
- [x] Online reading through external sources
- [x] Downloads with offline reading
- [x] Tracker integration (AniList, MyAnimeList, Shikimori)
- [x] **NEW**: AI-powered manga narration (Tanoshi Narration)
  - [x] Real-time text-to-speech with custom voices
  - [x] Intelligent speaker detection and character voices
  - [x] Background processing with live progress updates
  - [x] Rolling window processing for long chapters
- [x] iCloud sync with CloudKit integration
- [x] Cross-platform support (iOS, iPadOS, macOS)

## Tanoshi Narration

Experience your manga with AI-powered audio narration! Tanoshi Narration transforms manga pages into immersive audio experiences using advanced OCR and text-to-speech technology.

### How It Works
1. **Toggle Listen** in the reader toolbar
2. **Smart Processing**: AI extracts text and identifies speakers from manga pages
3. **Voice Synthesis**: Characters get unique voices using GPT-SoVITS technology
4. **Auto-Play**: Audio plays automatically as you read, synced to your current page

### Features
- **Real-time Processing**: 20-page rolling windows with live progress updates
- **Custom Voice Packs**: Narrator, main character, and supporting character voices
- **Background Processing**: Audio generation happens behind the scenes
- **Offline Playback**: Downloaded audio for offline reading
- **Smart Gating**: Placeholder ads support development while processing

### Technical Stack
- **Frontend**: Swift (iOS/macOS) with SwiftUI and AVPlayer
- **Backend**: Python FastAPI on Modal with GPU acceleration
- **OCR**: MAGI v2 for text extraction and speaker detection
- **TTS**: GPT-SoVITS for high-quality voice synthesis
- **Streaming**: Server-Sent Events (SSE) for real-time updates
- **Storage**: HLS audio streaming with CDN delivery

## Installation

For detailed installation instructions, check out [the website](https://aidoku.app).

### TestFlight

To join the TestFlight, you will need to join the [Aidoku Discord](https://discord.gg/kh2PYT8V8d).

### AltStore

We have an AltStore repo that contains the latest releases ipa. You can copy the [direct source URL](https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json) and paste it into AltStore. Note that AltStore PAL is not supported.

### Manual Installation

The latest ipa file will always be available from the [releases page](https://github.com/Aidoku/Aidoku/releases).

## Development

### Prerequisites
- Xcode 15+ with Swift Package Manager
- iOS 16+ / macOS 13+ deployment targets
- SwiftLint for code quality

### Building
```bash
# Resolve dependencies
xcodebuild -resolvePackageDependencies -project Aidoku.xcodeproj

# Build for iOS Simulator
xcodebuild -scheme "Aidoku (iOS)" -destination 'generic/platform=iOS Simulator' -configuration Debug build

# Build for macOS
xcodebuild -scheme "Aidoku (macOS)" -configuration Debug build

# Create unsigned iOS IPA (for distribution)
xcodebuild -scheme "Aidoku (iOS)" -configuration Release archive \
  -archivePath build/Aidoku.xcarchive -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

mkdir -p Payload && cp -r build/Aidoku.xcarchive/Products/Applications/Aidoku.app Payload
zip -r Aidoku-iOS.ipa Payload
```

### Linting
```bash
# Run SwiftLint with repository configuration
swiftlint

# Strict mode (matches CI)
swiftlint --strict
```

### Architecture
The project uses a shared core architecture:
- **Shared/**: Core functionality, data models, and business logic
- **iOS/**: iOS-specific UI and platform features
- **macOS/**: macOS-specific implementation
- **backend/**: Python FastAPI backend for narration services

#### Key Components
- **CoreDataManager**: Persistence with CloudKit sync and deduplication
- **SourceManager**: WASM-based manga source system with import/export
- **DownloadManager**: Offline content management with on-disk caching
- **NarrationAPI**: AI-powered text-to-speech integration
- **Tracking**: AniList, MyAnimeList, and Shikimori integration

### Narration Backend Development

The Tanoshi Narration backend runs on Python FastAPI with Modal for GPU acceleration.

#### Local Setup
```bash
# Navigate to backend directory
cd backend

# Create virtual environment (Python 3.10+)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment template
cp .env.example .env
# Edit .env with your configuration

# Run locally
uvicorn backend.server:app --reload --port 8080
```

#### Modal Deployment
```bash
# Install Modal CLI
pip install modal

# Set up authentication
modal token set

# Deploy to Modal
modal serve backend/modal_app.py
```

#### Environment Configuration
See `backend/.env.example` for required configuration:
- **API Keys**: External service authentication
- **Storage**: S3/MinIO bucket configuration
- **Database**: Redis connection for caching and rate limiting
- **Models**: MAGI v2 and GPT-SoVITS endpoints
- **CDN**: Base URL for audio delivery

#### API Endpoints
- `POST /v1/narration/session/start` - Begin narration for 20-page window
- `POST /v1/narration/session/next` - Process next 20 pages
- `GET /v1/narration/jobs/{job_id}/events` - SSE progress updates
- `GET /v1/narration/jobs/{job_id}/snapshot` - Current job state
- `POST /v1/voices/register` - Register custom voice profiles
- `GET /v1/voices/{voice_id}` - Voice metadata and status

## Contributing

Aidoku is still in a beta phase, and there are a lot of planned features and fixes. If you're interested in contributing, I'd first recommend checking with me on [Discord](https://discord.gg/kh2PYT8V8d) in the app development channel.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Development Guidelines
- Follow Swift coding conventions and SwiftLint rules
- Use SwiftUI for new UI components
- Maintain compatibility with iOS 16+ and macOS 13+
- Test narration features with both local and Modal backends
- Document API changes in WARP.md

### Contributing to Narration
The Tanoshi Narration system welcomes contributions:
- **Frontend**: SwiftUI components, AVPlayer integration, SSE handling
- **Backend**: Python FastAPI endpoints, Modal optimization, ML pipelines
- **Infrastructure**: CDN setup, caching strategies, monitoring
- **Quality**: Testing, performance optimization, error handling

### Translations
Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).

## Technical Details

### Data Storage
- **Core Data**: Local persistence with CloudKit sync
- **Downloads**: `Downloads/<sourceId>/<mangaId>/<chapterId>/`
- **Narration Audio**: HLS format at `audio/{job_id}/page-{index}/index.m3u8`
- **Voice Profiles**: Zero-shot and few-shot voice training data

### Performance
- **TTFA (Time to First Audio)**: Target ≤8s warm, ≤12s cold
- **Caching**: Page-level and utterance-level caching for cost optimization
- **Rolling Windows**: 20-page batches with prioritized current page ±2
- **Background Processing**: Non-blocking audio generation

### Security & Privacy
- **Rate Limiting**: Per-IP windowed limits with Redis backing
- **Content Validation**: PNG-only uploads with size limits
- **Privacy**: Optional text storage, hash-based deduplication
- **Sandboxing**: Timeouts and memory caps on backend processing

## Roadmap

### Narration Enhancements
- [ ] Voice cloning with user-uploaded samples
- [ ] Multi-language support beyond Japanese
- [ ] Improved speaker detection accuracy
- [ ] Custom voice pack marketplace
- [ ] Offline TTS processing

### Core Features
- [ ] Enhanced source discovery
- [ ] Advanced reading modes
- [ ] Social features and recommendations
- [ ] Improved accessibility features
- [ ] Cross-device reading sync

## Support

- **Discord**: Join the [Aidoku Discord](https://discord.gg/kh2PYT8V8d) for support and discussion
- **Issues**: Report bugs and feature requests on GitHub
- **Documentation**: See `WARP.md` for detailed technical documentation
- **Website**: Visit [aidoku.app](https://aidoku.app) for user guides

---

**Aidoku** brings manga to life with cutting-edge AI narration technology while maintaining the core values of being free, open-source, and ad-free.

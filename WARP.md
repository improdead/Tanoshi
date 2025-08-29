  # WARP.md

  This file provides guidance to WARP (warp.dev) when working with code in this repository.

  Project at a glance
  - Language/targets: Swift with two primary app schemes: “Aidoku (iOS)” and “Aidoku (macOS)”.
  - Dependency manager: Swift Package Manager (SPM) via the Xcode project; dependencies are resolved by Xcode.
  - Linting: SwiftLint configured by .swiftlint.yml.
  - CI: GitHub Actions run SwiftLint and produce unsigned nightly iOS builds (IPA) using xcodebuild.

  Common CLI commands
  Note: Use a recent Xcode and have command line tools installed. For iOS builds on CI, the workflow downloads the iOS platform first; locally this is typically already present.

  Resolve SPM dependencies
  - xcodebuild -resolvePackageDependencies -project Aidoku.xcodeproj

  Build (Debug)
  - iOS Simulator (generic destination):
    - xcodebuild -scheme "Aidoku (iOS)" -destination 'generic/platform=iOS Simulator' -configuration Debug build
  - macOS:
    - xcodebuild -scheme "Aidoku (macOS)" -configuration Debug build

  Archive and produce an unsigned iOS IPA (parity with CI)
  - Archive (Release, code signing disabled):
    - xcodebuild -scheme "Aidoku (iOS)" -configuration Release archive -archivePath build/Aidoku.xcarchive -skipPackagePluginValidation CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  - Package IPA (zip the .app inside a Payload directory):
    - mkdir -p Payload && cp -r build/Aidoku.xcarchive/Products/Applications/Aidoku.app Payload && zip -r Aidoku-iOS.ipa Payload

  Lint
  - Run SwiftLint with repo config:
    - swiftlint
  - Strict mode (same as an extra CI step):
    - swiftlint --strict

  Tests
  - This project currently has no XCTest targets (the shared Xcode schemes contain no Testables). If/when tests are added, typical invocations are:
    - xcodebuild -scheme "Aidoku (iOS)" -destination 'platform=iOS Simulator,name=<Device>' test
    - Run a single test (example pattern):
      - xcodebuild -scheme "Aidoku (iOS)" -destination 'platform=iOS Simulator,name=<Device>' -only-testing:<TargetName>/<TestClass>/<testMethod> test

  High-level architecture (big picture)
  The repository is organized around a shared core (“Shared/”) consumed by separate iOS and macOS UIs. The core subsystems below collaborate through Core Data, notifications, and a WASM-based source execution layer.

  - Persistence (Core Data + CloudKit)
    - File: Shared/Managers/CoreData/CoreDataManager.swift
    - Uses NSPersistentCloudKitContainer with two stores (“Cloud” and “Local”), persistent history tracking, and remote change notifications.
    - Deduplication logic runs on incoming CloudKit mirroring transactions to prevent duplicates across key entities (Manga, Chapter, History, etc.).
    - Merge policy: property trump; viewContext automatically merges changes.
    - iCloud container ID is taken from Info.plist key ICLOUD_CONTAINER_ID or defaults to iCloud.<bundle id>.

  - Content sources and WASM integration
    - Files: Shared/Sources/* and Shared/Wasm/*, plus bridging in Shared/Extensions/AidokuRunner.swift
    - SourceManager loads installed sources from Core Data, supports import of .zip payloads (unzipped into Documents/Sources/<id>), and maintains a user-defined set of external source lists (JSON). Legacy sources are supported as a fallback.
    - AidokuRunner-based execution provides request hooks (User-Agent, cookie propagation) and Cloudflare mitigation; logs are prefixed per-source.
    - Sources are sorted with a preferred language ordering; notifications (e.g., updateSourceList, loadedSourceFilters) inform UI after loading and sorting.

  - Downloads (on-disk content cache)
    - Files: Shared/Data/Downloads/* (DownloadManager, DownloadQueue, DownloadCache, models)
    - On-disk layout: Downloads/<sourceId>/<mangaId>/<chapterId>/{ .metadata.json, 001.png, 002.png, ... }. Manga-level metadata may be stored as .manga_metadata.json.

  - Tracking integrations
    - Files: Shared/Tracking/* (OAuth flows and adapters for AniList, MyAnimeList, Shikimori)
    - Provides unified models (TrackItem, TrackStatus, TrackUpdate) and per-service API clients/queries.

  - UI layers
    - iOS: SwiftUI-first UI in iOS/New with UIKit bridges for controllers and hosting; additional UIKit-based screens in iOS/UI and iOS/Old UI.
    - macOS: SwiftUI app target under macOS/.
    - Shared models/view models live under Shared/Models and managers under Shared/Managers.

  - Logging
    - Files: Shared/Logging/*
    - Logger writes to a LogStore and optionally streams entries via HTTP POST to a configured URL; console printing can be toggled.

  - Other notable subsystems
    - Utilities for networking and image processing (e.g., Cloudflare handler, downsampling, interceptors).
    - Optional upscaling pipeline (Shared/Upscaling) built around Core ML model wrappers and multi-array helpers.

  GitHub Actions highlights
  - .github/workflows/lint.yml: Runs SwiftLint three ways (strict, PR-diff, and in a different working directory).
  - .github/workflows/nightly.yml: macOS runner builds the iOS scheme with code signing disabled, then zips the .app into an unsigned IPA and uploads as an artifact.
  - .github/workflows/update_altstore_source.yml: On release, generates and publishes AltStore source metadata to the altstore branch using a Python helper.

  Platform/runtime notes
  - iOS/iPadOS: The “Aidoku (iOS)” scheme is the primary target for development. Networking for sources is passed through the AidokuRunner hooks to add UA/cookies and to handle Cloudflare blocks (with an interactive fallback when needed).
  - macOS: The macOS scheme builds a desktop variant sharing the same core.

  Where to look first (orientation)
  - CoreDataManager.swift for persistence setup and CloudKit sync behavior.
  - SourceManager.swift and Extensions/AidokuRunner.swift for source discovery, import, and WASM execution.
  - Data/Downloads/DownloadManager.swift for on-disk structure and queue/pause/resume behavior.
  - iOS/New/* for current SwiftUI screens and view models.

  What’s new (Tanoshi Narration integration)
  - Backend scaffold (Python FastAPI + Modal) lives under backend/ with:
    - backend/modal_app.py: Modal app with SSE endpoints, presigned uploads, Redis-backed snapshots + idempotency (in-memory fallback), and MAGI/SoVITS orchestration placeholders.
    - backend/server.py: Local FastAPI server entrypoint (uvicorn) to run without Modal.
    - backend/requirements.txt: Python dependencies.
    - backend/.env.example: Example environment configuration for local dev.
    - backend/README.md: Quickstart, env vars, and notes.
  - Shared Swift module (client): Shared/Narration/
    - Models: Shared/Narration/Models/NarrationModels.swift (Codable request/response types).
    - Networking: Shared/Narration/Networking/NarrationAPI.swift (REST), Shared/Narration/Networking/SSEClient.swift (SSE streaming).
    - Upload: Shared/Narration/Upload/PageUploader.swift (presigned PNG PUTs with content-type/size validation).
  - iOS UI + Reader wiring:
    - ListenToggleView.swift is embedded in ReaderToolbarView on iOS. The Reader injects closures to start/stop and a shared ReaderNarrationViewModel instance.
    - On start, the Reader collects the current page and next 19 pages (up to 20), converts to PNG (in-memory image or fetched by URL), uploads via presigned PUT, and subscribes to SSE.
    - Playback: When a page becomes ready, and the ad gate has elapsed, audio is auto-played for the page the user is currently viewing via AVPlayer.
    - The default backend base URL is https://api.tanoshi.app (override via UserDefaults key Tanoshi.APIBase). The app assumes Modal in production; local backend is not used by default.
  - See need.md for env, infra, and open decisions.

  Local dev quickstart (backend)
  - Python 3.10+
  - Create venv and install: pip install -r backend/requirements.txt
  - Copy backend/.env.example to .env and fill values (see backend/README.md)
  - Run locally: uvicorn backend.server:app --reload --port 8080
  - Modal (optional): modal token set, then modal serve backend/modal_app.py

  iOS client quickstart
  - Build the “Aidoku (iOS)” scheme. The Listen toggle UI is provided and embedded into ReaderToolbarView on iOS.
  - Reader integration
    - Start: On toggle ON, the app collects the current page and the next 19 pages (up to 20 total) for the active chapter window.
    - Upload: Pages are uploaded via presigned PUTs (PNG only) and mapped by the index provided in the upload plan (plan.index).
    - SSE: The client subscribes to /v1/narration/jobs/{job_id}/events and updates per-page status and window progress.
    - Playback: When the user is on a page, the app auto-plays that page’s audio as soon as it’s ready and after the ad gate. Playback uses AVPlayer with HLS URLs (page-{index}/index.m3u8).
  - Config
    - The default backend base URL is https://api.tanoshi.app (override with UserDefaults key Tanoshi.APIBase).
    - The app does not use a local backend by default; Modal-hosted backend is assumed in production.
  - Next/optional
    - Rolling windows: auto-trigger /v1/narration/session/next at page ≥ (start+15) to keep audio ahead.
    - Gate duration: honor backend adPlan.duration_hint when available for precise gating.

  Troubleshooting
  - SSE connectivity: Ensure CORS (CORS_ORIGINS) includes the app’s custom scheme and localhost when testing.
  - Upload failures: PageUploader enforces image/png and size limits; check S3 policy and BUCKET_* settings.
  - Cold starts (Modal): Expect higher TTFA on first request; see the “Backend (Modal, Python) quickstart” and “Modal cost & latency” notes below for mitigation tips.

  WARP.md — Tanoshi Narration (Python on Modal: MAGI v2 → GPT-SoVITS)

  Implementation status at a glance
  - Implemented now (stubbed where noted)
    - Session start/next endpoints with presigned PNG uploads (placeholders)
    - SSE events: page_status, page_ready, progress, job_done; initial state burst on connect
    - Snapshot endpoint; Redis snapshot persistence with TTL; in-memory fallback + TTL cleanup
    - Rate limiting (per-IP, windowed) for start/next; Redis-backed when available
    - Idempotency for /session/start (dedupe by chapter_id + window + voice_pack) via Redis (fallback in-memory)
    - Voices register/get (presigned refs, dataset only for few_shot)
    - Env-driven CDN_BASE_URL in audio URLs
  - Not implemented (to be built)
    - Real MAGI v2 OCR/speaker extraction and GPT-SoVITS synthesis pipeline
    - Real presigned S3/MinIO URLs and upload validation hooks
    - Multi-worker orchestration, prioritization (current page ±2), retries
    - Persistent job store (DB/Redis as source of truth across restarts/scale-out)
  - Suggestions / next steps
    - Add separate IDEMP_TTL_SECONDS if different from job TTL is desired
    - Consider a /v1/narration/jobs/{job_id} metadata endpoint (created_at, updated_at)
    - Wire rolling windows auto-trigger from iOS at ≥ start+15
    - Optional single-file per-page audio (m4a) for simpler offline cache

  This file guides the manga → audiobook pipeline that runs when a reader toggles Listen in Tanoshi.
  Backend: Python (FastAPI) deployed on Modal. All endpoints are implemented in Python; GPU workers run MAGI v2 and GPT-SoVITS in separate containers.

  Project at a glance

  Flow: App → Modal (Python) → PNG pages (no base64) → MAGI v2 (chapter-wide extraction) → GPT-SoVITS (voices) → App

  Batching: 20 PNG pages per request (rolling window for long chapters)

  Trigger: User flips Listen toggle → show placeholder ad → background processing starts immediately

  Playback: When the user is on page N, auto-play page N’s audio as soon as it is ready, after the ad gate (per 20-page request)

  Status: Per-page chips show Queued / Extracting / TTS / Ready / Error + a slim global progress bar

  Storage: Per-page HLS under audio/{job_id}/page-{index}/index.m3u8

  SSE: Real-time job/status events drive UI progress

  Endpoints (stateless, SSE-driven)
  Implementation: Python (FastAPI/Starlette) on Modal; SSE via text/event-stream; presigned S3-compatible URLs for PNG uploads and HLS reads.
  POST /v1/narration/session/start

  Begin a 20-page window. In the stub, processing starts immediately (simulating cold-start hide); production will start MAGI after an arrival threshold (e.g., N/20 uploads). Returns 20 presigned PUT URLs for PNG upload.

  Body

  {
    "chapter_id": "series123:ch045",
    "voice_pack": {
      "Narrator": "sovits:narrator-v1",
      "MC": "sovits:mc-v1"
    },
    "window": { "start_index": 0, "size": 20 },
    "client": { "device": "ios", "app_version": "1.0.0" }
  }


  200 OK

  {
    "job_id": "job_abc",
    "upload": {
      "mode": "presigned",
      "pages": [
        {"index":0,"put_url":"https://...","content_type":"image/png","max_bytes":3000000},
        {"index":1,"put_url":"https://..."},
        {"index":19,"put_url":"https://..."}
      ]
    },
    "status_sse": "https://api.tanoshi.app/v1/narration/jobs/job_abc/events",
    "audio_url_template": "https://cdn.tanoshi.app/audio/job_abc/page-{index}/index.m3u8",
    "adPlan": {"kind":"placeholder","duration_hint":3}
  }


  Errors

  400 invalid window/voice

  429 rate limit

  5xx transient (retry with jitter)

  Note: PNG is enforced by the client and object-store policy; the API returns presigned PUTs with content_type=image/png and does not receive file bytes.

  POST /v1/narration/session/next (rolling windows)

  Start the next 20 pages; same response shape. window.start_index = 20, 40, …

  GET /v1/narration/jobs/{job_id}/events (SSE)

  Real-time progress for chips + progress bar. text/event-stream with events:

  page_status
  {"index":7,"state":"queued|extracting|tts|ready|error","reason":null}

  page_ready
  {"index":7,"audio":"https://cdn/.../page-7/index.m3u8","duration":13.2}

  progress
  {"done":5,"total":20}

  job_done
  {"ok":true}

  On reconnect, the client should resubscribe and call /snapshot to restore state.

  Server notes (reconnect): the backend does not implement cursor/Last-Event-ID. It now emits an initial state burst (page_status for each page + progress) on new connections to help restore UI, but clients should still call /snapshot after reconnect.

  GET /v1/narration/jobs/{job_id}/snapshot

  One-shot JSON to restore UI after relaunch.

  200 OK

  {
    "job_id":"job_abc",
    "pages":[
      {"index":0,"state":"ready","audio":"https://cdn/.../page-0/index.m3u8"},
      {"index":1,"state":"tts"},
      {"index":2,"state":"extracting"}
    ],
    "progress":{"done":5,"total":20}
  }

  Voice Profiles (cloned voices)

  We support zero-shot (no training, use a short reference clip) and few-shot / fine-tuned GPT-SoVITS voices (speaker-specific checkpoint). Use these to build “anime-style” voice packs.

  POST /v1/voices/register

  Register a new voice.

  Body

  {
    "name": "MC v1",
    "engine": "sovits",
    "mode": "zero_shot",               // or "few_shot"
    "lang_hint": "ja"
  }


  200 OK

  {
    "voice_id":"sovits:mc-v1",
    "upload": {
      "mode": "presigned",
      "refs": [
        {"purpose":"zero_shot_ref","put_url":"https://..."}  // single 5–30s WAV/FLAC for zero-shot
      ],
      "dataset": {                                           // only for few-shot
        "audio_put_prefix":"https://.../clips/{i}.wav",
        "transcript_put_url":"https://.../transcripts.jsonl"
      }
    },
    "status_sse":"https://api/voices/sovits:mc-v1/events"
  }


  Zero-shot: upload one clean 5–30s reference. Backend caches a speaker embedding or SoVITS conditioning features.

  Few-shot: upload many clips + transcripts; backend trains a speaker checkpoint.

  GET /v1/voices/{voice_id}

  Voice metadata.

  {
    "voice_id":"sovits:mc-v1",
    "engine":"sovits",
    "mode":"few_shot",
    "status":"ready",              // or "training"
    "languages":["ja"],
    "sample_rate":24000,
    "preview":"https://cdn/.../preview.m4a"
  }


  (Optional) POST /v1/voices/{voice_id}/train kicks off training if assets were uploaded previously.

  States & events (SSE reference)

  Per-page states
  queued → extracting (MAGI) → tts (SoVITS) → ready (or error)

  SSE examples

  event: page_status
  data: {"index":7,"state":"extracting"}

  event: page_status
  data: {"index":7,"state":"tts"}

  event: page_ready
  data: {"index":7,"audio":"https://cdn/audio/job_abc/page-7/index.m3u8","duration":13.2}

  event: progress
  data: {"done":5,"total":20}

  event: job_done
  data: {"ok":true}

  Data contracts

  MAGI output (per page)

  {
    "page_index": 7,
    "lines": [
      {"speaker":"MC","text":"...","lang":"ja","role":"speech"},
      {"speaker":"Narrator","text":"...","role":"narration"}
    ]
  }


  SoVITS request (utterance)

  {
    "page_index":7,
    "speaker":"MC",
    "text":"...",
    "voice_id":"sovits:mc-v1",
    "speed":1.0,
    "pitch":0.0
  }

  Storage layout (object store)
  /narration/{job_id}/
    pages/
      000.png … 019.png
    magi/
      page-000.json … page-019.json
    audio/
      page-000/
        index.m3u8
        seg-00001.ts …
      page-001/ …
    status/
      snapshot.json

  /voices/{voice_id}/
    manifest.json               # name, engine: "sovits", mode: "zero_shot"|"few_shot", status
    samples/                    # uploaded ref audio (raw, zero-shot)
    embedding.bin               # optional cached conditioning (zero-shot)
    checkpoint.pth              # few-shot trained voice
    preview.m4a                 # audition clip

  Note: The stub serves /snapshot from memory and does not yet persist job snapshots; production will write status/snapshot.json and evict stale in-memory JOBS entries (TTL).

  Caching & idempotency

  Page key: page:{blake3(png_bytes)}:magi.json

  Utterance key: tts:{voice_id}:{sha256(text|prosody)}.ogg

  Page audio key: page-audio:{job_id}:{index} (HLS playlist + segments)

  Voice cache:

  Zero-shot: keep speaker conditioning in RAM (tiny).

  Few-shot: small LRU of checkpoints loaded per GPU worker.

  Always check caches before work; page/utterance caches drastically reduce cost and TTFA.

  UX policy (important)

  Listening is off by default. After the user toggles it on, audio auto-plays for the current page once ready (after the ad gate).

  Ad placeholder first; processing starts behind it.

  Visible Listen toggle (same style as existing toolbar).

  Per-page chip + global progress bar.

  Retry on a single page if it errors (re-queues only that page).
  - While the placeholder ad is showing, processing begins immediately and continues in the background.
  - If the user tries to play before a page is ready, show a subtle “Processing…” state and disable Play until page_ready.

  Security & limits

  Uploads: PNG only; enforce Content-Type: image/png and size caps; short-TTL presigned PUTs.

  Downloads: signed GETs; no directory listing; CDN cache with versioned keys.

  Rate-limits: /start, /next, and uploads per device/IP; Redis-backed idempotency for /session/start (fallback to in-memory when Redis is absent).

  Rate limiting & Redis (implementation status)
  - The backend now supports simple per-IP windowed rate limiting for /session/start and /session/next.
  - Redis is used when REDIS_URL is set; otherwise an in-memory fallback is used.
  - Snapshots are persisted in Redis with TTL (JOB_TTL_SECONDS, default 3600s). In-memory jobs are evicted by a background cleaner after the same TTL.
  - Idempotency: /session/start dedupes by (chapter_id, window.start_index/size, voice_pack) and returns the existing job_id if found.
  - Namespacing: rl:{kind}:{ip}, narration:job:{job_id}:snapshot, narration:idemp:{sha256(canonical-payload)}

  Privacy: store page hashes/derived text only if required; provide delete-by-hash.

  Sandboxing: timeouts, memory caps, whitelisted write paths on backend.

  SLOs & observability

  p95 time-to-first-ready page (TTFA): ≤ 6–8s (warm), ≤ 12s (cold)

  Metrics: MAGI latency (batch & per page), SoVITS latency (per utterance), cache hit-rates (page/utterance), GPU utilization, TTFA, per-page success %, ad impressions.

  Structured logs per job_id/page_index; redact text if not needed.

  Scaling & cost

  Keep one warm MAGI GPU and one warm SoVITS GPU to minimize TTFA; autoscale with small buffers for peaks.

  Short utterances (2–5s) → better caching and recovery.

  Use windowing (20 pages) and priority current page ±2 in SoVITS queue.

  Modal cost & latency (pay less, start faster)

  - Bake the environment once
    - Build a custom modal.Image with your apt + pip deps (torch, ffmpeg, etc.).
    - On cold start, Modal just pulls the image; it won’t run pip again.

  - Persist model weights
    - Put MAGI v2 and GPT-SoVITS weights in a Modal Volume.
    - Mount read-only at /models during inference to avoid re-downloading each start.
    - You still pay compute to load weights into RAM/GPU when a container starts.

  - Warm-up on container start (only when needed)
    - Use a lifecycle @enter() hook to load models once per container start.
    - Eliminates per-request load time; front-loads on each new container.

  - Avoid paid “keep warm” unless you must
    - Cold-start controls (scaledown_window, min_containers, buffer) reduce latency but increase cost.
    - Default idle shutdown ≈ 60s. Raising it or pinning min_containers keeps instances alive (billable).

  - Practical template (no idle cost, faster cold starts)

  ```python
  import modal

  # 1) Pre-baked image (no runtime pip)
  image = (
      modal.Image.debian_slim()
      .apt_install("ffmpeg")
      .pip_install(
          "torch==2.3.1", "torchaudio==2.3.1",
          "transformers==4.43.3",  # example if MAGI uses HF stack
          "soundfile", "numpy"
      )
  )

  # 2) Persistent model volume
  models = modal.Volume.from_name("tanoshi-models", create_if_missing=True)

  app = modal.App("tanoshi-narration")

  # One-time job to populate the volume (run manually or in CI)
  @app.function(image=image, volumes={"/models": models})
  def download_models():
      import os, subprocess, pathlib
      root = pathlib.Path("/models")
      root.mkdir(exist_ok=True, parents=True)
      # idempotent downloads (MAGI v2 weights, SoVITS checkpoint / refs)
      # e.g., subprocess.run(["curl", "-L", URL, "-o", str(root/"magi.bin")], check=True)
      #       subprocess.run(["curl", "-L", URL, "-o", str(root/"sovits.pth")], check=True)

  # 3) GPU inference class with warm-up at container start
  @app.cls(
      image=image,
      gpu="L4",                      # or "A10G"/"A100" as needed
      volumes={"/models": models},   # read-only by default
  )
  class SoVITSService:
      @modal.enter()
      def load(self):
          # Load weights from /models into RAM / GPU once per container
          # e.g., self.tts = load_sovits("/models/sovits.pth")
          #       self.magi = load_magi("/models/magi.bin")
          pass

      @modal.method()
      def synth(self, page_json: dict) -> str:
          # run MAGI → build utterances → SoVITS → write HLS to storage
          # return public URL
          return "https://cdn.example.com/audio/..."
  ```

  Cold start path: container pulls the pre-baked image (no pip), mounts /models (already populated), runs @enter() to load weights, then serves requests.

  No idle charge: you’re not pinning instances; they scale to zero after idle.

  Still want lower latency? Optionally set scaledown_window=600 or min_containers=1—accepting a small ongoing cost.

  Open questions / next actions

  - Finalize voice catalog and speaker routing (Narrator vs MC vs Others).
  - Choose window threshold: require all 20 PNGs or allow N/20 to start MAGI for faster TTFA.
  - Lock HLS as page format (recommended over single-clip).
  - Define training quotas and moderation for user-submitted voices (legal/consent).
  - Add /session/next UI wiring for rolling windows.
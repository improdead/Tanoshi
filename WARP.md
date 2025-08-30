  # WARP.md

  This file provides guidance to WARP (warp.dev) when working with code in this repository.

  Project at a glance
  - App name: Tanoshi (renamed from Aidoku in this repo)
  - Language/targets: Swift with two primary app schemes: “Tanoshi (iOS)” and “Tanoshi (macOS)”.
  - Dependency manager: Swift Package Manager (SPM) via the Xcode project; dependencies are resolved by Xcode.
  - Linting: SwiftLint configured by .swiftlint.yml.
  - CI: GitHub Actions run SwiftLint and produce unsigned nightly iOS builds (IPA) using xcodebuild.

  Common CLI commands
  Note: Use a recent Xcode and have command line tools installed. For iOS builds on CI, the workflow downloads the iOS platform first; locally this is typically already present.

  Resolve SPM dependencies
  - xcodebuild -resolvePackageDependencies -project Aidoku.xcodeproj

  Build (Debug)
  - iOS Simulator (generic destination):
    - xcodebuild -scheme "Tanoshi (iOS)" -destination 'generic/platform=iOS Simulator' -configuration Debug build
  - macOS:
    - xcodebuild -scheme "Tanoshi (macOS)" -configuration Debug build

  Archive and produce an unsigned iOS IPA (parity with CI)
  - Archive (Release, code signing disabled):
    - xcodebuild -scheme "Tanoshi (iOS)" -configuration Release archive -archivePath build/Tanoshi.xcarchive -skipPackagePluginValidation CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  - Package IPA (zip the .app inside a Payload directory):
    - mkdir -p Payload && cp -r build/Tanoshi.xcarchive/Products/Applications/Tanoshi.app Payload && zip -r Tanoshi-iOS.ipa Payload

  Lint
  - Run SwiftLint with repo config:
    - swiftlint
  - Strict mode (same as an extra CI step):
    - swiftlint --strict

  Tests
  - This project currently has no XCTest targets (the shared Xcode schemes contain no Testables). If/when tests are added, typical invocations are:
    - xcodebuild -scheme "Tanoshi (iOS)" -destination 'platform=iOS Simulator,name=<Device>' test
    - Run a single test (example pattern):
      - xcodebuild -scheme "Tanoshi (iOS)" -destination 'platform=iOS Simulator,name=<Device>' -only-testing:<TargetName>/<TestClass>/<testMethod> test

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
  - Backend (Python FastAPI + Modal) lives under backend/ with:
    - backend/modal_app.py: Modal app with SSE endpoints, direct PNG PUT uploads into a Modal Volume, Redis-backed snapshots + idempotency (in-memory fallback), MAGI v2 OCR integrated (Hugging Face), and TTS placeholder (dummy HLS).
    - backend/server.py: Local FastAPI server entrypoint (uvicorn) to run without Modal.
    - backend/requirements.txt: Python dependencies.
    - backend/.env.example: Example environment configuration for local dev.
    - backend/README.md: Quickstart, env vars, and notes.
  - Shared Swift module (client): Shared/Narration/
    - Models: Shared/Narration/Models/NarrationModels.swift (Codable request/response types).
    - Networking: Shared/Narration/Networking/NarrationAPI.swift (REST), Shared/Narration/Networking/SSEClient.swift (SSE streaming).
    - Upload: Shared/Narration/Upload/PageUploader.swift (direct PNG PUTs to API with content-type/size validation).
  - iOS UI + Reader wiring:
    - ListenToggleView.swift is embedded in ReaderToolbarView on iOS. The Reader injects closures to start/stop and a shared ReaderNarrationViewModel instance.
    - On start, the Reader collects the current page and next 19 pages (up to 20), converts to PNG (in-memory image or fetched by URL), uploads via direct PUT to API, and subscribes to SSE.
    - Playback: When a page becomes ready, and the ad gate has elapsed, audio is auto-played for the page the user is currently viewing via AVPlayer.
    - The default backend base URL is https://api.tanoshi.app (override via UserDefaults key Tanoshi.APIBase). The app assumes Modal in production; local backend is not used by default.
  - See need.md for env, infra, and open decisions.

  Local dev quickstart (backend)
  - Python 3.10+
  - Create venv and install: pip install -r backend/requirements.txt
  - Copy backend/.env.example to .env and fill values (see backend/README.md)
  - Run locally: uvicorn backend.server:app --reload --port 8080
  - Modal (optional): modal token set, then modal serve backend/modal_app.py

  Backend (Modal) quickstart
  - Prereqs
    - Python 3.10+ and `pip install modal` (or `pipx install modal`)
    - Login: `modal token set`
  - Create persistent volumes
    - `modal volume create tanoshi-models`
    - `modal volume create tanoshi-data`
  - Create env secret (bound to all Modal functions in code as `tanoshi-env`)
    - `modal secret create tanoshi-env`
    - Add keys (example):
      - `API_BASE_URL=https://api.tanoshi.app` (or leave unset; backend uses the incoming request host)
      - `CDN_BASE_URL=https://cdn.tanoshi.app` (HLS served by API today; CDN optional)
      - `CORS_ORIGINS=aidoku://,http://localhost:8080`
      - `JOB_TTL_SECONDS=3600`
      - `RATE_LIMIT_WINDOW_SECONDS=60`, `RATE_LIMIT_START_MAX=10`, `RATE_LIMIT_NEXT_MAX=20`
      - Optional: `REDIS_URL=redis://...` for snapshots/idempotency
      - Optional: `MAGI_START_AFTER_N_PAGES=4`
  - Develop: `modal serve backend/modal_app.py`
    - Prints a dev URL like `https://<acct>--tanoshi-narration.modal.run`. Visit `/web` to test uploads + SSE.
  - Deploy: `modal deploy backend/modal_app.py`
    - Yields a stable production URL on `modal.run`. Point your client to your own domain (see below) and set `API_BASE_URL` accordingly.
  - No custom domain? Totally fine for MVP.
    - Use the printed `*.modal.run` URL directly in the iOS build or via `UserDefaults` key `Tanoshi.APIBase`.
    - Leave `API_BASE_URL` unset; the backend infers the base from each request and returns absolute URLs with the correct host.
  - iOS dev convenience (temporary):
    - We set `UserDefaults` default `Tanoshi.APIBase` to the deployed Modal URL in `iOS/AppDelegate.swift` so debug builds just work out of the box. Update or remove before release.

  Hide the Modal URL (production)
  - Recommended: Put your own domain (e.g., `api.tanoshi.app`) in front of Modal.
    - Option A — DNS CNAME + proxy: Point `api.tanoshi.app` (proxied via Cloudflare) to your Modal host `<acct>--tanoshi-narration.modal.run`.
    - Option B — Reverse proxy (Cloudflare Worker / Vercel / NGINX): Forward all paths to the Modal URL and pass through headers. Ensure streaming works for SSE (`text/event-stream`). Example Cloudflare Worker:
      ```js
      export default { async fetch(req, env) {
        const upstreamHost = env.UPSTREAM_HOST; // "<acct>--tanoshi-narration.modal.run"
        const url = new URL(req.url); url.hostname = upstreamHost; url.protocol = 'https:';
        const h = new Headers(req.headers); h.set('host', upstreamHost);
        const resp = await fetch(url.toString(), { method: req.method, headers: h, body: req.body, redirect: 'follow' });
        return new Response(resp.body, { status: resp.status, statusText: resp.statusText, headers: resp.headers });
      }}
      ```
  - The backend now returns absolute URLs using the current request host if `API_BASE_URL` is not set, so your users never see `modal.run` when calling through your domain.

  Notes
  - The FastAPI app is exposed via `@app.function(...).asgi_app()` and binds the `tanoshi-env` secret. For the MVP, the ASGI function runs on an L4 GPU (single container) to keep MAGI snappy. Later, you can split CPU web + GPU worker to reduce cost.
  - Per-page readiness is now strict: a page is marked `ready` only after its PNG exists and MAGI JSON is available; missing/failed pages are marked `error` with a `reason`. The synthesizer inserts ~250ms silences between utterances for intelligibility.
  - Create voices and uploads under `/models` and `/data` volumes; these persist across runs.

  iOS client quickstart
  - Build the “Tanoshi (iOS)” scheme. The Listen toggle UI is provided and embedded into ReaderToolbarView on iOS.
  - Reader integration
    - Start: On toggle ON, the app collects the current page and the next 19 pages (up to 20 total) for the active chapter window.
    - Upload: Pages are uploaded via direct PUTs (PNG only) to the API and mapped by the index provided in the upload plan (plan.index). For pages already in memory or on disk (local source), the app uses those bytes; for online‑only pages, it fetches the image and re‑encodes to PNG before upload. For local PDFs, pages are pre‑converted to PNG on import (CBZ), so uploads are consistent. If a page is stored in a CBZ/ZIP, the app extracts the image and re-encodes to PNG if needed before upload.
    - SSE: The client subscribes to /v1/narration/jobs/{job_id}/events and updates per-page status and window progress.
    - Playback: When the user is on a page, the app auto-plays that page’s audio as soon as it’s ready and after the ad gate. Playback uses AVPlayer with HLS URLs (page-{index}/index.m3u8).
    - UI: The Listen control is a compact icon button (ear symbol) in the reader toolbar. Long-press shows a quick status bubble (X/Y ready; green dot if any ready). Tapping toggles Listen on/off.
  - Config
    - The default backend base URL is https://api.tanoshi.app (override with UserDefaults key Tanoshi.APIBase).
    - The app does not use a local backend by default; Modal-hosted backend is assumed in production.
  - Content sources (Tanoshi specifics)
    - Local sources: PDF import is supported. On import, PDFs are converted into CBZ (ZIP of per‑page PNGs) so reading behaves like image archives. Listen reads the in‑app image (or on‑disk file) and uploads PNG bytes to the backend. Network is still required to send PNGs and receive audio.
    - Community/online sources: Listen first uses an in‑memory image if present; otherwise it fetches the page image URL and re‑encodes to PNG for upload. This requires network and respects any source‑specific headers already handled by the app’s reader pipeline.
    - Offline mode: Without network, Listen is disabled (uploads + SSE + HLS require connectivity).
  - Next/optional
    - Rolling windows: auto-trigger /v1/narration/session/next at page ≥ (start+15) to keep audio ahead.
    - Gate duration: honor backend adPlan.duration_hint when available for precise gating.

  Troubleshooting
  - SSE connectivity: Ensure CORS (CORS_ORIGINS) includes the app’s custom scheme and localhost when testing.
  - Upload failures: PageUploader enforces image/png and size limits; check S3 policy and BUCKET_* settings.
  - Cold starts (Modal): Expect higher TTFA on first request; see the “Backend (Modal, Python) quickstart” and “Modal cost & latency” notes below for mitigation tips.
  - MAGI on empty input: The backend guards against running MAGI with an empty chapter page list if no uploads arrive before the wait window. It returns and retries once enough pages are uploaded.
  - Debug web UI and typed SSE: The /web debug page listens for typed SSE events (page_status, page_ready, progress, job_done) so you can see the exact events emitted by the API.
  - Redis (multi‑instance): Set `REDIS_URL` in the `tanoshi-env` secret to enable:
    - Idempotency and snapshots in Redis with TTL (`JOB_TTL_SECONDS`, default 3600s).
    - Cross‑instance SSE via Redis Pub/Sub. The API publishes every event to `narration:job:{job_id}:events`; SSE subscribers read from Pub/Sub, with local queue fallback.
    - If an instance receives an upload or SSE connect for an unknown job, it reconstructs minimal state from Redis snapshot (or a stub) instead of returning 404.
  - Memory budget (Redis 30 MB): Snapshots are compact JSON (~few KB per job). TTL cleanup keeps memory bounded. Rate-limit counters expire after 60s; idempotency keys expire after `IDEMP_TTL_SECONDS`.
  - Config snippet: add this to `tanoshi-env`:
    - `REDIS_URL=redis://default:<password>@redis-15361.c265.us-east-1-2.ec2.redns.redis-cloud.com:15361`

  WARP.md — Tanoshi Narration (Python on Modal: MAGI v2 → GPT-SoVITS)

  

  This file guides the manga → audiobook pipeline that runs when a reader toggles Listen in Tanoshi.
  Backend: Python (FastAPI) deployed on Modal. All endpoints are implemented in Python; GPU workers run MAGI v2 and GPT-SoVITS in separate containers.

  Project at a glance

  Flow: App → Modal (Python) → PNG pages (no base64) → MAGI v2 (chapter-wide extraction) → GPT-SoVITS (voices) → App

  Batching: 20 PNG pages per request (rolling window for long chapters)

  Trigger: User flips Listen toggle → show placeholder ad → background processing starts immediately

  Playback: When the user is on page N, auto-play page N’s audio as soon as it is ready, after the ad gate (per 20-page request)

  Status: Per-page chips show Queued / Extracting / TTS / Ready / Error + a slim global progress bar

  Storage: Per-page HLS under audio/{job_id}/page-{index}/index.m3u8 (MIME: application/vnd.apple.mpegurl; segments: video/MP2T)

  SSE: Real-time job/status events drive UI progress

  
  Narration Stability + Cost Fix (Aug 30)
  - Summary: Addressed iOS upload timeouts and high Modal GPU cost by adding batch uploads, deferring compute until uploads arrive, adding keep-warm for GPU model load, and enhancing HLS diagnostics.
  - New endpoint: POST /v1/narration/jobs/{job_id}/pages/batch
    - Accepts multipart/form-data (fields page_0..page_19 or page_00..page_19) or application/zip (000.png..019.png).
    - Writes images to /data/narration/{job}/pages/{i}.png, emits page_status:extracting per saved page, and triggers the MAGI threshold.
    - Response: {accepted: N, failed: [reasons], total_bytes: X}.
    - Keep legacy PUT /v1/narration/jobs/{job_id}/pages/{i} for compatibility.
  - Deferred processing: The backend no longer wastes time before uploads arrive.
    - MAGI begins only after MAGI_START_AFTER_N_PAGES uploads or explicit begin via crossing the threshold.
    - upload_page and /pages/batch ensure the processing loop is running even if /session/start happened on another instance.
  - GPU warming: The GPU worker class sets keep_warm=1 and preloads MAGI at @enter.
    - backend/modal_app.py:144 (NarrationService) loads ragavsachdeva/magiv2 once, eval() with cuda/half where available.
  - HLS diagnostics: The backend logs when HLS is written/served.
    - [hls] job=… page=… segs=N playlist_bytes=M (after writing playlist)
    - [serve_playlist] … and [serve_segment] … on each request
    - File refs: backend/modal_app.py:485, backend/modal_app.py:1115
  - iOS uploader guidance (client changes recommended):
    - Prefer /pages/batch; fallback to per-page PUTs if /batch 404.
    - Throttle concurrent PUTs to 3–4; exponential backoff + jitter on -1001; max 2 retries; 120s timeout; downscale long edge to ~1600 px.

  Error symptoms and root cause
  - iOS timeouts: NSURLErrorDomain Code=-1001 on many PUTs; example indices 1,2,4,5,6,8,10,11,14,15,16,17,18.
    - Cause: 20 simultaneous uploads queue behind cold/warm starts; client default timeout expires.
  - Server 500 with ClientDisconnect:
    - Traceback shows starlette.requests.ClientDisconnect while the server tries to read a body after the client timed out.
    - Example: PUT /v1/narration/jobs/{job}/pages/14 → 500 Internal Server Error (duration ~69s, execution ~62s) paired with iOS -1001.
  - No audio heard on processed page:
    - Previously possible if HLS packaging produced a minimal or missing playlist or if the client never requested the playlist URL.
    - Added [hls]/[serve_*] logs to confirm file creation and client fetches; a short tone/beep fallback remains in place to ensure audible output during failures.

  What changed (backend)
  - Batch uploads: /v1/narration/jobs/{job_id}/pages/batch saves multiple pages atomically and emits events per page.
  - Cross-instance kick: upload routes start the processing loop if it isn’t running yet.
  - HLS logs: Emitted after writing to help debug audio path.
  - GPU warm class: keep_warm=1 and preload MAGI for future GPU offload.

  Next steps (optional, cost)
  - Split GPU from CPU: run only MAGI on a GPU class/function; run TTS + ffmpeg on CPU-only function; free GPU immediately after MAGI (Phase 2 in PLAN.md).
  - Cache HF assets: set TRANSFORMERS_CACHE/HF_HOME to persist under /models/hf to avoid cold re-downloads.
  - Right-size resources: lower CPU/RAM on GPU function; raise only on CPU TTS if needed.

  iOS note — Core Data warning
  - If you see “History Change Request failed as no history tracking option detected on store … Local.sqlite”, enable persistent history tracking on the Local store:
    - Set `NSPersistentHistoryTrackingKey = true` on the Local `NSPersistentStoreDescription`.
    - Optionally set `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true` if you listen for remote changes.

  Endpoints (stateless, SSE-driven)
  Implementation: Python (FastAPI/Starlette) on Modal; SSE via text/event-stream. For Modal-only MVP we use direct API PUTs into a Modal Volume (no S3/CDN yet). HLS is packaged with ffmpeg into TS segments with independent segments.
  GET /web

  Minimal debug page to start a session, upload local PNGs, and watch SSE events directly in a browser.
  POST /v1/narration/session/start

  Begin a 20-page window. In Modal-only MVP, returns 20 direct PUT URLs to upload PNGs into a Modal Volume. Processing starts in the background (MAGI waits for uploads).

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
      "mode": "direct",
      "pages": [
        {"index":0,"put_url":"/v1/narration/jobs/job_abc/pages/0","content_type":"image/png","max_bytes":3000000},
        {"index":1,"put_url":"/v1/narration/jobs/job_abc/pages/1"},
        {"index":19,"put_url":"/v1/narration/jobs/job_abc/pages/19"}
      ]
    },
    "status_sse": "/v1/narration/jobs/job_abc/events",
    "audio_url_template": "/v1/narration/jobs/job_abc/audio/page-{index}/index.m3u8",
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
    "cache_key": "<blake3>",
    "lines": [
      {"speaker":"MC","text":"...","lang":"ja","role":"speech"},
      {"speaker":"Narrator","text":"...","role":"narration"}
    ]
  }


  SoVITS request (utterance)

  {
    "page_index":7,
    "speaker":"MC",
    "text":"...",  // sanitized (no <other> etc.)
    "voice_id":"sovits:mc-v1",
    "speed":1.0,
    "pitch":0.0
  }

  Storage layout (Modal Volume /data; standardized TS segments)
  /data/narration/{job_id}/
    pages/
      000.png … 019.png
    magi/
      page-000.json … page-019.json
    audio/
      page-000/
        index.m3u8
        seg-00001.ts …   # video/MP2T
      page-001/ …
    status/ (future)
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
  
  Appendix — Implementation status & recent changes
  
  What’s implemented (works in the current repo)
  - iOS Reader wiring: ListenToggle embedded in ReaderToolbarView; ReaderViewController drives start/stop, uploads, SSE subscription, and auto-play after ad gate.
  - Shared narration client: models, REST client, SSE client, and uploader supports direct PUT URLs with content-type/size enforcement.
  - Backend (Modal-only MVP): start/next endpoints, direct PNG PUT upload to Modal Volume, MAGI v2 inference via HF (`ragavsachdeva/magiv2`, trust_remote_code=True) across chapter pages (begin after N uploads for lower TTFA) with autocast+no_grad when CUDA available, dummy HLS generation with ffmpeg (`-f hls -hls_time 2 -hls_segment_type mpegts -hls_flags independent_segments -hls_list_size 0`), SSE (page_status/page_ready/progress/job_done) with initial state burst, snapshot endpoint.
  - Redis (optional): snapshot persistence with TTL and idempotency for /session/start; per-IP rate limiting for start/next (in-memory fallbacks exist).
  - Docs: WARP.md reorganized with Modal-only flow; need.md lists required env/secrets/infra decisions.
  
  Not implemented yet (to build next)
  - GPT-SoVITS voice synthesis (currently dummy HLS silence is generated). Voice cloning/training TBD.
  - Real presigned S3/MinIO URLs and server-side object validation (Modal-only now).
  - Orchestration for multi-workers, prioritization (current page ±2), retries, and persistent job store as source of truth.
  - iOS rolling windows: auto-trigger /v1/narration/session/next at page ≥ start+15 (optional feature flag).
  - macOS Reader mounting point for Listen toggle and playback UI.

  Recent hardening
  - MAGI loads off the event loop (background thread) to avoid blocking uploads/SSE on cold start.
  - MAGI begins after N pages uploaded, then re-runs incrementally as late pages arrive.
  - HLS segments validated strictly (seg-\d+.ts) to prevent path traversal.

  Pseudocode (current backend, Modal-only)
  ```
  POST /v1/narration/session/start
    new job_id → init pages[]=queued
    spawn background task(_process_job)
    return direct PUT plans: /v1/narration/jobs/{job}/pages/{i}

  PUT /v1/narration/jobs/{job}/pages/{i}
    validate image/png, ≤3MB → write /data/narration/{job}/pages/{i}.png
    pages[i]=extracting; signal magi_start_event if uploaded_pages≥N

  _process_job(job)
    await in thread: load MAGI (HF trust_remote_code, optional revision)
    await magi_start_event (or timeout)
    run MAGI over available pages (skip magi_done_pages) → write magi/page-*.json
    for i in 0..19:
      emit extracting→tts; build dummy HLS (ffmpeg hls ts) for page i
      set ready + audio URL; emit progress
    spawn watcher: if late pages arrive, rerun MAGI (skip done)

  GET /v1/narration/jobs/{job}/audio/page-{i}/index.m3u8 → read from /data
  GET /v1/narration/jobs/{job}/audio/page-{i}/seg-*.ts (strict regex)

  POST /v1/voices/register → returns direct PUT endpoints (refs, clips, transcripts)
  PUT /v1/voices/{voice}/refs/ref.wav → store under /models/voices/{voice}/
  ```

  Technical implementation notes
  - MAGI v2 OCR is integrated and runs (CUDA if available).
  - TTS:
    - Default: `espeak-ng` offline TTS (robotic voice) for immediate end‑to‑end testing.
    - GPT‑SoVITS: supported when `SOVITS_ENABLED=true` and the repo + checkpoints exist under `/models/GPT-SoVITS`. The code attempts to import a `TTS` API from the repo and synthesize WAVs using a voice reference if present. If import/call fails, it falls back to `espeak-ng`.
    - Provide your own legal/licensed GPT‑SoVITS weights via `SOVITS_MODEL_URLS` env and run `modal run backend/modal_app.py::download_models` to populate `/models`.
  
  Recent changes (pushed)
  - Commit: 548bf1a — “Add narration features and backend improvements”.
  - Scope: 16 files changed, 1,761 insertions, 291 deletions.
  - New files
    - Shared/Narration/Models/NarrationModels.swift
    - Shared/Narration/Networking/NarrationAPI.swift
    - Shared/Narration/Networking/SSEClient.swift
    - Shared/Narration/Upload/PageUploader.swift
    - iOS/New/Views/Reader/ListenToggleView.swift
    - iOS/New/Views/Reader/ReaderNarrationViewModel.swift
    - backend/.env.example, backend/README.md, backend/modal_app.py, backend/requirements.txt, backend/server.py
    - need.md
  - Modified files
    - Aidoku.xcodeproj/project.pbxproj (registered new files in targets)
    - WARP.md (organized guidance; implementation status; SSE/Redis/TTL notes)
    - iOS/UI/Reader/ReaderToolbarView.swift (hosts Listen toggle)
        - iOS/UI/Reader/ReaderViewController.swift (toggle wiring, uploads, SSE playback, ad gate)

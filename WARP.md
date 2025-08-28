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
  - DownloadManager orchestrates queueing, pause/resume, cancel, deletion, and status reporting; posts notifications (downloadsQueued, downloadsPaused/resumed, downloadRemoved, downloadsRemoved) and maintains a short-lived cache for UI queries.

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

WARP.md — Tanoshi Narration (MAGI v2 → XTTS on Modal)

This file guides the manga → audiobook pipeline that runs when a reader toggles Listen in Tanoshi.

Project at a glance

Flow: App → Modal → PNG pages → MAGI v2 (chapter-wide extraction) → XTTS-v2 (voices) → App

Batching: 20 PNG pages per request (rolling window for long chapters)

Trigger: User flips Listen toggle → show placeholder ad → background processing starts immediately

Playback: When the user is on page N, play page N’s audio once ready; never auto-play

Status: Per-page chips show Queued / Extracting / TTS / Ready / Error with a slim global progress bar

Storage: Per-page HLS under audio/{job_id}/page-{index}/index.m3u8

SSE: Realtime job/status events drive UI progress (same pattern as your existing SSE sections). 
 

Endpoints (stateless, SSE-driven)

POST /v1/narration/session/start
Returns: job_id, 20 presigned PUT URLs for PNGs, status_sse, audio_url_template, adPlan (placeholder).

GET /v1/narration/jobs/:job_id/events → text/event-stream (SSE)
Emits: page_status, page_ready, progress, job_done. (Event grammar mirrors your existing SSE examples.) 

GET /v1/narration/jobs/:job_id/snapshot
One-shot JSON with last known states (for resume after app relaunch).

Notes

PNG only (no base64).

Presigned PUT URLs expire quickly; size caps enforced per page.

App reuses your shared downloads layout: Downloads/<sourceId>/<mangaId>/<chapterId>/001.png, 002.png, …. 

Client flow (iOS)

Listen toggle ON (styled like the rest of Reader; default OFF).

Immediately open ad placeholder and call /session/start.

Parallel PUT of 20 PNG pages to given URLs (no base64).

Subscribe SSE; render chips per page:

Gray Queued, Amber Extracting/TTS, Green Ready, Red Error.

When user views page N and it’s Ready, show Play in mini-player; prefetch N+1.

At page ≥ 15, request next window (/session/start or /session/next) for pages 20–39.

Never auto-play; user controls playback via the toggle/mini-player.

iOS and macOS share the same core; UI hooks live under your iOS target while storage paths and managers remain in Shared. 

Backend flow (Modal)
Orchestrator (CPU)

Wait for all 20 PNGs (or a configured threshold) to arrive.

Run MAGI v2 once per 20-page window → per-page essential lines + speaker.

Fan-out XTTS-v2 per utterance (GPU) with short clips (≈2–5s).

Packager assembles per-page HLS; publishes to object storage + CDN.

Emit SSE: page_status transitions; page_ready with URL.

Worker pools

MAGI v2 (GPU): concurrency=1–2 per GPU; load weights in @enter(); process all 20 together for consistent speaker tags.

XTTS-v2 (GPU): concurrency=4–8 small utterances per GPU; prioritize current page ±2 first.

Packager (CPU): high concurrency; atomic manifest updates; CDN cache-friendly keys.

Modal settings (per service)

Prebaked image with CUDA/cuDNN, MAGI v2, XTTS-v2, ffmpeg.

Volumes for model weights; @enter() to warm models once per container.

Autoscaler:

MAGI: min_containers=1, buffer=0–1, scaledown_window=600s

XTTS: min_containers=1–2, buffer=1, scaledown_window=900s

States & events

States (per page)
queued → extracting (MAGI) → tts (XTTS) → ready (or error)

SSE events

event: page_status
data: {"index":7,"state":"extracting"}

event: page_ready
data: {"index":7,"audio":"https://cdn/audio/job_abc/page-7/index.m3u8","duration":13.2}

event: progress
data: {"done":5,"total":20}

event: job_done
data: {"ok":true}


(Format mirrors your existing SSE event guidance and grammar.) 

Data contracts

/v1/narration/session/start → response

{
  "job_id": "job_abc",
  "upload": {
    "mode": "presigned",
    "pages": [
      {"index":0,"put_url":"...","content_type":"image/png","max_bytes":3000000},
      {"index":1,"put_url":"..."},
      {"index":19,"put_url":"..."}
    ]
  },
  "status_sse": "https://api/sse/jobs/job_abc",
  "audio_url_template": "https://cdn/audio/{job_id}/page-{index}/index.m3u8",
  "adPlan": {"kind":"placeholder","duration_hint":3}
}


MAGI output (per page)

{
  "page_index": 7,
  "lines": [
    {"speaker":"MC","text":"...","lang":"ja","role":"speech"},
    {"speaker":"Narrator","text":"...","role":"narration"}
  ]
}


XTTS request (utterance)

{"page_index":7,"speaker":"MC","text":"...","voice":"xtts:anime-soft-01","speed":1.0,"pitch":0.0}

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


This aligns with your existing Downloads/ image layout on device and keeps per-page assets distinct. 

Caching & idempotency

Page key: page:{blake3(png_bytes)}:magi.json

Utterance key: tts:{voice}:{sha256(text|speaker|prosody)}.ogg

Page audio key: page-audio:{job_id}:{index} (HLS playlist + segments)

Always check caches before work; page/utterance caches drastically reduce cost and TTFA.

UX policy (important)

Manual: Listening never auto-starts.

Ad placeholder first, but processing kicks off immediately behind it.

Visible Listen toggle, same visual style as current toolbar items.

Per-page chip + small global progress bar for clarity.

If a page fails, chip shows Error with a Retry action (re-queues only that page).

Security & isolation

Enforce PNG MIME, size caps, and short-TTL presigned URLs.

Signed GETs for HLS; no public listing.

Rate-limit starts and uploads per device; Redis locks prevent duplicate jobs.

Carry over your sandboxing/limits mindset—timeouts, capped memory, and path whitelisting for any file writes on the backend. 
 

SLOs & observability

p95 time-to-first-ready page: ≤ 6–8s (warm); ≤ 12s (cold)

Metrics: MAGI latency, XTTS latency, cache hit-rates, GPU utilization, TTFA, per-page success %, ad impressions.

Structured logs per job_id/page_index; redacted text where not needed.

Scaling & cost

One warm MAGI GPU and one warm XTTS GPU keep TTFA low; autoscale with buffers for peaks.

Default voices can later use a CPU TTS tier (Piper) with a rewarded ad to unlock XTTS premium; keep the same contracts.

Durable storage + CDN; atomic manifest updates.

Open questions / next actions

Finalize voice catalog and speaker routing policy.

Decide window threshold: require all 20 PNGs or allow N/20 to start MAGI for faster TTFA.

Add /session/next contract for rolling windows.

Decide HLS vs single-clip per page (HLS strongly recommended).

Add auth/rate-limit gates before public rollout (mirrors ownership note in your other WARP). 

Appendix — SSE sample (page lifecycle)
event: page_status
data: {"index":0,"state":"queued"}
event: page_status
data: {"index":0,"state":"extracting"}
event: page_status
data: {"index":0,"state":"tts"}
event: page_ready
data: {"index":0,"audio":"https://cdn/audio/job_abc/page-0/index.m3u8"}
event: job_done
data: {"ok":true}

Here is the documentation and development for the models we will use :
Magiv2:
from PIL import Image
import numpy as np
from transformers import AutoModel
import torch

model = AutoModel.from_pretrained("ragavsachdeva/magiv2", trust_remote_code=True).cuda().eval()


def read_image(path_to_image):
    with open(path_to_image, "rb") as file:
        image = Image.open(file).convert("L").convert("RGB")
        image = np.array(image)
    return image

chapter_pages = ["page1.png", "page2.png", "page3.png" ...]
character_bank = {
    "images": ["char1.png", "char2.png", "char3.png", "char4.png" ...],
    "names": ["Luffy", "Sanji", "Zoro", "Ussop" ...]
}

chapter_pages = [read_image(x) for x in chapter_pages]
character_bank["images"] = [read_image(x) for x in character_bank["images"]]

with torch.no_grad():
    per_page_results = model.do_chapter_wide_prediction(chapter_pages, character_bank, use_tqdm=True, do_ocr=True)

transcript = []
for i, (image, page_result) in enumerate(zip(chapter_pages, per_page_results)):
    model.visualise_single_image_prediction(image, page_result, f"page_{i}.png")
    speaker_name = {
        text_idx: page_result["character_names"][char_idx] for text_idx, char_idx in page_result["text_character_associations"]
    }
    for j in range(len(page_result["ocr"])):
        if not page_result["is_essential_text"][j]:
            continue
        name = speaker_name.get(j, "unsure") 
        transcript.append(f"<{name}>: {page_result['ocr'][j]}")
with open(f"transcript.txt", "w") as fh:
    for line in transcript:
        fh.write(line + "\n")


XTTS V2:
from TTS.tts.configs.xtts_config import XttsConfig
from TTS.tts.models.xtts import Xtts

config = XttsConfig()
config.load_json("/path/to/xtts/config.json")
model = Xtts.init_from_config(config)
model.load_checkpoint(config, checkpoint_dir="/path/to/xtts/", eval=True)
model.cuda()

outputs = model.synthesize(
    "It took me quite a long time to develop a voice and now that I have it I am not going to be silent.",
    config,
    speaker_wav="/data/TTS-public/_refclips/3.wav",
    gpt_cond_len=3,
    language="en",
)
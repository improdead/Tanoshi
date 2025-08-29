# need.md — Tanoshi Narration required configs and decisions

This document lists secrets, environment variables, infrastructure choices, and open decisions needed to finalize and operate the Tanoshi Narration system (FastAPI on Modal + iOS client). See WARP.md for architecture and developer workflow.

Secrets and environment variables (backend)
- API_BASE_URL: Public base URL for the API (e.g., https://api.tanoshi.app)
- CDN_BASE_URL: Public base URL for CDN serving audio/HLS (e.g., https://cdn.tanoshi.app). Modal-only MVP serves from API paths; CDN not required yet.
- REDIS_URL: Redis connection string (e.g., redis://host:6379/0)
  - Redis keys used:
    - rl:{kind}:{ip} – per-IP rate limit counters
    - narration:job:{job_id}:snapshot – JSON-serialized job snapshot
    - narration:idemp:{sha256} – idempotency key for /session/start
  - TTLs:
    - JOB_TTL_SECONDS (default 3600s) – snapshot expiry and in-memory job eviction
    - IDEMP_TTL_SECONDS (default mirrors JOB_TTL_SECONDS) – idempotency dedupe window (e.g., 300–600s)
    - RATE_LIMIT_WINDOW_SECONDS (default 60s)
    - RATE_LIMIT_START_MAX (default 10), RATE_LIMIT_NEXT_MAX (default 20)
- CORS_ORIGINS: Comma-separated allowed origins (include localhost and custom URL schemes used by the app)
- LOG_LEVEL: Optional (info|debug|warning|error) for backend logging
- SENTRY_DSN: Optional Sentry DSN for error reporting

Modal-only volumes
- DATA_VOLUME: Modal volume name for runtime data (defaults to tanoshi-data) mounted at /data
- MODELS_VOLUME: Modal volume name for models (defaults to tanoshi-models) mounted at /models

Modal (deployment) configuration
- Modal token set locally (modal token set) and service account for CI/CD if needed
- Image pinning: CUDA/cuDNN, torch/torchaudio versions
- Volumes: Names for persistent volumes (DATA_VOLUME at /data, MODELS_VOLUME at /models)
- GPU type: L4 (default) or A10G/A100 depending on performance/cost targets
- Autoscaling: min_containers and scaledown_window for narration API (optional; default scale-to-zero)
- Concurrency: per-worker limits for MAGI and SoVITS (SoVITS later)

Model weights and assets
- MAGI v2: pulled from Hugging Face `ragavsachdeva/magiv2` at runtime (cached). Consider baking into image or pre-pulling into /models for faster cold starts.
- GPT-SoVITS base model checkpoint(s) (later)
- Optional: text normalization/tokenizer resources
- Voice preview generation settings (sample text per language)

Voice packs (defaults and catalog)
- Default voice pack mapping for series: { Narrator: <voice_id>, MC: <voice_id>, Others?: <voice_id> }
- Policy on zero-shot vs few-shot usage (when to train a fine-tuned voice)
- Training dataset requirements and guardrails (consent, moderation, allowed sources)
- Quotas: limits per user/series for voice training and usage

Storage and CDN
- Modal-only MVP stores runtime artifacts under /data (Modal Volume):
  - /data/narration/{job_id}/pages/*.png
  - /data/narration/{job_id}/magi/page-*.json
  - /data/narration/{job_id}/audio/page-*/{index.m3u8, seg-*.ts}
- CDN/S3 not required yet; switch later for scale.

Performance knobs
- MAGI_START_AFTER_N_PAGES (default 4): start MAGI once N pages uploaded to reduce TTFA.
- Use `torch.autocast("cuda", dtype=torch.float16)` and `torch.no_grad()` for inference when CUDA is available.

Rate limiting and security
- Per-device/IP rate limits for /session/start, /session/next, and uploads
- Redis key namespaces and TTLs for idempotency locks
- PNG upload constraints (max bytes per page — e.g., 3 MB). PNG is enforced by the client and object-store policy; server returns presigned PUTs with content_type=image/png and does not receive file bytes.
- Delete-by-hash policy (privacy requests)

Observability
- Metrics backend (e.g., Prometheus, OpenTelemetry, Modal metrics)
- p95 TTFA, cache hit rates, GPU utilization, per-page success %, SSE disconnects/retries
- Structured logs with job_id/page_index (redaction policy for text)
- Alerting thresholds (TTFA, error rates)

iOS client integration
- Base URL configuration for NarrationAPI (default to https://api.tanoshi.app; override via UserDefaults key Tanoshi.APIBase)
- Feature flag/remote toggle for Listen feature
- Playback policy: Listening is off by default. After the user toggles it on, audio auto-plays for the current page once ready (after the ad gate). Provide a setting to disable auto-play if needed.
- Ad gating: default 3s gate implemented; optionally honor backend adPlan.duration_hint.
- Rolling windows: optionally auto-trigger /v1/narration/session/next at page ≥ (start+15) to keep audio ahead.
- Audio engine: AVPlayer-based HLS playback for per-page audio.

Open decisions to finalize
- macOS Reader integration: choose where to mount the Listen toggle and how to present playback (no macOS Reader UI currently in repo)
- Voice pack defaults per major series (Narrator/MC/Others)
- MAGI start threshold (wait for all 20 pages or start after N uploads for faster TTFA). Current stub starts immediately to hide cold start; production will use an arrival threshold.
- Rolling windows policy (auto-trigger threshold, e.g., at page ≥ start+15; prefetch window size)
- Ad gate policy (honor backend adPlan.duration_hint vs fixed gate; UX alignment with ads)
- GPU type and autoscaling parameters for cost/latency balance
- CORS_ORIGINS list for production domains and app schemes
- Error surface strategy (how to expose per-page errors to users; retry affordances)

Notes
- Do not commit real secrets. Keep backend/.env.example updated with all required keys.
- For local dev, MinIO + Redis containers are recommended; production can use S3/CloudFront + managed Redis.


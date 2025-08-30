# Tanoshi Narration backend (FastAPI on Modal)

This service exposes the endpoints described in WARP.md to orchestrate the manga → audio pipeline.

Run locally
- Python 3.10+
- Create a venv and install deps:
  - python -m venv .venv && source .venv/bin/activate
  - pip install -r backend/requirements.txt
- Copy backend/.env.example to .env and fill values
- Start local dev server:
  - uvicorn backend.server:app --reload --port 8080

Run on Modal
- Login once: modal token set
- Serve (ephemeral, for dev): modal serve backend/modal_app.py
- Or run functions: modal run backend/modal_app.py

Environment setup (Modal)
- Volumes:
  - MODELS_VOLUME: defaults to tanoshi-models, mounted at /models
  - DATA_VOLUME: defaults to tanoshi-data, mounted at /data
- GPU: L4 by default; override in decorator if needed
- CORS: set CORS_ORIGINS to allow your app schemes/hosts

Environment variables
- API_BASE_URL: public API base, e.g., https://api.tanoshi.app
- CDN_BASE_URL: public CDN base, e.g., https://cdn.tanoshi.app
- BUCKET_URL: S3 endpoint, e.g., https://s3.us-east-1.amazonaws.com or http(s)://minio:9000
- BUCKET_REGION: S3 region, e.g., us-east-1
- BUCKET_NAME: bucket to store narration data
- AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY: S3 creds (or use IAM)
- REDIS_URL: redis://host:port/0
- CORS_ORIGINS: comma-separated list, e.g., http://localhost:3000,aidoku://
- JOB_TTL_SECONDS: seconds to retain job snapshots (default 3600)
- IDEMP_TTL_SECONDS: seconds to dedupe /session/start (defaults to JOB_TTL_SECONDS)
- RATE_LIMIT_WINDOW_SECONDS: rate limit window in seconds (default 60)
- RATE_LIMIT_START_MAX: max /session/start requests per IP per window (default 10)
- RATE_LIMIT_NEXT_MAX: max /session/next requests per IP per window (default 20)
- MAGI_START_AFTER_N_PAGES: default 4
- MAGI_REVISION: optional HF commit/tag for ragavsachdeva/magiv2
- SOVITS_ENABLED: true/false (default false)
- SOVITS_VERSION: default v4
- SOVITS_PRETRAINED_SUBDIR: path under /models/GPT-SoVITS with pretrained models

Notes
- SSE endpoints emit simple text/event-stream. On connect, the server emits an initial burst of page_status (for all pages) and a progress event to help clients restore UI quickly. Clients should still call /snapshot on reconnect.
- Job snapshots are persisted in Redis when REDIS_URL is provided (key: narration:job:{job_id}:snapshot) with TTL (JOB_TTL_SECONDS). In-memory fallback exists with a background cleaner.
- MAGI v2 is integrated (HF trust_remote_code; autocast+no_grad). GPT-SoVITS is stubbed behind SOVITS_ENABLED with a beep fallback.

Endpoints (selected)
- POST /v1/narration/session/start: create a job and return upload plan (PUT pages).
- POST /v1/narration/session/next: same semantics as start with shifted window.
- GET  /v1/narration/jobs/{job_id}/events: typed SSE (page_status, page_ready, progress, job_done).
- GET  /v1/narration/jobs/{job_id}/snapshot: snapshot of job state.
- PUT  /v1/narration/jobs/{job_id}/pages/{i}: upload a single PNG page (image/png; <=3 MB).
- POST /v1/narration/jobs/{job_id}/pages/batch: upload many pages at once.
  - multipart/form-data with fields page_0..page_19 (or page_00..page_19), or application/zip (000.png..019.png).
  - Emits page_status:extracting per saved page and triggers MAGI threshold.
  - Response: {accepted, failed[], total_bytes}.
- GET  /v1/narration/jobs/{job_id}/audio/page-{i}/index.m3u8: HLS playlist.
- GET  /v1/narration/jobs/{job_id}/audio/page-{i}/seg-*.ts: HLS segments.

Tanoshi Narration — Stabilization and Cost Plan

Goal
- Eliminate upload timeouts and cross‑instance flakiness
- Reduce wall‑clock cost per window
- Keep audio pacing natural with the no‑character‑ID phase

Phase 1 — Stability + Quick ROI (implement now)
1) Backend: Add batch upload endpoint
   - POST /v1/narration/jobs/{job_id}/pages/batch (multipart or zip)
   - Saves 0..19 PNGs; emits page_status:extracting per page; triggers MAGI threshold
   - Keep legacy PUT /pages/{i} for compatibility

2) iOS uploader hardening
   - Throttle concurrent PUTs to 3–4 (semaphore)
   - Exponential backoff on -1001 with jitter, max 2 retries
   - Upload timeout 120s
   - Prefer /batch; fallback to legacy PUTs if /batch unavailable
   - Downscale long edge to ~1600 px before PNG (large cost/latency win)

3) Modal warm container (GPU)
   - keep_warm=1 on NarrationService; optional heartbeat during dev
   - MAGI weights loaded once in @enter(); no reloads per page

4) Redis finalization
   - Set REDIS_URL; use Redis for snapshots (TTL) and Pub/Sub SSE across instances
   - Unknown job on upload/connect → rehydrate from snapshot instead of 404

5) Logs + observability
   - Server logs when HLS playlist/segments are written/served
   - Client log dedup (already added) to reduce noise

Phase 2 — Cost‑oriented refactor (next pass)
6) Split GPU from CPU work
   - MAGI runs on GPU container only
   - TTS + ffmpeg run on CPU function (cheaper), invoked after MAGI
   - Release GPU ASAP; keep CPU worker scaled to zero/min containers

7) Cache model assets
   - TRANSFORMERS_CACHE or HF_HOME → /models/hf (persistent) to avoid re‑downloads on cold starts

8) Resource sizing
   - Lower CPU/RAM on GPU function; increase on CPU synth only if needed

Phase 3 — Optional
9) All‑in‑one start payload
   - Allow /session/start to accept the 20 images (multipart) to remove upload round‑trips entirely

Notes / current limitations
- No character recognition: pages are synthesized as Narrator only, with sentence‑by‑sentence chunks and ~350 ms fixed pauses (configurable via CHUNKED_TTS). This keeps speech natural without speaker IDs.
- Redis memory (30 MB): snapshots are compact JSON; TTL bounds memory. Rate limit keys expire in 60s.

Success criteria
- Upload timeout errors drop to ~0
- One GPU MAGI pass per window; all audio produced by CPU TTS/ffmpeg (Phase 2)
- Total window latency <= ~3–6 s warm; cost reduced from 20x PUTs to ~1 request + single MAGI run


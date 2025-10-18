What do I need.md — Open questions, placeholders, and decisions to make

This document tracks unknowns and placeholders to resolve for a production-ready Modal + FastAPI setup for Tanoshi Narration.

Infra and deployment
- GPU topology:
  - Today, the ASGI app itself runs on a GPU (L4) to keep MAGI snappy. Do we want to split CPU web + GPU worker (NarrationService) later to reduce cost?
  - If we split, define RPC boundaries (Modal.function/class) and queueing semantics.
- Hugging Face cache:
  - We now set TRANSFORMERS_CACHE and HF_HOME to /models/hf in the image. Confirm this is desired and that the models volume has enough capacity.
  - Consider pre-caching additional assets beyond ragavsachdeva/magiv2.
- Redis:
  - Are we guaranteed a Redis URL in prod? Without it, idempotency and cross‑instance SSE fall back to in‑memory only.
  - Confirm Redis plan (memory budget ~30 MB noted in WARP.md).
- CORS and domains:
  - Confirm final API base domain and CORS origins for app schemes/domains.
  - If fronted by a proxy (Cloudflare/NGINX), verify SSE pass‑through and buffering disabled.

TTS / SoVITS specifics
- SOVITS_ENABLED defaults to false. When enabling:
  - Which GPT‑SoVITS repo/branch to pin? We clone https://github.com/RVC-Boss/GPT-SoVITS.git by default.
  - Are pretrained checkpoints available and where should we fetch them from? (SOVITS_MODEL_URLS env supports a list.)
  - Voice refs: We expect /models/voices/{voice_id}/refs/ref.wav — confirm file format and preprocessing needs.
  - Dataset/training (few‑shot) is currently a placeholder; training endpoint is not implemented.
- Language handling:
  - Basic espeak-ng fallback picks ja for Japanese characters; refine language hints per voice or MAGI output.

Audio packaging and CDN
- HLS is served directly by the API from the /data volume. Do we want to put a CDN in front later? If yes, confirm path mapping and cache headers.
- Current MIME types: playlist application/vnd.apple.mpegurl, segments video/MP2T; verify player compatibility across platforms.

Limits and validation
- PNG upload limit is 3 MB per page. Confirm this ceiling and whether we should downscale client‑side more aggressively.
- Voice ref limit is 5–30s, ~24 kHz mono (16–24 k accepted). Confirm acceptable ranges.

Operational concerns
- Logging:
  - We added more debug breadcrumbs around HLS and SSE. Do we want structured logs (JSON) and request IDs?
- Metrics:
  - No explicit metrics emitted yet (timings, queue sizes, TTS durations). Decide on an APM/metrics sink.
- Cleanup:
  - JOB_TTL_SECONDS default is 3600s. Confirm retention policy and whether to persist snapshots to disk as well.

Security
- Ensure tanoshi-env Modal Secret contains only non‑sensitive config, or rotate keys as needed. Currently supports REDIS_URL and other config.

Pseudocode notes for future worker split
- Goal: Move MAGI to a GPU worker and keep ASGI app on CPU.

  on POST /session/start:
    create job in Redis (status queued)
    return direct PNG PUT plan + SSE URL

  on PUT /pages/{i}:
    write to /data volume
    mark page uploaded; if threshold reached and no MAGI task enqueued, enqueue MAGI job

  GPU worker (consume MAGI tasks):
    load MAGI weights at startup (keep warm)
    for each job:
      read available uploaded pages
      run do_chapter_wide_prediction → write MAGI JSON files
      publish per‑page extracting→tts transitions

  TTS (CPU):
    watch for MAGI JSON → build utterances → TTS (SoVITS or fallback) → write HLS → emit page_ready

  SSE:
    subscribe to Redis Pub/Sub channel narration:job:{job_id}:events
    on connect, emit snapshot, then stream events; send keep‑alive heartbeats; set headers to disable buffering

Please annotate this file with decisions and answers as we converge.

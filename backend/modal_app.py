"""
Modal + FastAPI backend skeleton for Tanoshi Narration.

Goals:
- Python on Modal with pre-baked image and persistent model volume.
- Endpoints per WARP.md: start, next, SSE events, snapshot, voice register/get.
- PNG-only presigned upload placeholders; SSE simulates status updates.
- Background processing starts immediately (simulated here) — wire to MAGI/SoVITS later.

Run (Modal):
  modal run backend/modal_app.py
  modal serve backend/modal_app.py
"""

from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from dataclasses import dataclass, field
from typing import Set
import re
from typing import AsyncGenerator, Dict, List, Optional
import hashlib
import pathlib
import subprocess

import modal
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.responses import StreamingResponse
from starlette.datastructures import Headers

try:
    # Optional Redis (async) client for job state + rate limiting
    from redis import asyncio as aioredis  # type: ignore
except Exception:  # pragma: no cover - optional dependency present in requirements
    aioredis = None  # type: ignore


# -----------------------------
# Modal app, image, and volume
# -----------------------------

image = (
    modal.Image.debian_slim()
    .apt_install("ffmpeg")
    .pip_install(
        # Core web/backend
        "fastapi",
        "uvicorn",
        "pydantic",
        # Object storage / async utils
        "boto3",
        "aioboto3",
        # Optional cache client
        "redis",
        # Hashing / DSP utilities
        "blake3",
        "numpy",
        "soundfile",
        "Pillow",
        # MAGI v2 stack
        "transformers==4.43.3",
        "torch==2.3.1",
        "torchaudio==2.3.1",
    )
)

models_volume = modal.Volume.from_name("tanoshi-models", create_if_missing=True)
data_volume = modal.Volume.from_name("tanoshi-data", create_if_missing=True)

app = modal.App("tanoshi-narration")


@app.function(image=image, volumes={"/models": models_volume})
def download_models() -> None:
    """One-shot task to populate /models with MAGI and SoVITS weights (idempotent)."""
    import pathlib
    import subprocess

    root = pathlib.Path("/models")
    root.mkdir(exist_ok=True, parents=True)
    # Example (uncomment and set URLs):
    # subprocess.run(["curl", "-L", MAGI_URL, "-o", str(root / "magi.bin")], check=True)
    # subprocess.run(["curl", "-L", SOVITS_URL, "-o", str(root / "sovits.pth")], check=True)


@app.cls(image=image, gpu="L4", volumes={"/models": models_volume, "/data": data_volume})
class NarrationService:
    """GPU-backed service that would host MAGI + SoVITS (stubbed)."""

    def __init__(self) -> None:
        self.loaded_at: Optional[float] = None

    @modal.enter()
    def load(self) -> None:
        # Load weights once from /models into RAM/GPU.
        # self.magi = load_magi("/models/magi.bin")
        # self.sovits = load_sovits("/models/sovits.pth")
        self.loaded_at = time.time()

    @modal.method()
    def synth(self, page_json: dict) -> str:
        """Stub: would run MAGI → SoVITS → write HLS; returns audio URL."""
        job_id = page_json.get("job_id", "job")
        index = page_json.get("page_index", 0)
        base = os.getenv("CDN_BASE_URL", "https://cdn.tanoshi.app")
        return f"{base}/audio/{job_id}/page-{index}/index.m3u8"


# -----------------------------
# FastAPI app (served via Modal)
# -----------------------------

api = FastAPI(title="Tanoshi Narration API", version="0.2.0")
api.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(",") if os.getenv("CORS_ORIGINS") else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Window(BaseModel):
    start_index: int = Field(0, ge=0)
    size: int = Field(20, ge=1)


class ClientInfo(BaseModel):
    device: str
    app_version: str


class SessionStartRequest(BaseModel):
    chapter_id: str
    voice_pack: Dict[str, str]
    window: Window
    client: ClientInfo


class VoiceRegisterRequest(BaseModel):
    name: str
    engine: str = Field("sovits")
    mode: str = Field("zero_shot")  # or "few_shot"
    lang_hint: Optional[str] = None


@dataclass
class PageState:
    index: int
    state: str = "queued"  # queued|extracting|tts|ready|error
    audio: Optional[str] = None
    reason: Optional[str] = None


@dataclass
class JobState:
    job_id: str
    total: int
    done: int = 0
    pages: Dict[int, PageState] = field(default_factory=dict)
    events: "asyncio.Queue[str]" = field(default_factory=asyncio.Queue)
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    uploaded_pages: Set[int] = field(default_factory=set)
    magi_start_event: asyncio.Event = field(default_factory=asyncio.Event)


JOBS: Dict[str, JobState] = {}

# Optional Redis setup (for snapshot persistence and rate limiting)
REDIS_URL = os.getenv("REDIS_URL")
IDEMP_TTL_SECONDS = int(os.getenv("IDEMP_TTL_SECONDS", os.getenv("JOB_TTL_SECONDS", "3600")))
redis_client: Optional["aioredis.Redis"] = None

async def get_redis() -> Optional["aioredis.Redis"]:
    global redis_client
    if REDIS_URL and aioredis is not None:
        if redis_client is None:
            redis_client = aioredis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)
        return redis_client
    return None

# Job TTL & cleanup
JOB_TTL_SECONDS = int(os.getenv("JOB_TTL_SECONDS", "3600"))  # 1h default
_cleanup_task_started = False

async def _cleanup_jobs_loop() -> None:
    while True:
        await asyncio.sleep(60)
        now = time.time()
        expired: List[str] = []
        for job_id, job in list(JOBS.items()):
            if now - job.updated_at > JOB_TTL_SECONDS:
                expired.append(job_id)
        for job_id in expired:
            JOBS.pop(job_id, None)

def _ensure_cleanup_started() -> None:
    global _cleanup_task_started
    if not _cleanup_task_started:
        try:
            asyncio.get_running_loop().create_task(_cleanup_jobs_loop())
            _cleanup_task_started = True
        except RuntimeError:
            # No running loop yet; will be started on first request
            pass

# Simple per-IP rate limiting
RATE_LIMIT_WINDOW_SECONDS = int(os.getenv("RATE_LIMIT_WINDOW_SECONDS", "60"))
RATE_LIMIT_START_MAX = int(os.getenv("RATE_LIMIT_START_MAX", "10"))
RATE_LIMIT_NEXT_MAX = int(os.getenv("RATE_LIMIT_NEXT_MAX", "20"))

async def _check_rate_limit(request: Request, kind: str) -> None:
    ip = request.client.host if request.client else "unknown"
    max_allowed = RATE_LIMIT_START_MAX if kind == "start" else RATE_LIMIT_NEXT_MAX
    key = f"rl:{kind}:{ip}"
    r = await get_redis()
    if r:
        # Increment counter with window TTL
        count = await r.incr(key)
        if count == 1:
            await r.expire(key, RATE_LIMIT_WINDOW_SECONDS)
        if count > max_allowed:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
    else:
        # In-memory fallback
        now = time.time()
        bucket = _RATE_BUCKETS.get(key)
        if not bucket or now > bucket["reset_at"]:
            _RATE_BUCKETS[key] = {"count": 1, "reset_at": now + RATE_LIMIT_WINDOW_SECONDS}
        else:
            bucket["count"] += 1
            if bucket["count"] > max_allowed:
                raise HTTPException(status_code=429, detail="Rate limit exceeded")

_RATE_BUCKETS: Dict[str, Dict[str, float]] = {}

# In-memory idempotency map fallback (key -> {job_id, reset_at})
_IDEMP_MAP: Dict[str, Dict[str, object]] = {}


def _make_presigned_put(job_id: str, idx: int) -> Dict[str, object]:
    # Modal-only direct PUT to API endpoint
    api_base = os.getenv("API_BASE_URL", "https://api.tanoshi.app")
    return {
        "index": idx,
        "put_url": f"{api_base}/v1/narration/jobs/{job_id}/pages/{idx}",
        "content_type": "image/png",
        "max_bytes": 3_000_000,
    }


def _audio_url(job_id: str, idx: int) -> str:
    base = os.getenv("CDN_BASE_URL", "https://cdn.tanoshi.app")
    return f"{base}/audio/{job_id}/page-{idx}/index.m3u8"

def _compose_snapshot(job: JobState) -> Dict[str, object]:
    pages: List[Dict[str, object]] = []
    for i in range(job.total):
        p = job.pages[i]
        d: Dict[str, object] = {"index": p.index, "state": p.state}
        if p.audio:
            d["audio"] = p.audio
        if p.reason:
            d["reason"] = p.reason  # type: ignore[assignment]
        pages.append(d)
    return {"job_id": job.job_id, "pages": pages, "progress": {"done": job.done, "total": job.total}}

async def _persist_snapshot(job: JobState) -> None:
    r = await get_redis()
    if r:
        key = f"narration:job:{job.job_id}:snapshot"
        await r.set(key, json.dumps(_compose_snapshot(job)))
        await r.expire(key, JOB_TTL_SECONDS)

def _compute_idempotency_key_for_start(req: "SessionStartRequest") -> str:
    # Build a canonical payload and hash it to form a stable key
    key_payload = {
        "chapter_id": req.chapter_id,
        "window": {"start_index": req.window.start_index, "size": req.window.size},
        # Include voice pack mapping; order-insensitive by sorting items
        "voice_pack": {k: req.voice_pack[k] for k in sorted(req.voice_pack.keys())},
    }
    digest = hashlib.sha256(json.dumps(key_payload, sort_keys=True).encode("utf-8")).hexdigest()
    return f"narration:idemp:{digest}"


async def _simulate_processing(job: JobState) -> None:
    """Replaced by _process_job with real MAGI and dummy TTS."""
    await _process_job(job)


# -----------------------------
# MAGI v2 integration (Modal-only)
# -----------------------------
_MAGI_MODEL = None
_MAGI_DEVICE = "cpu"
MAGI_START_AFTER_N_PAGES = int(os.getenv("MAGI_START_AFTER_N_PAGES", "4"))
MAGI_REVISION = os.getenv("MAGI_REVISION")  # optional HF commit hash/tag

def _ensure_dirs(job_id: str) -> Dict[str, pathlib.Path]:
    root = pathlib.Path("/data") / "narration" / job_id
    (root / "pages").mkdir(parents=True, exist_ok=True)
    (root / "magi").mkdir(parents=True, exist_ok=True)
    (root / "audio").mkdir(parents=True, exist_ok=True)
    return {
        "root": root,
        "pages": root / "pages",
        "magi": root / "magi",
        "audio": root / "audio",
    }

def _ensure_magi_loaded() -> None:
    global _MAGI_MODEL, _MAGI_DEVICE
    if _MAGI_MODEL is not None:
        return
    from transformers import AutoModel  # lazy import
    import torch  # type: ignore
    _MAGI_DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
    # Trust remote code per HF card; run on available device
    if MAGI_REVISION:
        _MAGI_MODEL = AutoModel.from_pretrained(
            "ragavsachdeva/magiv2", trust_remote_code=True, revision=MAGI_REVISION
        )
    else:
        _MAGI_MODEL = AutoModel.from_pretrained("ragavsachdeva/magiv2", trust_remote_code=True)
    try:
        _MAGI_MODEL.to(_MAGI_DEVICE)
    except Exception:
        pass
    _MAGI_MODEL.eval()

def _read_image_to_numpy(path: pathlib.Path):
    from PIL import Image  # lazy import
    import numpy as np  # type: ignore
    with open(path, "rb") as f:
        image = Image.open(f).convert("L").convert("RGB")
        return np.array(image)

def _write_dummy_hls(job_id: str, page_index: int, duration: float = 12.3) -> pathlib.Path:
    dirs = _ensure_dirs(job_id)
    page_dir = dirs["audio"] / f"page-{page_index:03d}"
    page_dir.mkdir(parents=True, exist_ok=True)
    playlist = page_dir / "index.m3u8"
    # Generate HLS with independent TS segments
    if not playlist.exists():
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-t", str(duration), "-i", "anullsrc=r=24000:cl=mono",
            "-c:a", "aac", "-b:a", "64k",
            "-f", "hls",
            "-hls_time", "2",
            "-hls_segment_type", "mpegts",
            "-hls_flags", "independent_segments",
            "-hls_list_size", "0",
            str(playlist)
        ]
        try:
            subprocess.run(cmd, check=True, cwd=str(page_dir))
        except Exception:
            # Fallback: write single-segment minimal playlist and empty TS
            seg_path = page_dir / "seg-00001.ts"
            seg_path.write_bytes(b"\x00")
            playlist.write_text(
                "\n".join([
                    "#EXTM3U",
                    "#EXT-X-VERSION:3",
                    f"#EXT-X-TARGETDURATION:{int(max(1, duration))}",
                    "#EXT-X-MEDIA-SEQUENCE:0",
                    f"#EXTINF:{duration:.1f},",
                    "seg-00001.ts",
                    "#EXT-X-ENDLIST",
                ])
            )
    return playlist

async def _run_magi_for_job(job: JobState) -> None:
    # Load MAGI in a background thread to avoid blocking the event loop
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(None, _ensure_magi_loaded)
    dirs = _ensure_dirs(job.job_id)
    # Wait for N pages before starting MAGI to cut TTFA (event-driven)
    if len(job.uploaded_pages) < min(MAGI_START_AFTER_N_PAGES, job.total):
        try:
            await asyncio.wait_for(job.magi_start_event.wait(), timeout=60.0)
        except asyncio.TimeoutError:
            pass

    # Build chapter list using all currently uploaded pages; missing ones will be added later in rolling passes
    page_indices: List[int] = []
    chapter_pages = []
    for i in range(job.total):
        p = dirs["pages"] / f"{i:03d}.png"
        if p.exists():
            chapter_pages.append(_read_image_to_numpy(p))
            page_indices.append(i)

    # Empty character bank by default (user can add later)
    character_bank = {"images": [], "names": []}
    # MAGI inference
    import torch  # type: ignore
    # autocast for VRAM savings
    if _MAGI_DEVICE == "cuda":
        autocast_ctx = torch.autocast(device_type="cuda", dtype=torch.float16)
    else:
        from contextlib import nullcontext
        autocast_ctx = nullcontext()

    with torch.no_grad():
        with autocast_ctx:
            results = _MAGI_MODEL.do_chapter_wide_prediction(
                chapter_pages,
                character_bank,
                use_tqdm=False,
                do_ocr=True,
            )

    # Persist per-page MAGI JSON with BLAKE3 cache key
    try:
        import blake3  # type: ignore
    except Exception:
        blake3 = None  # type: ignore
    for i, page_result in zip(page_indices, results):
        page_path = dirs["pages"] / f"{i:03d}.png"
        cache_key = None
        if blake3 is not None and page_path.exists():
            cache_key = blake3.blake3(page_path.read_bytes()).hexdigest()
        out = {
            "page_index": i,
            "cache_key": cache_key,
            # Store essential fields used downstream; include full page_result for debugging
            "ocr": page_result.get("ocr"),
            "is_essential_text": page_result.get("is_essential_text"),
            "character_names": page_result.get("character_names"),
            "text_character_associations": page_result.get("text_character_associations"),
        }
        (dirs["magi"] / f"page-{i:03d}.json").write_text(json.dumps(out, ensure_ascii=False))

async def _process_job(job: JobState) -> None:
    queue = job.events

    # Initial queued statuses
    for i in range(job.total):
        await queue.put(f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'queued'})}\n\n")

    # Ensure directories
    _ensure_dirs(job.job_id)

    # Process pages with MAGI rolling starts, then dummy TTS per page
    await _run_magi_for_job(job)

    for i in range(job.total):
        page = job.pages[i]
        # extracting → done already; emit extracting to reflect transition
        page.state = "extracting"
        await queue.put(f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'extracting'})}\n\n")

        # Immediately move to tts stage (we simulate TTS audio)
        page.state = "tts"
        await queue.put(f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'tts'})}\n\n")

        # Generate dummy HLS for this page
        _write_dummy_hls(job.job_id, i, duration=12.3)

        page.state = "ready"
        page.audio = f"/v1/narration/jobs/{job.job_id}/audio/page-{i:03d}/index.m3u8"
        job.done += 1
        job.updated_at = time.time()

        await queue.put(
            f"event: page_ready\ndata: {json.dumps({'index': i, 'audio': page.audio, 'duration': 12.3})}\n\n"
        )
        await queue.put(f"event: progress\ndata: {json.dumps({'done': job.done, 'total': job.total})}\n\n")
        await _persist_snapshot(job)

    await queue.put("event: job_done\ndata: {\"ok\": true}\n\n")


@api.post("/v1/narration/session/start")
async def session_start(req: SessionStartRequest, request: Request):
    _ensure_cleanup_started()
    # Rate limit per IP for start
    await _check_rate_limit(request, kind="start")
    # Basic rate limit
    # Use a dummy Request-like object? We have no Request here; switch signature to accept Request
    # We'll overload: FastAPI allows dependency injection, but keep simple: use a placeholder IP key
    # Enforce PNG uploads (no base64); ensure 20-page window by default
    if req.window.size != 20:
        raise HTTPException(status_code=400, detail="window.size must be 20")

    # Idempotency: reuse existing job if one exists for the same (chapter_id, window, voice_pack)
    idem_key = _compute_idempotency_key_for_start(req)
    r = await get_redis()
    if r:
        existing_job_id = await r.get(idem_key)
        if existing_job_id:
            # Ensure job still exists (snapshot or in-memory)
            snap_key = f"narration:job:{existing_job_id}:snapshot"
            snap_exists = await r.exists(snap_key)
            if snap_exists or existing_job_id in JOBS:
                api_base = os.getenv("API_BASE_URL", "https://api.tanoshi.app")
                pages = [_make_presigned_put(existing_job_id, i) for i in range(req.window.size)]
                return {
                    "job_id": existing_job_id,
                    "upload": {"mode": "presigned", "pages": pages},
                    "status_sse": f"{api_base}/v1/narration/jobs/{existing_job_id}/events",
                    "audio_url_template": _audio_url(existing_job_id, "{index}"),
                    "adPlan": {"kind": "placeholder", "duration_hint": 3},
                }
    else:
        # In-memory fallback
        now = time.time()
        entry = _IDEMP_MAP.get(idem_key)
        if entry and isinstance(entry.get("reset_at"), float) and now < float(entry["reset_at"]):
            existing_job_id = str(entry.get("job_id"))
            if existing_job_id in JOBS:
                api_base = os.getenv("API_BASE_URL", "https://api.tanoshi.app")
                pages = [_make_presigned_put(existing_job_id, i) for i in range(req.window.size)]
                return {
                    "job_id": existing_job_id,
                    "upload": {"mode": "presigned", "pages": pages},
                    "status_sse": f"{api_base}/v1/narration/jobs/{existing_job_id}/events",
                    "audio_url_template": _audio_url(existing_job_id, "{index}"),
                    "adPlan": {"kind": "placeholder", "duration_hint": 3},
                }

    job_id = f"job_{uuid.uuid4().hex[:8]}"
    total = req.window.size

    job = JobState(job_id=job_id, total=total)
    for i in range(total):
        job.pages[i] = PageState(index=i)
    JOBS[job_id] = job

    # Record idempotency mapping
    if r:
        await r.set(idem_key, job_id)
        await r.expire(idem_key, IDEMP_TTL_SECONDS)
    else:
        _IDEMP_MAP[idem_key] = {"job_id": job_id, "reset_at": time.time() + IDEMP_TTL_SECONDS}

    # Kick processing in background immediately (MAGI waits for uploads)
    asyncio.create_task(_process_job(job))

    pages = [_make_presigned_put(job_id, i) for i in range(total)]
    api_base = os.getenv("API_BASE_URL", "https://api.tanoshi.app")
    return {
        "job_id": job_id,
        "upload": {"mode": "direct", "pages": pages},
        "status_sse": f"{api_base}/v1/narration/jobs/{job_id}/events",
        "audio_url_template": f"{api_base}/v1/narration/jobs/{job_id}/audio/page-{{index}}/index.m3u8",
        "adPlan": {"kind": "placeholder", "duration_hint": 3},
    }


@api.post("/v1/narration/session/next")
async def session_next(req: SessionStartRequest, request: Request):
    # Rate limit per IP for next
    await _check_rate_limit(request, kind="next")
    # Semantics mirror /start; client bumps window.start_index to 20, 40, ...
    return await session_start(req, request)


@api.get("/v1/narration/jobs/{job_id}/events")
async def job_events(job_id: str, request: Request):
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")

    async def event_stream() -> AsyncGenerator[bytes, None]:
        # Heartbeat every 15s to keep proxies happy
        heartbeat_interval = 15.0
        last_heartbeat = time.time()
        queue = job.events
        # Emit current state once at connect to help clients restore without /snapshot
        # (Docs still recommend calling /snapshot on reconnect.)
        # Emit page_status for all pages and a progress event.
        initial = _compose_snapshot(job)
        for p in initial["pages"]:  # type: ignore[index]
            yield f"event: page_status\ndata: {json.dumps(p)}\n\n".encode("utf-8")
        yield f"event: progress\ndata: {json.dumps(initial['progress'])}\n\n".encode("utf-8")

        while True:
            if await request.is_disconnected():
                break

            try:
                event = await asyncio.wait_for(queue.get(), timeout=1.0)
                yield event.encode("utf-8")
            except asyncio.TimeoutError:
                pass

            now = time.time()
            if now - last_heartbeat > heartbeat_interval:
                yield b": keep-alive\n\n"
                last_heartbeat = now

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@api.get("/v1/narration/jobs/{job_id}/snapshot")
async def job_snapshot(job_id: str):
    # Prefer Redis snapshot if available, fallback to in-memory
    r = await get_redis()
    if r:
        key = f"narration:job:{job_id}:snapshot"
        snap = await r.get(key)
        if snap:
            return json.loads(snap)
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return _compose_snapshot(job)


# -----------------------------
# Direct PNG uploads (Modal Volume)
# -----------------------------
@api.put("/v1/narration/jobs/{job_id}/pages/{page_index}")
async def upload_page(job_id: str, page_index: int, request: Request):
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")

    # Validate headers
    ctype = request.headers.get("content-type", "").lower()
    if "image/png" not in ctype:
        raise HTTPException(status_code=415, detail="Content-Type must be image/png")

    # Read body and enforce max size
    body = await request.body()
    max_bytes = 3_000_000
    if len(body) > max_bytes:
        raise HTTPException(status_code=413, detail="PNG exceeds max bytes")

    # Persist to /data volume
    dirs = _ensure_dirs(job_id)
    out = dirs["pages"] / f"{page_index:03d}.png"
    out.write_bytes(body)
    # Mark uploaded and signal MAGI threshold if reached
    job.uploaded_pages.add(page_index)
    if len(job.uploaded_pages) >= min(MAGI_START_AFTER_N_PAGES, job.total):
        job.magi_start_event.set()

    # Update state → extracting (MAGI will run shortly)
    page = job.pages.get(page_index)
    if page:
        page.state = "extracting"
        await job.events.put(
            f"event: page_status\ndata: {json.dumps({'index': page_index, 'state': 'extracting'})}\n\n"
        )
        job.updated_at = time.time()
        await _persist_snapshot(job)

    return {"ok": True}


# -----------------------------
# Serve HLS from /data
# -----------------------------
@api.get("/v1/narration/jobs/{job_id}/audio/page-{page_index}/index.m3u8")
async def get_playlist(job_id: str, page_index: int):
    dirs = _ensure_dirs(job_id)
    path = dirs["audio"] / f"page-{page_index:03d}" / "index.m3u8"
    if not path.exists():
        raise HTTPException(status_code=404, detail="playlist not found")
    return StreamingResponse(iter([path.read_bytes()]), media_type="application/vnd.apple.mpegurl")


@api.get("/v1/narration/jobs/{job_id}/audio/page-{page_index}/{segment}")
async def get_segment(job_id: str, page_index: int, segment: str):
    dirs = _ensure_dirs(job_id)
    # Validate segment strictly (e.g., seg-00001.ts, index.m3u8 is served by another route)
    if not re.fullmatch(r"seg-\d+\.ts", segment):
        raise HTTPException(status_code=400, detail="invalid segment name")
    safe = pathlib.Path(segment).name  # prevent path traversal
    path = dirs["audio"] / f"page-{page_index:03d}" / safe
    if not path.exists():
        raise HTTPException(status_code=404, detail="segment not found")
    # audio/ts segment
    return StreamingResponse(iter([path.read_bytes()]), media_type="video/MP2T")


@api.post("/v1/voices/register")
async def voice_register(req: VoiceRegisterRequest):
    voice_id = f"sovits:{req.name.replace(' ', '-').lower()}"
    api_base = os.getenv("API_BASE_URL", "https://api.tanoshi.app")
    upload: Dict[str, object] = {
        "mode": "presigned",
        "refs": [
            {
                "purpose": "zero_shot_ref",
                "put_url": f"https://uploads.tanoshi.app/voices/{voice_id}/ref.wav?signature=fake",
            }
        ],
    }
    if req.mode == "few_shot":
        upload["dataset"] = {
            "audio_put_prefix": f"https://uploads.tanoshi.app/voices/{voice_id}/clips/{{i}}.wav",
            "transcript_put_url": f"https://uploads.tanoshi.app/voices/{voice_id}/transcripts.jsonl",
        }

    return {
        "voice_id": voice_id,
        "upload": upload,
        "status_sse": f"{api_base}/v1/voices/{voice_id}/events",
    }


@api.get("/v1/voices/{voice_id}")
async def voice_get(voice_id: str):
    return {
        "voice_id": voice_id,
        "engine": "sovits",
        "mode": "zero_shot",
        "status": "ready",
        "languages": ["ja"],
        "sample_rate": 24000,
        "preview": f"https://cdn.tanoshi.app/voices/{voice_id}/preview.m4a",
    }


# Expose FastAPI via Modal asgi_app
@app.function(image=image, gpu="L4", volumes={"/models": models_volume, "/data": data_volume}).asgi_app()
def fastapi_app():  # type: ignore[override]
    return api



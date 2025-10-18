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
import sys

import modal
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.responses import StreamingResponse
from fastapi.responses import HTMLResponse

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
    .apt_install("ffmpeg", "espeak-ng", "git", "git-lfs", "curl")
    .pip_install(
        # Core web/backend
        "fastapi",
        "uvicorn",
        "pydantic",
        "python-multipart",
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
    # Persist HF downloads to the models volume to avoid cold re-downloads
    .env({"TRANSFORMERS_CACHE": "/models/hf", "HF_HOME": "/models/hf"})
)

models_volume = modal.Volume.from_name(os.getenv("MODELS_VOLUME", "tanoshi-models"), create_if_missing=True)
data_volume = modal.Volume.from_name(os.getenv("DATA_VOLUME", "tanoshi-data"), create_if_missing=True)

# Optional secret bundle for env vars when running on Modal
try:
    TANOSHI_SECRET = modal.Secret.from_name("tanoshi-env")
except Exception:
    TANOSHI_SECRET = None  # Allows local uvicorn import without Modal secrets

app = modal.App("tanoshi-narration")


@app.function(
    image=image,
    volumes={"/models": models_volume},
    secrets=[TANOSHI_SECRET] if 'TANOSHI_SECRET' in globals() and TANOSHI_SECRET else [],
)
def download_models() -> None:
    """One-shot task to populate /models with MAGI and SoVITS weights (idempotent)."""
    import pathlib
    import subprocess
    import os

    root = pathlib.Path("/models")
    root.mkdir(exist_ok=True, parents=True)

    # 1) Clone GPT-SoVITS (optional) into /models/GPT-SoVITS if not present
    repo_url = os.getenv("SOVITS_REPO_URL", "https://github.com/RVC-Boss/GPT-SoVITS.git")
    repo_dir = root / "GPT-SoVITS"
    if not repo_dir.exists():
        try:
            subprocess.run(["git", "clone", "--depth", "1", repo_url, str(repo_dir)], check=True)
        except Exception:
            pass
    # Ensure pretrained_models directory exists
    (repo_dir / "pretrained_models").mkdir(parents=True, exist_ok=True)

    # 2) Optionally fetch pretrained checkpoints if URLs provided (space- or comma-separated)
    # e.g., SOVITS_MODEL_URLS="https://.../gpt.pt,https://.../sovits.pth"
    model_urls = os.getenv("SOVITS_MODEL_URLS", "").replace("\n", " ").replace(",", " ").split()
    for u in model_urls:
        try:
            dest = (repo_dir / "pretrained_models" / pathlib.Path(u).name)
            if not dest.exists():
                subprocess.run(["curl", "-L", u, "-o", str(dest)], check=True)
        except Exception:
            continue

    # 3) Optional default voice reference for narrator (if provided)
    # e.g., DEFAULT_VOICE_REF_URL points to a small clean WAV/FLAC
    ref_url = os.getenv("DEFAULT_VOICE_REF_URL")
    if ref_url:
        narrator_dir = root / "voices" / "sovits:narrator-v1" / "refs"
        narrator_dir.mkdir(parents=True, exist_ok=True)
        ref_path = narrator_dir / "ref.wav"
        if not ref_path.exists():
            try:
                subprocess.run(["curl", "-L", ref_url, "-o", str(ref_path)], check=True)
            except Exception:
                pass

    # 4) Pre-cache MAGI v2 weights into HF cache (optional)
    try:
        from transformers import AutoModel  # type: ignore
        rev = os.getenv("MAGI_REVISION")
        if rev:
            AutoModel.from_pretrained("ragavsachdeva/magiv2", trust_remote_code=True, revision=rev)
        else:
            AutoModel.from_pretrained("ragavsachdeva/magiv2", trust_remote_code=True)
    except Exception:
        pass


@app.cls(
    image=image,
    gpu="L4",
    keep_warm=1,
    volumes={"/models": models_volume, "/data": data_volume},
    secrets=[TANOSHI_SECRET] if 'TANOSHI_SECRET' in globals() and TANOSHI_SECRET else [],
)
class NarrationService:
    """GPU-backed service that would host MAGI + SoVITS (stubbed)."""

    def __init__(self) -> None:
        self.loaded_at: Optional[float] = None

    @modal.enter()
    def load(self) -> None:
        # Load MAGI weights once from /models into RAM/GPU (kept warm).
        # Optional SoVITS preload could go here as well.
        try:
            # Reuse local helper to load MAGI; assumes CUDA available in this GPU container
            from transformers import AutoModel  # lazy import
            import torch  # type: ignore
            device = "cuda" if torch.cuda.is_available() else "cpu"
            if os.getenv("MAGI_REVISION"):
                self._magi = AutoModel.from_pretrained(
                    "ragavsachdeva/magiv2", trust_remote_code=True, revision=os.getenv("MAGI_REVISION")
                )
            else:
                self._magi = AutoModel.from_pretrained("ragavsachdeva/magiv2", trust_remote_code=True)
            try:
                self._magi.to(device)
            except Exception:
                pass
            self._magi.eval()
        except Exception:
            self._magi = None  # type: ignore[attr-defined]
        self.loaded_at = time.time()

    @modal.method()
    def synth(self, page_json: dict) -> str:
        """Stub: would run MAGI → SoVITS → write HLS; returns audio URL."""
        job_id = page_json.get("job_id", "job")
        index = page_json.get("page_index", 0)
        base = os.getenv("CDN_BASE_URL", "https://cdn.tanoshi.app")
        return f"{base}/audio/{job_id}/page-{index}/index.m3u8"

    @modal.method()
    def magi_chapter(self, job_id: str, indices: List[int]) -> List[int]:
        """Run MAGI chapter-wide prediction on the given uploaded pages.
        Reads PNGs from /data, writes MAGI JSON to /data, and returns processed indices.
        """
        if not hasattr(self, "_magi") or self._magi is None:  # type: ignore[attr-defined]
            # Fallback: try to load once if missing
            self.load()
        model = getattr(self, "_magi", None)
        if model is None:
            return []
        import numpy as np  # type: ignore
        from PIL import Image  # lazy import
        root = pathlib.Path("/data") / "narration" / job_id
        pages_dir = root / "pages"
        magi_dir = root / "magi"
        magi_dir.mkdir(parents=True, exist_ok=True)

        chapter_pages = []
        got_indices = []
        for i in indices:
            p = pages_dir / f"{i:03d}.png"
            if p.exists():
                with open(p, "rb") as f:
                    arr = np.array(Image.open(f).convert("L").convert("RGB"))
                chapter_pages.append(arr)
                got_indices.append(i)
        if not chapter_pages:
            return []
        character_bank = {"images": [], "names": []}
        # Inference (no grad)
        import torch  # type: ignore
        if torch.cuda.is_available():
            autocast_ctx = torch.autocast(device_type="cuda", dtype=torch.float16)
        else:
            from contextlib import nullcontext
            autocast_ctx = nullcontext()
        with torch.no_grad():
            with autocast_ctx:
                results = model.do_chapter_wide_prediction(
                    chapter_pages,
                    character_bank,
                    use_tqdm=False,
                    do_ocr=True,
                )
        # Persist
        try:
            import blake3  # type: ignore
        except Exception:
            blake3 = None  # type: ignore
        for i, page_result in zip(got_indices, results):
            page_path = pages_dir / f"{i:03d}.png"
            cache_key = None
            if blake3 is not None and page_path.exists():
                cache_key = blake3.blake3(page_path.read_bytes()).hexdigest()
            out = {
                "page_index": i,
                "cache_key": cache_key,
                "ocr": page_result.get("ocr"),
                "is_essential_text": page_result.get("is_essential_text"),
                "character_names": page_result.get("character_names"),
                "text_character_associations": page_result.get("text_character_associations"),
            }
            (magi_dir / f"page-{i:03d}.json").write_text(json.dumps(out, ensure_ascii=False))
        return got_indices


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
    magi_done_pages: Set[int] = field(default_factory=set)
    magi_lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    voice_pack: Dict[str, str] = field(default_factory=dict)
    api_base: str = ""
    processing_started: bool = False


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

def _redis_job_channel(job_id: str) -> str:
    return f"narration:job:{job_id}:events"

async def _emit_event(job: "JobState", event: str) -> None:
    # Local queue for same-instance listeners
    await job.events.put(event)
    # Cross-instance via Redis, if configured
    r = await get_redis()
    if r:
        try:
            await r.publish(_redis_job_channel(job.job_id), event)
        except Exception:
            pass

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
RATE_LIMIT_UPLOAD_MAX = int(os.getenv("RATE_LIMIT_UPLOAD_MAX", "120"))

async def _check_rate_limit(request: Request, kind: str) -> None:
    ip = request.client.host if request.client else "unknown"
    if kind == "start":
        max_allowed = RATE_LIMIT_START_MAX
    elif kind == "next":
        max_allowed = RATE_LIMIT_NEXT_MAX
    else:
        max_allowed = RATE_LIMIT_UPLOAD_MAX
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


def _make_presigned_put(job_id: str, idx: int, api_base: str) -> Dict[str, object]:
    # Direct PUT to API endpoint (absolute), using provided base for consistency
    return {
        "index": idx,
        "put_url": f"{api_base}/v1/narration/jobs/{job_id}/pages/{idx}",
        "content_type": "image/png",
        "max_bytes": 3_000_000,
    }


def _audio_url(job_id: str, idx: int) -> str:
    base = os.getenv("CDN_BASE_URL", "https://cdn.tanoshi.app")
    return f"{base}/audio/{job_id}/page-{idx}/index.m3u8"

def _ensure_voice_dirs(voice_id: str) -> Dict[str, pathlib.Path]:
    root = pathlib.Path("/models") / "voices" / voice_id
    (root / "refs").mkdir(parents=True, exist_ok=True)
    (root / "clips").mkdir(parents=True, exist_ok=True)
    return {"root": root, "refs": root / "refs", "clips": root / "clips"}

_TAG_RE = re.compile(r"<[^>]+>")

def _sanitize_text(text: str) -> str:
    # Remove bracketed tags like <other> and trim whitespace
    return _TAG_RE.sub("", text).strip()


def _ensure_terminal_punct(t: str) -> str:
    t = t.strip()
    if not t:
        return t
    if t[-1] in ".?!,;:" or t.endswith("…"):
        return t
    # Short interjection → comma, otherwise period
    return t + ("," if len(t) <= 3 else ".")


def _combine_utterances_for_page(job: "JobState", utts: List[Dict[str, str]]) -> (str, str):
    """Combine bubble texts into one natural sentence stream.
    Uses Narrator voice (or default) when character recognition is unavailable.
    """
    narrator = job.voice_pack.get("Narrator") or job.voice_pack.get("Default") or "sovits:narrator-v1"
    texts: List[str] = []
    for u in utts:
        txt = _ensure_terminal_punct(_sanitize_text(u.get("text", "")))
        if txt:
            texts.append(txt)
    combined = " ".join(texts)
    return combined, narrator


def _default_voice_pack() -> Dict[str, str]:
    return {"Narrator": "sovits:narrator-v1", "MC": "sovits:mc-v1"}

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


def _api_base_from_request(request: Request) -> str:
    """Derive the public API base from the incoming request.
    Honors X-Forwarded-* headers when behind a proxy; falls back to request.url.
    """
    proto = request.headers.get("x-forwarded-proto") or request.url.scheme or "https"
    host = request.headers.get("x-forwarded-host") or request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}"


# -----------------------------
# MAGI v2 integration (Modal-only)
# -----------------------------
_MAGI_MODEL = None
_MAGI_DEVICE = "cpu"
MAGI_START_AFTER_N_PAGES = int(os.getenv("MAGI_START_AFTER_N_PAGES", "4"))
MAGI_REVISION = os.getenv("MAGI_REVISION")  # optional HF commit hash/tag

# SoVITS (optional, zero-shot)
SOVITS_ENABLED = os.getenv("SOVITS_ENABLED", "false").lower() in {"1", "true", "yes"}
ESPEAK_ENABLED = os.getenv("ESPEAK_ENABLED", "true").lower() in {"1", "true", "yes"}
ESPEAK_VOICE_DEFAULT = os.getenv("ESPEAK_VOICE", "en")
ESPEAK_RATE = int(os.getenv("ESPEAK_RATE", "170"))
ESPEAK_PITCH = int(os.getenv("ESPEAK_PITCH", "50"))
ESPEAK_VOLUME = int(os.getenv("ESPEAK_VOLUME", "125"))
TTS_SAMPLE_RATE = int(os.getenv("TTS_SAMPLE_RATE", "24000"))
SOVITS_VERSION = os.getenv("SOVITS_VERSION", "v4")
SOVITS_PRETRAINED_SUBDIR = os.getenv("SOVITS_PRETRAINED_SUBDIR", "GPT_SoVITS/pretrained_models")
CHUNKED_TTS = os.getenv("CHUNKED_TTS", "true").lower() in {"1", "true", "yes"}

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
    # Log playlist presence and segments
    segs = list(page_dir.glob("seg-*.ts"))
    try:
        print(f"[hls] job={job_id} page={page_index} segs={len(segs)} playlist_bytes={playlist.stat().st_size}")
    except Exception:
        pass
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

    # Build chapter list using all currently uploaded pages; skip ones already processed by MAGI
    page_indices: List[int] = []
    chapter_pages = []
    for i in range(job.total):
        if i in job.magi_done_pages:
            continue
        p = dirs["pages"] / f"{i:03d}.png"
        if p.exists():
            chapter_pages.append(_read_image_to_numpy(p))
            page_indices.append(i)

    # Guard: do not run MAGI with no pages yet
    if not chapter_pages:
        return

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
        job.magi_done_pages.add(i)


def _build_utterances_for_page(job: JobState, dirs: Dict[str, pathlib.Path], page_index: int) -> List[Dict[str, str]]:
    """
    Build utterances from MAGI JSON for a page.
    Returns list of {speaker, voice_id, text}.
    """
    magi_path = dirs["magi"] / f"page-{page_index:03d}.json"
    if not magi_path.exists():
        return []
    data = json.loads(magi_path.read_text())
    ocr = data.get("ocr") or []
    essential = data.get("is_essential_text") or [True] * len(ocr)
    char_names = data.get("character_names") or []
    assoc = data.get("text_character_associations") or []  # list of [text_idx, char_idx]
    speaker_by_text = {int(ti): (char_names[int(ci)] if 0 <= int(ci) < len(char_names) else "Other") for ti, ci in assoc}
    utterances: List[Dict[str, str]] = []
    default_voice = job.voice_pack.get("Narrator") or job.voice_pack.get("Default") or "sovits:narrator-v1"
    for idx, raw in enumerate(ocr):
        if idx >= len(essential) or not essential[idx]:
            continue
        spk = speaker_by_text.get(idx, "Other")
        if spk == "MC":
            voice_id = job.voice_pack.get("MC") or default_voice
        elif spk == "Narrator":
            voice_id = job.voice_pack.get("Narrator") or default_voice
        else:
            voice_id = job.voice_pack.get(spk) or job.voice_pack.get("Narrator") or default_voice
        text = _sanitize_text(str(raw))
        if not text:
            continue
        utterances.append({"speaker": spk, "voice_id": voice_id, "text": text})
    return utterances


def _tts_cache_path(job_id: str, voice_id: str, text: str) -> pathlib.Path:
    h = hashlib.sha256((voice_id + "|" + text).encode("utf-8")).hexdigest()
    root = pathlib.Path("/data") / "narration" / job_id / "tts_cache"
    root.mkdir(parents=True, exist_ok=True)
    return root / f"tts-{h}.wav"


def _resolve_voice_ref(voice_id: str) -> Optional[pathlib.Path]:
    # Voices reside under /models/voices/{voice_id}/refs/ref.wav
    p = pathlib.Path("/models") / "voices" / voice_id / "refs" / "ref.wav"
    return p if p.exists() else None


def _write_hls_from_wav(job_id: str, page_index: int, wav_path: pathlib.Path) -> pathlib.Path:
    dirs = _ensure_dirs(job_id)
    page_dir = dirs["audio"] / f"page-{page_index:03d}"
    page_dir.mkdir(parents=True, exist_ok=True)
    playlist = page_dir / "index.m3u8"
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-i", str(wav_path),
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
        # Basic debug breadcrumbs for audio generation
        try:
            segs = sorted([p for p in page_dir.iterdir() if p.suffix == '.ts'])
            playlist_size = playlist.stat().st_size if playlist.exists() else -1
            print(f"[hls] job={job_id} page={page_index} segs={len(segs)} playlist_bytes={playlist_size}")
        except Exception:
            pass
    except Exception as e:
        # Fallback to dummy if conversion fails
        print(f"[hls_fallback] job={job_id} page={page_index} err={e}")
        _write_dummy_hls(job_id, page_index, duration=12.3)
    # Emit debug stats
    segs = list(page_dir.glob("seg-*.ts"))
    try:
        print(f"[hls] job={job_id} page={page_index} segs={len(segs)} playlist_bytes={playlist.stat().st_size}")
    except Exception:
        pass
    return playlist


def _concat_wavs_with_silence(wav_paths: List[pathlib.Path], out_wav: pathlib.Path, ms: int = 250) -> None:
    if not wav_paths:
        # generate 1s silence
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-t", "1", "-i", "anullsrc=r=24000:cl=mono",
            "-c:a", "pcm_s16le",
            str(out_wav)
        ], check=False)
        return
    work = out_wav.parent
    work.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []
    for i, p in enumerate(wav_paths):
        lines.append(f"file '{p.as_posix()}'")
        if i < len(wav_paths) - 1 and ms > 0:
            sil = work / f"sil-{i:03d}.wav"
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-t", str(ms / 1000.0), "-i", "anullsrc=r=24000:cl=mono",
                "-c:a", "pcm_s16le", str(sil)
            ], check=False)
            lines.append(f"file '{sil.as_posix()}'")
    list_file = work / "concat.txt"
    list_file.write_text("\n".join(lines))
    try:
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", str(list_file),
            "-c:a", "pcm_s16le",
            str(out_wav)
        ], check=True)
    except Exception:
        pass


def _sovits_synthesize(job_id: str, voice_id: str, text: str) -> pathlib.Path:
    # Cache first
    out = _tts_cache_path(job_id, voice_id, text)
    if out.exists():
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    if not SOVITS_ENABLED:
        # If espeak is enabled, synthesize speech via espeak-ng; otherwise fallback to a beep.
        if ESPEAK_ENABLED:
            # Pick a voice by language heuristic (ja if Japanese chars present)
            try:
                voice = ESPEAK_VOICE_DEFAULT
                if any("\u3040" <= ch <= "\u30ff" or "\u3400" <= ch <= "\u9fff" for ch in text):
                    voice = "ja"
                # Synthesize to WAV using espeak-ng
                subprocess.run([
                    "espeak-ng",
                    "-v", str(voice),
                    "-s", str(ESPEAK_RATE),
                    "-p", str(ESPEAK_PITCH),
                    "-a", str(ESPEAK_VOLUME),
                    "-w", str(out),
                    text
                ], check=False)
                # Ensure sample rate is TTS_SAMPLE_RATE
                tmp = out.with_suffix(".tmp.wav")
                subprocess.run([
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(out),
                    "-ar", str(TTS_SAMPLE_RATE), "-ac", "1",
                    "-c:a", "pcm_s16le", str(tmp)
                ], check=False)
                if tmp.exists():
                    out.unlink(missing_ok=True)
                    tmp.replace(out)
            except Exception:
                pass
            if out.exists():
                return out
            # Fallback if espeak failed
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-t", "1.0", "-i", "sine=frequency=1000:sample_rate=24000",
                "-c:a", "pcm_s16le", str(out)
            ], check=False)
            return out
        else:
            # Beep placeholder
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-t", "1.0", "-i", "sine=frequency=1000:sample_rate=24000",
                "-c:a", "pcm_s16le", str(out)
            ], check=False)
            return out
    # Attempt GPT-SoVITS import from /models (best-effort)
    try:
        sovits_root = pathlib.Path("/models") / "GPT-SoVITS"
        if sovits_root.exists():
            # Write a small runner script to call possible API variants
            runner = sovits_root / "_modal_runner.py"
            code = f"""
import sys, os
text = {text!r}
out = {str(out)!r}
sr = {TTS_SAMPLE_RATE!r}
ref = {str(_resolve_voice_ref(voice_id))!r}
sys.path.insert(0, {str(sovits_root)!r})
ok = False
try:
    from api import TTS  # type: ignore
    tts = TTS()
    tts.infer(text=text, ref_wav=ref, out_wav=out, sr=int(sr))
    ok = True
except Exception as e:
    try:
        from GPT_SoVITS.api import TTS  # type: ignore
        tts = TTS()
        tts.infer(text=text, ref_wav=ref, out_wav=out, sr=int(sr))
        ok = True
    except Exception as e2:
        pass
sys.exit(0 if ok else 1)
"""
            runner.write_text(code)
            # Run the script
            rc = subprocess.run([sys.executable, str(runner)], cwd=str(sovits_root))
            if rc.returncode == 0 and out.exists():
                return out
    except Exception:
        pass
    # Fallback to beep if GPT-SoVITS import/call fails
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-t", "1.0", "-i", "sine=frequency=440:sample_rate=24000",
        "-c:a", "pcm_s16le", str(out)
    ], check=False)
    return out

async def _process_job(job: JobState) -> None:
    queue = job.events

    # Initial queued statuses
    for i in range(job.total):
        await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'queued'})}\n\n")

    # Ensure directories
    dirs = _ensure_dirs(job.job_id)

    # Kick initial MAGI pass (it waits until enough pages uploaded)
    async with job.magi_lock:
        await _run_magi_for_job(job)

    pending = set(range(job.total))

    async def try_process_page(i: int) -> bool:
        page = job.pages[i]
        png_path = dirs["pages"] / f"{i:03d}.png"
        magi_path = dirs["magi"] / f"page-{i:03d}.json"
        if not png_path.exists() or not magi_path.exists():
            return False
        try:
            page.state = "extracting"
            await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'extracting'})}\n\n")

            page.state = "tts"
            await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'tts'})}\n\n")

            utts = _build_utterances_for_page(job, dirs, i)
            if not utts:
                raise RuntimeError("no utterances from MAGI")
            combined_text, voice_id = _combine_utterances_for_page(job, utts)
            if CHUNKED_TTS:
                # Synthesize each sentence separately and insert fixed pauses (approximate pacing)
                # Split on sentence terminators; keep non-empty
                sentences = re.split(r"(?<=[\.\?\!])\s+", combined_text)
                sentences = [s.strip() for s in sentences if s.strip()]
                wavs: List[pathlib.Path] = []
                for s in sentences:
                    wavs.append(_sovits_synthesize(job.job_id, voice_id, s))
                merged = (pathlib.Path("/data") / "narration" / job.job_id / f"page-{i:03d}.wav")
                merged.parent.mkdir(parents=True, exist_ok=True)
                _concat_wavs_with_silence(wavs, merged, ms=350)
                _write_hls_from_wav(job.job_id, i, merged)
            else:
                # Single TTS call per page; punctuation drives natural pauses
                wav = _sovits_synthesize(job.job_id, voice_id, combined_text)
                _write_hls_from_wav(job.job_id, i, wav)

            page.state = "ready"
            api_base = job.api_base or os.getenv("API_BASE_URL", "https://api.tanoshi.app")
            page.audio = f"{api_base}/v1/narration/jobs/{job.job_id}/audio/page-{i:03d}/index.m3u8"
            job.done += 1
            job.updated_at = time.time()

            await _emit_event(job, f"event: page_ready\ndata: {json.dumps({'index': i, 'audio': page.audio})}\n\n")
            await _emit_event(job, f"event: progress\ndata: {json.dumps({'done': job.done, 'total': job.total})}\n\n")
            await _persist_snapshot(job)
            return True
        except Exception as e:
            page.state = "error"
            page.reason = str(e)
            job.updated_at = time.time()
            await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': i, 'state': 'error', 'reason': page.reason})}\n\n")
            await _persist_snapshot(job)
            return True

    # Main scheduling loop: continue until all pages are ready/error
    while pending:
        progressed = False
        for i in list(pending):
            if await try_process_page(i):
                pending.discard(i)
                progressed = True
        if not progressed:
            # If more pages uploaded than MAGI processed, run MAGI again
            if len(job.magi_done_pages) < len(job.uploaded_pages):
                async with job.magi_lock:
                    await _run_magi_for_job(job)
            await asyncio.sleep(0.5)

    await _emit_event(job, "event: job_done\ndata: {\"ok\": true}\n\n")


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

    # Fill default voice pack if omitted
    if not req.voice_pack or len(req.voice_pack) == 0:
        req.voice_pack = _default_voice_pack()

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
                api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
                pages = [_make_presigned_put(existing_job_id, i, api_base) for i in range(req.window.size)]
                return {
                    "job_id": existing_job_id,
                    "upload": {"mode": "direct", "pages": pages},
                    "status_sse": f"{api_base}/v1/narration/jobs/{existing_job_id}/events",
                    "audio_url_template": f"{api_base}/v1/narration/jobs/{existing_job_id}/audio/page-{{index}}/index.m3u8",
                    "adPlan": {"kind": "placeholder", "duration_hint": 3},
                }
    else:
        # In-memory fallback
        now = time.time()
        entry = _IDEMP_MAP.get(idem_key)
        if entry and isinstance(entry.get("reset_at"), float) and now < float(entry["reset_at"]):
            existing_job_id = str(entry.get("job_id"))
            if existing_job_id in JOBS:
                api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
                pages = [_make_presigned_put(existing_job_id, i, api_base) for i in range(req.window.size)]
                return {
                    "job_id": existing_job_id,
                    "upload": {"mode": "direct", "pages": pages},
                    "status_sse": f"{api_base}/v1/narration/jobs/{existing_job_id}/events",
                    "audio_url_template": f"{api_base}/v1/narration/jobs/{existing_job_id}/audio/page-{{index}}/index.m3u8",
                    "adPlan": {"kind": "placeholder", "duration_hint": 3},
                }

    job_id = f"job_{uuid.uuid4().hex[:8]}"
    total = req.window.size

    api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
    job = JobState(job_id=job_id, total=total, api_base=api_base)
    for i in range(total):
        job.pages[i] = PageState(index=i)
    job.voice_pack = dict(req.voice_pack)
    JOBS[job_id] = job

    # Record idempotency mapping
    if r:
        await r.set(idem_key, job_id)
        await r.expire(idem_key, IDEMP_TTL_SECONDS)
    else:
        _IDEMP_MAP[idem_key] = {"job_id": job_id, "reset_at": time.time() + IDEMP_TTL_SECONDS}

    # Kick processing in background immediately (MAGI waits for uploads)
    if not job.processing_started:
        asyncio.create_task(_process_job(job))
        job.processing_started = True

    pages = [_make_presigned_put(job_id, i, api_base) for i in range(total)]
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
        # Reconstruct from Redis snapshot if available to avoid 404 on other instances
        r = await get_redis()
        snap_json = None
        if r:
            try:
                snap_json = await r.get(f"narration:job:{job_id}:snapshot")
            except Exception:
                pass
        job = _reconstruct_job_from_snapshot(job_id, snap_json) or JobState(job_id=job_id, total=20, api_base=os.getenv("API_BASE_URL", ""))
        for i in range(job.total):
            job.pages.setdefault(i, PageState(index=i))
        JOBS[job_id] = job

    async def event_stream() -> AsyncGenerator[bytes, None]:
        # Heartbeat every 15s to keep proxies happy
        heartbeat_interval = 15.0
        last_heartbeat = time.time()
        queue = job.events
        # If Redis available, also subscribe to Pub/Sub to receive cross-instance events
        r = await get_redis()
        pubsub = None
        if r:
            try:
                pubsub = r.pubsub()
                await pubsub.subscribe(_redis_job_channel(job.job_id))
            except Exception:
                pubsub = None
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

            delivered = False
            if pubsub is not None:
                try:
                    msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                    if msg and msg.get("type") == "message":
                        payload = msg.get("data")
                        if isinstance(payload, (bytes, bytearray)):
                            yield payload
                        elif isinstance(payload, str):
                            yield payload.encode("utf-8")
                        delivered = True
                except Exception:
                    pass
            if not delivered:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=1.0)
                    yield event.encode("utf-8")
                except asyncio.TimeoutError:
                    pass

            now = time.time()
            if now - last_heartbeat > heartbeat_interval:
                yield b": keep-alive\n\n"
                last_heartbeat = now

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


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
        # Recreate minimal job state if this request lands on a cold/other instance
        api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
        job = JobState(job_id=job_id, total=20, api_base=api_base)
        for i in range(job.total):
            job.pages[i] = PageState(index=i)
        JOBS[job_id] = job
    # Rate limit uploads per IP
    await _check_rate_limit(request, kind="upload")
    # Bounds check
    if page_index < 0 or page_index >= job.total:
        raise HTTPException(status_code=400, detail="invalid page index")

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
    # Ensure processing loop is running (cross-instance safety)
    if not job.processing_started:
        asyncio.create_task(_process_job(job))
        job.processing_started = True

    # Update state → extracting (MAGI will run shortly)
    page = job.pages.get(page_index)
    if page:
        page.state = "extracting"
        await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': page_index, 'state': 'extracting'})}\n\n")
        job.updated_at = time.time()
        await _persist_snapshot(job)

    return {"ok": True}


# -----------------------------
# Batch PNG uploads (multipart or zip)
# -----------------------------
@api.post("/v1/narration/jobs/{job_id}/pages/batch")
async def upload_pages_batch(job_id: str, request: Request):
    job = JOBS.get(job_id)
    if not job:
        # Recreate minimal job state on this instance if needed
        api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
        job = JobState(job_id=job_id, total=20, api_base=api_base)
        for i in range(job.total):
            job.pages[i] = PageState(index=i)
        JOBS[job_id] = job
    await _check_rate_limit(request, kind="upload")

    ctype = request.headers.get("content-type", "").lower()
    dirs = _ensure_dirs(job_id)
    saved: List[int] = []
    failed: List[str] = []
    total_bytes = 0

    def save_png_bytes(idx: int, data: bytes) -> None:
        nonlocal total_bytes
        if idx < 0 or idx >= job.total:
            failed.append(f"index {idx} out of range")
            return
        if len(data) > 3_000_000:
            failed.append(f"page {idx} too large")
            return
        # basic PNG header check
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            failed.append(f"page {idx} not png")
            return
        (dirs["pages"] / f"{idx:03d}.png").write_bytes(data)
        saved.append(idx)
        total_bytes += len(data)

    if "multipart/form-data" in ctype:
        form = await request.form()
        # Accept fields named page_0..page_19 or page_00..page_19
        items = []
        for key, val in form.multi_items():
            if not hasattr(val, "filename"):
                continue
            m = re.match(r"page[_-]?(\d{1,2})", key)
            if not m:
                continue
            idx = int(m.group(1))
            content = await val.read()  # type: ignore[attr-defined]
            items.append((idx, content))
        # Sort by index to have deterministic order
        for idx, content in sorted(items, key=lambda x: x[0]):
            save_png_bytes(idx, content)
    elif "application/zip" in ctype or "application/x-zip-compressed" in ctype:
        body = await request.body()
        import io, zipfile
        try:
            with zipfile.ZipFile(io.BytesIO(body)) as zf:
                # Accept files like 000.png .. 019.png or any name with a leading number
                namelist = zf.namelist()
                for name in namelist:
                    base = pathlib.Path(name).name
                    m = re.match(r"(\d{1,3})\.(png)$", base, flags=re.IGNORECASE)
                    if not m:
                        continue
                    idx = int(m.group(1))
                    if idx >= 100:
                        # Only 0..99 possible; we use 0..19
                        continue
                    data = zf.read(name)
                    save_png_bytes(idx, data)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"invalid zip: {e}")
    else:
        raise HTTPException(status_code=415, detail="Content-Type must be multipart/form-data or application/zip")

    # Emit extracting for saved pages and trigger MAGI threshold if reached
    for idx in saved:
        page = job.pages.get(idx)
        if page:
            page.state = "extracting"
            await _emit_event(job, f"event: page_status\ndata: {json.dumps({'index': idx, 'state': 'extracting'})}\n\n")
    job.uploaded_pages.update(saved)
    if len(job.uploaded_pages) >= min(MAGI_START_AFTER_N_PAGES, job.total):
        job.magi_start_event.set()
    # Ensure processing loop is running
    if not job.processing_started:
        asyncio.create_task(_process_job(job))
        job.processing_started = True

    job.updated_at = time.time()
    await _persist_snapshot(job)
    return {"accepted": len(saved), "failed": failed, "total_bytes": total_bytes}


# -----------------------------
# Serve HLS from /data
# -----------------------------
@api.get("/v1/narration/jobs/{job_id}/audio/page-{page_index}/index.m3u8")
async def get_playlist(job_id: str, page_index: int):
    dirs = _ensure_dirs(job_id)
    path = dirs["audio"] / f"page-{page_index:03d}" / "index.m3u8"
    if not path.exists() or path.stat().st_size == 0:
        # Attempt a short audible fallback to ensure the player has something to play
        try:
            _write_dummy_hls(job_id, page_index, duration=2.0)
            print(f"[hls_fallback] job={job_id} page={page_index} wrote dummy playlist")
            path = dirs["audio"] / f"page-{page_index:03d}" / "index.m3u8"
        except Exception:
            raise HTTPException(status_code=404, detail="playlist not found")
    print(f"[serve_playlist] job={job_id} page={page_index} bytes={path.stat().st_size}")
    return StreamingResponse(iter([path.read_bytes()]), media_type="application/vnd.apple.mpegurl")


@api.get("/v1/narration/jobs/{job_id}/audio/page-{page_index}/{segment}")
async def get_segment(job_id: str, page_index: int, segment: str):
    dirs = _ensure_dirs(job_id)
    # Validate segment strictly (e.g., seg-00001.ts, index.m3u8 is served by another route)
    if not re.fullmatch(r"seg-\d+\.ts", segment):
        raise HTTPException(status_code=400, detail="invalid segment name")
    safe = pathlib.Path(segment).name  # prevent path traversal
    path = dirs["audio"] / f"page-{page_index:03d}" / safe
    if not path.exists() or path.stat().st_size == 0:
        # Attempt to write a fallback HLS and serve the first segment
        try:
            _write_dummy_hls(job_id, page_index, duration=2.0)
            print(f"[hls_fallback] job={job_id} page={page_index} wrote dummy segs")
        except Exception:
            raise HTTPException(status_code=404, detail="segment not found")
        path = dirs["audio"] / f"page-{page_index:03d}" / safe
    try:
        print(f"[serve_segment] job={job_id} page={page_index} seg={segment} bytes={path.stat().st_size}")
    except Exception:
        pass
    # audio/ts segment
    return StreamingResponse(iter([path.read_bytes()]), media_type="video/MP2T")


@api.post("/v1/voices/register")
async def voice_register(req: VoiceRegisterRequest, request: Request):
    voice_id = f"sovits:{req.name.replace(' ', '-').lower()}"
    api_base = os.getenv("API_BASE_URL") or _api_base_from_request(request)
    # Direct PUT endpoints (Modal-only)
    return {
        "voice_id": voice_id,
        "upload": {
            "mode": "direct",
            "refs": [
                {"purpose": "zero_shot_ref", "put_url": f"{api_base}/v1/voices/{voice_id}/refs/ref.wav"}
            ],
            "dataset": {
                "audio_put_prefix": f"{api_base}/v1/voices/{voice_id}/clips/{{i}}.wav",
                "transcript_put_url": f"{api_base}/v1/voices/{voice_id}/transcripts.jsonl"
            }
        },
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
    }


@api.put("/v1/voices/{voice_id}/refs/ref.wav")
async def upload_voice_ref(voice_id: str, request: Request):
    # Accept WAV/FLAC; transcode elsewhere as needed
    ctype = request.headers.get("content-type", "").lower()
    if "audio/wav" not in ctype and "audio/x-wav" not in ctype and "audio/flac" not in ctype:
        raise HTTPException(status_code=415, detail="Content-Type must be audio/wav or audio/flac")
    body = await request.body()
    max_bytes = 20_000_000
    if len(body) > max_bytes:
        raise HTTPException(status_code=413, detail="reference too large")
    dirs = _ensure_voice_dirs(voice_id)
    # Validate audio properties: mono, ~24kHz, 5–30s
    try:
        import io
        import soundfile as sf  # type: ignore
        data, sr = sf.read(io.BytesIO(body), always_2d=False)
        duration = (len(data) / float(sr)) if sr else 0.0
        if sr not in (24000, 22050, 16000) or duration < 5.0 or duration > 30.0:
            raise HTTPException(status_code=400, detail="Reference must be 5–30s mono at ~24 kHz (16–24kHz accepted)")
    except HTTPException:
        raise
    except Exception:
        # If validation fails to parse, still save but warn by rejecting
        raise HTTPException(status_code=400, detail="Invalid audio file")
    (dirs["refs"] / "ref.wav").write_bytes(body)
    return {"ok": True}


@api.put("/v1/voices/{voice_id}/clips/{index}.wav")
async def upload_voice_clip(voice_id: str, index: int, request: Request):
    ctype = request.headers.get("content-type", "").lower()
    if "audio/wav" not in ctype and "audio/x-wav" not in ctype:
        raise HTTPException(status_code=415, detail="Content-Type must be audio/wav")
    body = await request.body()
    max_bytes = 20_000_000
    if len(body) > max_bytes:
        raise HTTPException(status_code=413, detail="clip too large")
    dirs = _ensure_voice_dirs(voice_id)
    (dirs["clips"] / f"{index:05d}.wav").write_bytes(body)
    return {"ok": True}


@api.put("/v1/voices/{voice_id}/transcripts.jsonl")
async def upload_voice_transcripts(voice_id: str, request: Request):
    ctype = request.headers.get("content-type", "").lower()
    if "application/json" not in ctype and "application/x-ndjson" not in ctype:
        raise HTTPException(status_code=415, detail="Content-Type must be application/json or application/x-ndjson")
    body = await request.body()
    if len(body) > 20_000_000:
        raise HTTPException(status_code=413, detail="transcripts too large")
    dirs = _ensure_voice_dirs(voice_id)
    (dirs["root"] / "transcripts.jsonl").write_bytes(body)
    return {"ok": True}


# Stub SSE for voices
@api.get("/v1/voices/{voice_id}/events")
async def voice_events(voice_id: str, request: Request):
    async def event_stream() -> AsyncGenerator[bytes, None]:
        # Send a one-time ready status, then keep-alive heartbeats
        yield f"event: voice_status\ndata: {{\"voice_id\": \"{voice_id}\", \"status\": \"ready\"}}\n\n".encode("utf-8")
        last = time.time()
        while True:
            if await request.is_disconnected():
                break
            await asyncio.sleep(10)
            now = time.time()
            if now - last >= 10:
                yield b": keep-alive\n\n"
                last = now
    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# Expose FastAPI via Modal as ASGI app (Modal 1.1.x)
@app.function(
    image=image,
    gpu="L4",
    volumes={"/models": models_volume, "/data": data_volume},
    secrets=[TANOSHI_SECRET] if 'TANOSHI_SECRET' in globals() and TANOSHI_SECRET else [],
)
@modal.asgi_app(label="api")
def fastapi_app():  # type: ignore[override]
    return api


@api.get("/web", response_class=HTMLResponse)
async def web_debug():
    # Minimal debug UI to exercise the flow manually
    html = """
    <!doctype html>
    <meta name=viewport content="width=device-width, initial-scale=1">
    <title>Tanoshi Narration Debug</title>
    <style>body{font-family:system-ui, -apple-system, Segoe UI, Roboto, sans-serif; max-width:860px; margin:24px auto; padding:0 12px}</style>
    <h1>Tanoshi Narration Debug</h1>
    <div>
      <label>Chapter ID <input id=chapter value="demo:ch000" size=30></label>
      <button id=start>Start</button>
    </div>
    <div id=uploadArea style="display:none;margin-top:12px;">
      <p>Upload PNG pages (0..19):</p>
      <input type=file id=file multiple accept="image/png">
      <button id=upload>Upload Selected</button>
    </div>
    <pre id=log style="background:#f6f6f6;padding:12px;border-radius:6px;white-space:pre-wrap"></pre>
    <script>
    const log = (...a)=>{document.getElementById('log').textContent += a.join(' ')+'\n'};
    let job = null; let plans = [];
    document.getElementById('start').onclick = async ()=>{
      const chapter = document.getElementById('chapter').value;
      const res = await fetch('/v1/narration/session/start', {method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify({chapter_id:chapter, voice_pack:{}, window:{start_index:0,size:20}, client:{device:'web',app_version:'debug'}})});
      const j = await res.json();
      job = j; plans = j.upload.pages;
      log('job_id', j.job_id); log('status_sse', j.status_sse);
      document.getElementById('uploadArea').style.display='block';
      const es = new EventSource(j.status_sse);
      ;['page_status','page_ready','progress','job_done'].forEach(type=>{
        es.addEventListener(type, e=>log(type, e.data));
      });
      es.onerror = (e)=>log('sse error', e);
    };
    document.getElementById('upload').onclick = async ()=>{
      const files = document.getElementById('file').files;
      const byName = {}; for (const f of files) byName[f.name]=f;
      for (const p of plans){
        const idx = p.index; const fname = String(idx).padStart(3,'0')+'.png';
        if(!byName[fname]) continue;
        await fetch(p.put_url, {method:'PUT', headers:{'content-type':'image/png'}, body: byName[fname]});
        log('uploaded', idx);
      }
    };
    </script>
    """;
    return HTMLResponse(content=html)

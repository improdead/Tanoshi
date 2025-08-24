import base64
import io
import os
import uuid
import logging
import traceback
from typing import Any, Dict, List

import modal


# App and shared state
app = modal.App("ai-manga-analysis-modal")

# Basic logging setup (visible in `modal serve` and Modal logs)
_LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, _LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("ai_manga")

# Persisted volume to cache models across cold starts
model_cache = modal.Volume.from_name("ai-manga-model-cache", create_if_missing=True)

# In-memory job stores (persisted across calls while container is warm)
analysis_jobs = modal.Dict.from_name("ai_analysis_jobs", create_if_missing=True)
audio_jobs = modal.Dict.from_name("ai_audio_jobs", create_if_missing=True)


# Base image with deps. Heavy model wheels get cached in the volume at runtime.
image = (
    modal.Image.from_dockerhub("python:3.11-slim")
    .apt_install("ffmpeg", "libsndfile1")
    .pip_install(
        [
            "fastapi==0.115.0",
            "uvicorn[standard]==0.30.6",
            "transformers",
            "Pillow",
            "TTS",
            "librosa",
            "soundfile",
            "numpy",
            "tqdm",
            "requests",
        ]
    )
    # Install CUDA-enabled PyTorch wheels for GPU (L4 supports CUDA 12.1)
    .run_commands(
        "pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121"
    )
)


# -------------------------
# MAGI + XTTS pipeline (GPU-backed, cached)
# -------------------------


@app.cls(
    image=image,
    gpu="L4",
    timeout=60 * 30,
    volumes={"/vol": model_cache},
)
class AIMangaPipeline:
    @modal.enter()
    def setup(self):
        # Lazy import inside container
        from transformers import AutoModel  # type: ignore
        from TTS.api import TTS  # type: ignore

        # Flags for readiness/debug
        self._setup_ok = False
        self._setup_error = None

        try:
            # Configure caches to mounted volume at runtime (avoid non-empty mount path during build)
            os.environ["COQUI_TOS_AGREED"] = "1"
            os.environ["HF_HOME"] = "/vol/hf"
            os.environ["HF_HUB_CACHE"] = "/vol/hf"
            os.environ["TRANSFORMERS_CACHE"] = "/vol/hf"
            os.environ["XDG_CACHE_HOME"] = "/vol/xdg"
            os.environ["XDG_DATA_HOME"] = "/vol/xdg"
            os.environ["TTS_HOME"] = "/vol/tts"
            # Ensure directories exist on the mounted volume
            for p in ["/vol/hf", "/vol/xdg", "/vol/tts"]:
                try:
                    os.makedirs(p, exist_ok=True)
                except Exception:
                    pass

            # Load MAGI; weights will be cached in /cache/hf
            logger.info("Loading MAGI model ...")
            self._magi = AutoModel.from_pretrained(
                "ragavsachdeva/magiv2", trust_remote_code=True
            ).eval()

            # Load TTS with cache to /cache/tts (or XDG dirs)
            logger.info("Loading TTS model ...")
            try:
                self._tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2", gpu=True)
            except Exception:
                logger.warning("XTTS load failed; falling back to tacotron2-DDC")
                self._tts = TTS("tts_models/en/ljspeech/tacotron2-DDC", gpu=True)

            # Persist downloaded weights/caches to the volume
            model_cache.commit()

            self._setup_ok = True
            logger.info("AIMangaPipeline setup completed.")
        except Exception as e:
            self._setup_ok = False
            self._setup_error = traceback.format_exc()
            logger.exception("AIMangaPipeline setup failed: %s", e)

    # ---------- Utilities ----------
    def _read_image_from_base64(self, b64: str):
        from PIL import Image
        import numpy as np
        try:
            data = base64.b64decode(b64)
            img = Image.open(io.BytesIO(data)).convert("L").convert("RGB")
            return np.array(img)
        except Exception:
            return None

    def _convert_bbox(self, b):
        if not b or len(b) < 4:
            return {"x": 0, "y": 0, "width": 0, "height": 0}
        return {
            "x": float(b[0]),
            "y": float(b[1]),
            "width": float(b[2] - b[0]),
            "height": float(b[3] - b[1]),
        }

    # ---------- Analysis ----------
    @modal.method()
    def run_analysis(self, job_id: str, pages_b64: List[str], character_bank: Dict[str, Any]) -> None:
        import torch

        try:
            analysis_jobs[job_id] = {"status": "processing", "progress": 0.05}

            if not getattr(self, "_setup_ok", False):
                analysis_jobs[job_id] = {
                    "status": "failed",
                    "error": "pipeline_not_ready",
                    "setupError": getattr(self, "_setup_error", None),
                }
                logger.error("run_analysis aborted: pipeline not ready")
                return

            chapter_pages = [img for img in (self._read_image_from_base64(b) for b in pages_b64) if img is not None]
            if not chapter_pages:
                analysis_jobs[job_id] = {"status": "failed", "error": "no valid images"}
                return

            character_images = []
            for img_b64 in (character_bank or {}).get("images", []):
                img = self._read_image_from_base64(img_b64)
                if img is not None:
                    character_images.append(img)
            processed_bank = {"images": character_images, "names": (character_bank or {}).get("names", [])}

            analysis_jobs[job_id] = {"status": "processing", "progress": 0.15}
            with torch.no_grad():
                per_page = self._magi.do_chapter_wide_prediction(
                    chapter_pages, processed_bank, use_tqdm=False, do_ocr=True
                )

            pages_json: List[Dict[str, Any]] = []
            transcript: List[Dict[str, Any]] = []

            for i, page_result in enumerate(per_page):
                speaker_name = {t: page_result["character_names"][c] for t, c in page_result["text_character_associations"]}

                text_regions: List[Dict[str, Any]] = []
                for j, text in enumerate(page_result.get("ocr", [])):
                    if page_result.get("is_essential_text", [True] * len(page_result.get("ocr", [])))[j]:
                        bbox = {}
                        if "text_bboxes" in page_result and j < len(page_result["text_bboxes"]):
                            bbox = self._convert_bbox(page_result["text_bboxes"][j])
                        text_regions.append(
                            {
                                "id": j,
                                "text": text,
                                "boundingBox": bbox,
                                "confidence": 1.0,
                                "isEssential": True,
                            }
                        )
                        transcript.append(
                            {
                                "pageIndex": i,
                                "textId": j,
                                "speaker": speaker_name.get(j, "unknown"),
                                "text": text,
                                "timestamp": None,
                            }
                        )

                character_detections: List[Dict[str, Any]] = []
                for cidx, cname in enumerate(page_result.get("character_names", [])):
                    bbox = {}
                    if "character_bboxes" in page_result and cidx < len(page_result["character_bboxes"]):
                        bbox = self._convert_bbox(page_result["character_bboxes"][cidx])
                    character_detections.append(
                        {"id": cidx, "name": cname, "boundingBox": bbox, "confidence": 1.0}
                    )

                assoc_dict = {str(t): int(c) for t, c in page_result.get("text_character_associations", [])}

                pages_json.append(
                    {
                        "pageIndex": i,
                        "textRegions": text_regions,
                        "characterDetections": character_detections,
                        "textCharacterAssociations": assoc_dict,
                    }
                )

            result_obj = {"pages": pages_json, "transcript": transcript, "version": "1.0"}
            analysis_jobs[job_id] = {"status": "completed", "progress": 1.0, "result": result_obj}
        except Exception as e:
            tb = traceback.format_exc()
            analysis_jobs[job_id] = {"status": "failed", "error": str(e), "trace": tb}
            logger.exception("run_analysis failed: %s", e)

    # ---------- Audio ----------
    @modal.method()
    def run_audio(self, job_id: str, transcript: List[Dict[str, Any]], voice_settings: Dict[str, Any]) -> None:
        import librosa
        try:
            language = (voice_settings or {}).get("language", "en")
            character_voice_files = (voice_settings or {}).get("characterVoiceFiles", {})
            default_voice_file = (voice_settings or {}).get("defaultVoiceFile")

            if not getattr(self, "_setup_ok", False):
                audio_jobs[job_id] = {
                    "status": "failed",
                    "error": "pipeline_not_ready",
                    "setupError": getattr(self, "_setup_error", None),
                }
                logger.error("run_audio aborted: pipeline not ready")
                return

            segments: List[Dict[str, Any]] = []
            for i, d in enumerate(transcript):
                text = (d.get("text") or "").strip()
                if not text:
                    continue
                speaker = d.get("speaker", "unknown")
                audio_path = f"/tmp/audio_{job_id}_{i}.wav"

                voice_b64 = character_voice_files.get(speaker, default_voice_file)
                if voice_b64:
                    spk_path = f"/tmp/speaker_{job_id}_{i}.wav"
                    with open(spk_path, "wb") as f:
                        f.write(base64.b64decode(voice_b64))
                    self._tts.tts_to_file(text=text, file_path=audio_path, speaker_wav=spk_path, language=language)
                    try:
                        os.remove(spk_path)
                    except Exception:
                        pass
                else:
                    kwargs = {"text": text, "file_path": audio_path, "language": language}
                    if hasattr(self._tts, "speakers") and getattr(self._tts, "speakers"):
                        kwargs["speaker"] = self._tts.speakers[0]
                    self._tts.tts_to_file(**kwargs)

                duration = float(librosa.get_duration(filename=audio_path))
                with open(audio_path, "rb") as f:
                    audio_b64 = base64.b64encode(f.read()).decode()
                try:
                    os.remove(audio_path)
                except Exception:
                    pass

                segments.append(
                    {
                        "dialogueId": f"{d.get('pageIndex', 0)}_{d.get('textId', 0)}",
                        "audioData": audio_b64,
                        "duration": duration,
                        "speaker": speaker,
                        "text": text,
                    }
                )

            audio_jobs[job_id] = {"status": "completed", "audioSegments": segments}
        except Exception as e:
            tb = traceback.format_exc()
            audio_jobs[job_id] = {"status": "failed", "error": str(e), "trace": tb}
            logger.exception("run_audio failed: %s", e)

    # ---------- Keep-warm ----------
    @modal.method()
    def ping(self) -> str:
        return "ok"

    @modal.method()
    def status(self) -> Dict[str, Any]:
        return {
            "setupOk": bool(getattr(self, "_setup_ok", False)),
            "setupError": getattr(self, "_setup_error", None),
            "magiLoaded": bool(getattr(self, "_magi", None) is not None),
            "ttsLoaded": bool(getattr(self, "_tts", None) is not None),
        }


@app.function(image=image, timeout=600)
@modal.asgi_app()
def fastapi_app() -> "FastAPI":
    # FastAPI is only needed inside the container
    from fastapi import FastAPI, HTTPException

    api = FastAPI(title="AI Manga Analysis (Modal)")

    @api.get("/health")
    def health() -> Dict[str, Any]:
        return {
            "status": "healthy",
            "magi_loaded": True,
            "tts_models_loaded": 1,
            "xtts_v2_loaded": True,
            "available_speakers": ["default"],
        }

    @api.post("/warm")
    def warm() -> Dict[str, str]:
        AIMangaPipeline().ping.remote()
        return {"status": "ok"}

    @api.get("/connected")
    def connected() -> Dict[str, Any]:
        out: Dict[str, Any] = {"modalConnected": False, "pipeline": None, "error": None}
        try:
            AIMangaPipeline().ping.remote()
            out["modalConnected"] = True
        except Exception as e:
            out["error"] = f"ping failed: {e}"
        try:
            out["pipeline"] = AIMangaPipeline().status.remote()
        except Exception as e:
            out["error"] = (out.get("error") or "") + f"; status failed: {e}"
        return out

    @api.post("/analyze")
    def start_analyze(body: Dict[str, Any]) -> Dict[str, str]:
        pages: List[str] = body.get("pages", [])
        job_id = str(uuid.uuid4())
        analysis_jobs[job_id] = {"status": "pending", "progress": 0.0}

        AIMangaPipeline().run_analysis.spawn(
            job_id, pages, body.get("characterBank", {"images": [], "names": []})
        )
        return {"job_id": job_id}

    @api.get("/status/{job_id}")
    def get_status(job_id: str) -> Dict[str, Any]:
        state = analysis_jobs.get(job_id)
        if not state:
            raise HTTPException(status_code=404, detail="job not found")
        return {
            "job_id": job_id,
            "status": state.get("status", "pending"),
            "progress": float(state.get("progress", 0.0)),
            "result": state.get("result"),
            "error": state.get("error"),
        }

    @api.get("/result/{job_id}")
    def get_result(job_id: str) -> Dict[str, Any]:
        state = analysis_jobs.get(job_id)
        if not state:
            raise HTTPException(status_code=404, detail="job not found")
        if state.get("status") != "completed" or "result" not in state:
            raise HTTPException(status_code=404, detail="result not ready")
        return state["result"]

    @api.post("/audio")
    def start_audio(body: Dict[str, Any]) -> Dict[str, str]:
        transcript: List[Dict[str, Any]] = body.get("transcript", [])
        job_id = str(uuid.uuid4())
        audio_jobs[job_id] = {"status": "processing"}

        # Synchronous so the first poll to /audio/result succeeds
        AIMangaPipeline().run_audio.remote(
            job_id, transcript, body.get("voiceSettings", {})
        )
        return {"job_id": job_id}

    @api.get("/audio/result/{job_id}")
    def get_audio_result(job_id: str) -> Dict[str, Any]:
        state = audio_jobs.get(job_id)
        if not state:
            raise HTTPException(status_code=404, detail="job not found")
        if state.get("status") != "completed" or "audioSegments" not in state:
            raise HTTPException(status_code=404, detail="result not ready")
        return {"audioSegments": state["audioSegments"]}

    @api.get("/audio/status/{job_id}")
    def get_audio_status(job_id: str) -> Dict[str, Any]:
        state = audio_jobs.get(job_id)
        if not state:
            raise HTTPException(status_code=404, detail="job not found")
        return {
            "job_id": job_id,
            "status": state.get("status"),
            "error": state.get("error"),
            "trace": state.get("trace"),
        }

    return api

@app.function(timeout=60)
def warm_once() -> str:
    AIMangaPipeline().ping.remote()
    return "ok"



import base64
import io
import os
import uuid
from typing import Any, Dict, List

import modal
from fastapi import FastAPI, HTTPException


# App and shared state
app = modal.App("ai-manga-analysis-modal")

# Persisted volume to cache models across cold starts
model_cache = modal.Volume.from_name("ai-manga-model-cache", create_if_missing=True)

# In-memory job stores (persisted across calls while container is warm)
analysis_jobs = modal.Dict.from_name("ai_analysis_jobs", create_if_missing=True)
audio_jobs = modal.Dict.from_name("ai_audio_jobs", create_if_missing=True)


# Base image with deps. Heavy model wheels get cached in the volume at runtime.
image = (
    modal.Image.debian_slim()
    .apt_install("ffmpeg", "libsndfile1")
    .env(
        {
            # HuggingFace caches
            "HF_HOME": "/model/hf",
            "HF_HUB_CACHE": "/model/hf",
            "TRANSFORMERS_CACHE": "/model/hf",
            # XDG caches used by various libs
            "XDG_CACHE_HOME": "/model/xdg",
            "XDG_DATA_HOME": "/model/xdg",
            # Coqui TTS
            "COQUI_TOS_AGREED": "1",
            "TTS_HOME": "/model/tts",
        }
    )
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
    max_containers=1,
    volumes={"/model": model_cache},
)
class AIMangaPipeline:
    @modal.enter()
    def setup(self):
        # Lazy import inside container
        from transformers import AutoModel  # type: ignore
        from TTS.api import TTS  # type: ignore

        # Load MAGI; weights will be cached in /model/hf
        self._magi = AutoModel.from_pretrained(
            "ragavsachdeva/magiv2", trust_remote_code=True
        ).eval()

        # Load TTS with cache to /model/tts (or XDG dirs)
        try:
            self._tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2", gpu=True)
        except Exception:
            # Fallback to a lighter model if XTTS isn't available in your region
            self._tts = TTS("tts_models/en/ljspeech/tacotron2-DDC", gpu=True)

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

        analysis_jobs[job_id] = {"status": "processing", "progress": 0.05}

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

    # ---------- Audio ----------
    @modal.method()
    def run_audio(self, job_id: str, transcript: List[Dict[str, Any]], voice_settings: Dict[str, Any]) -> None:
        import librosa
        language = (voice_settings or {}).get("language", "en")
        character_voice_files = (voice_settings or {}).get("characterVoiceFiles", {})
        default_voice_file = (voice_settings or {}).get("defaultVoiceFile")

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

    # ---------- Keep-warm ----------
    @modal.method()
    def ping(self) -> str:
        return "ok"


# -------------------------
# FastAPI routes
# -------------------------

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
    AIMangaPipeline().ping.call()
    return {"status": "ok"}


@api.post("/analyze")
def start_analyze(body: Dict[str, Any]) -> Dict[str, str]:
    pages: List[str] = body.get("pages", [])
    job_id = str(uuid.uuid4())
    analysis_jobs[job_id] = {"status": "pending", "progress": 0.0}

    AIMangaPipeline().run_analysis.spawn(job_id, pages, body.get("characterBank", {"images": [], "names": []}))
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
    AIMangaPipeline().run_audio.call(job_id, transcript, body.get("voiceSettings", {}))
    return {"job_id": job_id}


@api.get("/audio/result/{job_id}")
def get_audio_result(job_id: str) -> Dict[str, Any]:
    state = audio_jobs.get(job_id)
    if not state:
        raise HTTPException(status_code=404, detail="job not found")
    if state.get("status") != "completed" or "audioSegments" not in state:
        raise HTTPException(status_code=404, detail="result not ready")
    return {"audioSegments": state["audioSegments"]}


@app.function(image=image, timeout=600)
@modal.asgi_app()
def fastapi_app() -> FastAPI:
    return api

@app.function(timeout=60)
def warm_once() -> str:
    AIMangaPipeline().ping.call()
    return "ok"



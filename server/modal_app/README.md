# AI Manga Analysis Server (Modal, L4 + Cached)

- GPU: NVIDIA L4 (`gpu="L4"`)
- Persisted volume: `ai-manga-model-cache` mounted at `/model` to cache HF and TTS assets across cold starts
- Endpoints: `/health`, `/analyze`, `/status/{job_id}`, `/result/{job_id}`, `/audio`, `/audio/result/{job_id}`

Setup (CLI requires Python 3.11)
```bash
# ensure Python 3.11 for Modal CLI
pyenv install 3.11.9
pyenv local 3.11.9

pip install -r server/modal_app/requirements.txt
python -m modal setup

# run ephemeral server and get URL
modal serve server/modal_app/app.py
```

Point iOS app to your URL
```bash
defaults write app.tanoshi ai_analysis_colab_endpoint_url https://<your-modal-url>
defaults write app.tanoshi ai_analysis_auto_enabled -bool YES
```

Notes
- Model weights and caches persist under `/model` so subsequent cold starts avoid re-downloading.
- First boot may take a few minutes while models download.
- If L4 capacity is unavailable, change `gpu="L4"` to another GPU supported in your region.
# AI Manga Analysis Server (Modal)

This is a Modal-based FastAPI app that mirrors the endpoints expected by the iOS client. Use it as a drop-in replacement for the previous Google Colab/ngrok backend.

Endpoints (all JSON):
- GET /health
- POST /analyze -> {"job_id": "..."}
- GET /status/{job_id}
- GET /result/{job_id}
- POST /audio -> {"job_id": "..."}
- GET /audio/result/{job_id}

Quick start
1) Install Modal and authenticate (one-time):
```
pip install -r server/modal_app/requirements.txt
python3 -m modal setup
```

2) Run locally on Modal
- Start an ephemeral serve to get a public URL from Modal:
```
modal serve server/modal_app/app.py
```
  - Modal will print a URL for the FastAPI app. Copy it.

3) Point the iOS app to your Modal URL
In Xcode LLDB while the app is running, or in code at startup:
```
expr -l Swift -- UserDefaults.standard.set("https://<your-modal-url>", forKey: "ai_analysis_colab_endpoint_url")
expr -l Swift -- UserDefaults.standard.set(true, forKey: "ai_analysis_auto_enabled")
```

Notes
- This starter returns placeholder analysis and silent WAV audio for wiring and testing. Replace the workers in `analysis_worker` and `audio_worker` with your real models (OCR, MAGI, XTTS-v2, etc.).
- JSON field names match what the iOS client expects (snake_case where the client uses `convertFromSnakeCase`).
- You can deploy to Modal permanently with `modal deploy server/modal_app/app.py` and use the resulting URL.


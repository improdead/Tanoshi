from fastapi import FastAPI
from .modal_app import api as app  # reuse the FastAPI app defined for Modal

# Run with: uvicorn backend.server:app --reload --port 8080


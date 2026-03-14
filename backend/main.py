import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

load_dotenv()

from routes.speech_agent import router as speech_agent_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("blindspot")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Blindspot backend starting up")
    logger.info(f"  SMALLEST_AI_API_KEY set: {'yes' if os.getenv('SMALLEST_AI_API_KEY') else 'no'}")
    logger.info(f"  OPENAI_API_KEY set: {'yes' if os.getenv('OPENAI_API_KEY') else 'no'}")
    yield
    logger.info("Blindspot backend shutting down")


app = FastAPI(
    title="Blindspot Backend",
    description="Voice AI assistant backend for the Blindspot accessibility app",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(speech_agent_router)


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "blindspot-backend"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )

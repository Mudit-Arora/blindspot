import json
import logging
import base64

from fastapi import APIRouter, UploadFile, File, Form
from fastapi.responses import JSONResponse

from services.scene_context_builder import SceneContextBuilder
from services.smallest_ai_service import SmallestAIService

logger = logging.getLogger("blindspot.speech_agent")
router = APIRouter()

ai_service = SmallestAIService()
context_builder = SceneContextBuilder()


@router.post("/api/speech-agent")
async def speech_agent(
    audio: UploadFile = File(...),
    scene: str = Form("{}"),
):
    """
    Accepts audio file + scene JSON, returns JSON with transcripts and base64 audio.
    """
    logger.info(f"Speech-agent request: audio={audio.filename}, scene_len={len(scene)}")

    audio_bytes = await audio.read()
    scene_data = json.loads(scene)
    scene_context = context_builder.build_context(scene_data)

    try:
        user_text = await ai_service.transcribe_audio(audio_bytes)
        logger.info(f"User said: {user_text}")

        assistant_text = await ai_service.generate_response(
            user_text=user_text,
            scene_context=scene_context,
        )
        logger.info(f"Assistant: {assistant_text}")

        response_audio = await ai_service.text_to_speech(assistant_text)

        return JSONResponse(content={
            "user_text": user_text,
            "assistant_text": assistant_text,
            "audio_base64": base64.b64encode(response_audio).decode("utf-8"),
        })

    except Exception as e:
        logger.error(f"Processing error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": str(e)},
        )

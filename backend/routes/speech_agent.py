import json
import logging
import io

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, UploadFile, File, Form
from fastapi.responses import Response

from services.audio_processing import AudioProcessor
from services.scene_context_builder import SceneContextBuilder
from services.smallest_ai_service import SmallestAIService

logger = logging.getLogger("blindspot.speech_agent")
router = APIRouter()

ai_service = SmallestAIService()
audio_processor = AudioProcessor()
context_builder = SceneContextBuilder()


# ---------------------------------------------------------------------------
# WebSocket endpoint — low-latency streaming
# ---------------------------------------------------------------------------

@router.websocket("/ws/speech-agent")
async def websocket_speech_agent(websocket: WebSocket):
    await websocket.accept()
    logger.info("WebSocket client connected")

    scene_context = ""
    audio_buffer = bytearray()

    try:
        while True:
            message = await websocket.receive()

            if "text" in message:
                data = json.loads(message["text"])
                msg_type = data.get("type", "")

                if msg_type == "session_start":
                    scene_json = data.get("scene", "{}")
                    if isinstance(scene_json, str):
                        scene_data = json.loads(scene_json)
                    else:
                        scene_data = scene_json

                    scene_context = context_builder.build_context(scene_data)
                    audio_buffer = bytearray()
                    logger.info(f"Session started with scene context: {scene_context[:200]}")
                    await websocket.send_json({"type": "session_ready"})

                elif msg_type == "audio_end":
                    logger.info(f"Audio received: {len(audio_buffer)} bytes")
                    await websocket.send_json({"type": "processing"})

                    try:
                        # 1. Transcribe user audio
                        user_text = await ai_service.transcribe_audio(bytes(audio_buffer))
                        logger.info(f"User said: {user_text}")

                        # 2. Generate response text using LLM with scene context
                        assistant_text = await ai_service.generate_response(
                            user_text=user_text,
                            scene_context=scene_context,
                        )
                        logger.info(f"Assistant response: {assistant_text}")

                        # Send transcripts
                        await websocket.send_json({
                            "type": "transcript",
                            "user_text": user_text,
                            "assistant_text": assistant_text,
                        })

                        # 3. Synthesize response audio
                        response_audio = await ai_service.text_to_speech(assistant_text)

                        # Send audio as binary
                        await websocket.send_bytes(response_audio)
                        await websocket.send_json({"type": "response_end"})

                    except Exception as e:
                        logger.error(f"Processing error: {e}")
                        await websocket.send_json({
                            "type": "error",
                            "message": str(e),
                        })

                    audio_buffer = bytearray()

            elif "bytes" in message:
                audio_buffer.extend(message["bytes"])

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")


# ---------------------------------------------------------------------------
# REST endpoint — fallback for simpler request/response
# ---------------------------------------------------------------------------

@router.post("/api/speech-agent")
async def rest_speech_agent(
    audio: UploadFile = File(...),
    scene: str = Form("{}"),
):
    """
    REST fallback: accepts audio file + scene JSON, returns WAV audio response.
    """
    logger.info(f"REST speech-agent request: audio={audio.filename}, scene_len={len(scene)}")

    audio_bytes = await audio.read()
    scene_data = json.loads(scene)
    scene_context = context_builder.build_context(scene_data)

    # 1. Transcribe
    user_text = await ai_service.transcribe_audio(audio_bytes)
    logger.info(f"User said: {user_text}")

    # 2. Generate response
    assistant_text = await ai_service.generate_response(
        user_text=user_text,
        scene_context=scene_context,
    )
    logger.info(f"Assistant: {assistant_text}")

    # 3. Synthesize speech
    response_audio = await ai_service.text_to_speech(assistant_text)

    return Response(
        content=response_audio,
        media_type="audio/wav",
        headers={
            "X-User-Text": user_text,
            "X-Assistant-Text": assistant_text,
        },
    )

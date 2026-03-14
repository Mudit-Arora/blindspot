"""
AI service that integrates:
  - Speech-to-text (OpenAI Whisper or Smallest.ai)
  - LLM reasoning (OpenAI GPT)
  - Text-to-speech (Smallest.ai Lightning or OpenAI TTS as fallback)

Set environment variables:
  SMALLEST_AI_API_KEY  — for Smallest.ai TTS
  OPENAI_API_KEY       — for Whisper STT + GPT reasoning (+ fallback TTS)
"""

import os
import io
import logging
import struct

import httpx
from openai import AsyncOpenAI

logger = logging.getLogger("blindspot.ai_service")

SMALLEST_AI_API_KEY = os.getenv("SMALLEST_AI_API_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

SYSTEM_PROMPT = """You are Blindspot, a voice assistant for blind and visually impaired users.

Your job is to describe the user's surroundings clearly, concisely, and helpfully,
based on a computer-vision scene description provided as context.

Rules:
- Use spatial language: "on your left", "directly ahead", "to your right"
- Prioritize safety: mention hazards (potholes, construction, vehicles) first
- Give distances when available
- Be concise — the user is navigating in real time
- Speak naturally, as if talking to a friend
- If asked about something not in the scene data, say you can only describe what the camera sees
- Never mention bounding boxes, confidence scores, or technical details
"""


class SmallestAIService:

    def __init__(self):
        self.openai_client = AsyncOpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
        self.http_client = httpx.AsyncClient(timeout=30.0)

    # ------------------------------------------------------------------
    # Speech-to-Text
    # ------------------------------------------------------------------

    async def transcribe_audio(self, audio_bytes: bytes) -> str:
        """Transcribe WAV audio to text using OpenAI Whisper."""
        if not self.openai_client:
            logger.warning("No OPENAI_API_KEY — returning placeholder transcription")
            return "what is around me?"

        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = "recording.wav"

        transcript = await self.openai_client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            response_format="text",
        )
        return transcript.strip()

    # ------------------------------------------------------------------
    # LLM Reasoning
    # ------------------------------------------------------------------

    async def generate_response(self, user_text: str, scene_context: str) -> str:
        """Generate a navigation-assistant response using GPT."""
        if not self.openai_client:
            logger.warning("No OPENAI_API_KEY — returning placeholder response")
            return self._placeholder_response(scene_context)

        user_message = f"Scene description:\n{scene_context}\n\nUser says: \"{user_text}\""

        response = await self.openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            max_tokens=300,
            temperature=0.7,
        )

        return response.choices[0].message.content.strip()

    # ------------------------------------------------------------------
    # Text-to-Speech
    # ------------------------------------------------------------------

    async def text_to_speech(self, text: str) -> bytes:
        """
        Convert text to speech audio (WAV).
        Tries Smallest.ai Lightning first, falls back to OpenAI TTS.
        """
        if SMALLEST_AI_API_KEY:
            try:
                return await self._smallest_ai_tts(text)
            except Exception as e:
                logger.warning(f"Smallest.ai TTS failed, falling back to OpenAI: {e}")

        if self.openai_client:
            return await self._openai_tts(text)

        logger.warning("No TTS API key available — returning silence")
        return self._generate_silence_wav(duration_seconds=1)

    async def _smallest_ai_tts(self, text: str) -> bytes:
        """Call Smallest.ai Lightning TTS API."""
        response = await self.http_client.post(
            "https://waves-api.smallest.ai/api/v1/lightning/get_speech",
            headers={
                "Authorization": f"Bearer {SMALLEST_AI_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "text": text,
                "voice_id": "emily",
                "sample_rate": 24000,
                "speed": 1.0,
                "add_wav_header": True,
            },
        )
        response.raise_for_status()
        return response.content

    async def _openai_tts(self, text: str) -> bytes:
        """Use OpenAI TTS as fallback."""
        response = await self.openai_client.audio.speech.create(
            model="tts-1",
            voice="nova",
            input=text,
            response_format="wav",
        )
        return response.content

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _placeholder_response(self, scene_context: str) -> str:
        """Generate a simple response when no API keys are configured."""
        if not scene_context or scene_context == "No objects detected in the scene.":
            return "The path ahead appears clear. I don't detect any obstacles right now."
        return f"Here is what I see: {scene_context} Please be careful as you navigate."

    @staticmethod
    def _generate_silence_wav(duration_seconds: float = 1.0, sample_rate: int = 24000) -> bytes:
        """Generate a silent WAV file as a fallback when no TTS is available."""
        num_samples = int(sample_rate * duration_seconds)
        data_size = num_samples * 2  # 16-bit samples

        header = bytearray()
        header.extend(b"RIFF")
        header.extend(struct.pack("<I", 36 + data_size))
        header.extend(b"WAVE")
        header.extend(b"fmt ")
        header.extend(struct.pack("<I", 16))  # chunk size
        header.extend(struct.pack("<H", 1))   # PCM
        header.extend(struct.pack("<H", 1))   # mono
        header.extend(struct.pack("<I", sample_rate))
        header.extend(struct.pack("<I", sample_rate * 2))  # byte rate
        header.extend(struct.pack("<H", 2))   # block align
        header.extend(struct.pack("<H", 16))  # bits per sample
        header.extend(b"data")
        header.extend(struct.pack("<I", data_size))
        header.extend(b"\x00" * data_size)

        return bytes(header)

    async def close(self):
        await self.http_client.aclose()

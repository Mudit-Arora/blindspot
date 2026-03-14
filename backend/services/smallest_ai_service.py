"""
AI service that integrates:
  - Speech-to-text  → Smallest.ai Pulse
  - LLM reasoning   → Groq (free, OpenAI-compatible)
  - Text-to-speech  → Smallest.ai Lightning

Set environment variables:
  SMALLEST_AI_API_KEY  — for Pulse STT + Lightning TTS
  GROQ_API_KEY         — for LLM reasoning (free at console.groq.com)
"""

import os
import logging
import struct

import httpx

logger = logging.getLogger("blindspot.ai_service")

SMALLEST_AI_API_KEY = os.getenv("SMALLEST_AI_API_KEY", "")
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")

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
        self.http_client = httpx.AsyncClient(timeout=30.0)

    # ------------------------------------------------------------------
    # Speech-to-Text  (Smallest.ai Pulse)
    # ------------------------------------------------------------------

    async def transcribe_audio(self, audio_bytes: bytes) -> str:
        """Transcribe WAV audio using Smallest.ai Pulse STT."""
        if not SMALLEST_AI_API_KEY:
            logger.warning("No SMALLEST_AI_API_KEY — returning placeholder transcription")
            return "what is around me?"

        response = await self.http_client.post(
            "https://api.smallest.ai/waves/v1/pulse/get_text",
            params={"language": "en"},
            headers={
                "Authorization": f"Bearer {SMALLEST_AI_API_KEY}",
                "Content-Type": "audio/wav",
            },
            content=audio_bytes,
        )
        if response.status_code != 200:
            logger.error(f"STT API error ({response.status_code}): {response.text}")
        response.raise_for_status()
        result = response.json()
        return result.get("transcription", "").strip()

    # ------------------------------------------------------------------
    # LLM Reasoning  (Groq — free, OpenAI-compatible)
    # ------------------------------------------------------------------

    async def generate_response(self, user_text: str, scene_context: str) -> str:
        """Generate a navigation-assistant response using Groq LLM."""
        if not GROQ_API_KEY:
            logger.warning("No GROQ_API_KEY — returning placeholder response")
            return self._placeholder_response(scene_context)

        user_message = f"Scene description:\n{scene_context}\n\nUser says: \"{user_text}\""

        response = await self.http_client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": "llama-3.3-70b-versatile",
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_message},
                ],
                "max_tokens": 300,
                "temperature": 0.7,
            },
        )
        if response.status_code != 200:
            logger.error(f"LLM API error ({response.status_code}): {response.text}")
        response.raise_for_status()
        data = response.json()
        return data["choices"][0]["message"]["content"].strip()

    # ------------------------------------------------------------------
    # Text-to-Speech  (Smallest.ai Lightning)
    # ------------------------------------------------------------------

    async def text_to_speech(self, text: str) -> bytes:
        """Convert text to speech audio (WAV) using Smallest.ai Lightning."""
        if not SMALLEST_AI_API_KEY:
            logger.warning("No SMALLEST_AI_API_KEY — returning silence")
            return self._generate_silence_wav(duration_seconds=1)

        try:
            return await self._smallest_ai_tts(text)
        except Exception as e:
            logger.error(f"Smallest.ai TTS failed: {e}")
            return self._generate_silence_wav(duration_seconds=1)

    async def _smallest_ai_tts(self, text: str) -> bytes:
        """Call Smallest.ai Lightning v2 TTS API."""
        response = await self.http_client.post(
                "https://api.smallest.ai/waves/v1/lightning-v3.1/get_speech",
            headers={
                "Authorization": f"Bearer {SMALLEST_AI_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "text": text,
                "voice_id": "magnus",
                "sample_rate": 24000,
                "speed": 1.0,
            },
        )
        if response.status_code != 200:
            logger.error(f"TTS API error ({response.status_code}): {response.text}")
        response.raise_for_status()
        return response.content

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _placeholder_response(self, scene_context: str) -> str:
        if not scene_context or scene_context == "No objects detected in the scene.":
            return "The path ahead appears clear. I don't detect any obstacles right now."
        return f"Here is what I see: {scene_context} Please be careful as you navigate."

    @staticmethod
    def _generate_silence_wav(duration_seconds: float = 1.0, sample_rate: int = 24000) -> bytes:
        num_samples = int(sample_rate * duration_seconds)
        data_size = num_samples * 2

        header = bytearray()
        header.extend(b"RIFF")
        header.extend(struct.pack("<I", 36 + data_size))
        header.extend(b"WAVE")
        header.extend(b"fmt ")
        header.extend(struct.pack("<I", 16))
        header.extend(struct.pack("<H", 1))
        header.extend(struct.pack("<H", 1))
        header.extend(struct.pack("<I", sample_rate))
        header.extend(struct.pack("<I", sample_rate * 2))
        header.extend(struct.pack("<H", 2))
        header.extend(struct.pack("<H", 16))
        header.extend(b"data")
        header.extend(struct.pack("<I", data_size))
        header.extend(b"\x00" * data_size)
        return bytes(header)

    async def close(self):
        await self.http_client.aclose()

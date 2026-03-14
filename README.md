# Blindspot

An accessibility-focused iOS app for blind and visually impaired users. Blindspot uses computer vision to analyze surroundings and a voice AI agent that describes what's happening and helps users navigate safely.

## Architecture

```
┌──────────────────┐         WebSocket / REST          ┌──────────────────┐
│                  │  ──── scene JSON + audio ────────► │                  │
│   iOS App        │                                    │  Python Backend  │
│   (Swift/SwiftUI)│  ◄──── response audio ──────────── │  (FastAPI)       │
│                  │                                    │                  │
└──────────────────┘                                    └──────────────────┘
      │                                                        │
      ├── AVFoundation (camera)                                ├── Whisper STT
      ├── Vision framework (object detection)                  ├── GPT-4o (reasoning)
      ├── AVAudioEngine (mic recording)                        └── Smallest.ai / OpenAI TTS
      └── AVAudioPlayer (playback)
```

## Example Interaction

**User holds Talk button and says:** "What's going on around me?"

**Blindspot responds (spoken):** "There is construction about 8 feet ahead. A pothole is slightly to your left. You should move slightly to the right."

---

## iOS App

### Requirements

- Xcode 26+
- iOS 18.0+ deployment target
- Physical iPhone (camera + mic required)

### Project Structure

```
blindspot/
├── blindspotApp.swift          # App entry point
├── Models/
│   ├── DetectedObject.swift    # Detected object with position + distance
│   └── SceneDescription.swift  # Scene summary for backend
├── Views/
│   ├── MainView.swift          # Root view composing camera + voice UI
│   ├── CameraView.swift        # Camera preview + detection overlays
│   └── VoiceInteractionView.swift  # Talk button + status display
├── ViewModels/
│   ├── CameraViewModel.swift        # Camera + Vision pipeline
│   └── VoiceAssistantViewModel.swift # Voice interaction lifecycle
├── Services/
│   ├── CameraService.swift          # AVCaptureSession management
│   ├── VisionDetectionService.swift # Apple Vision object detection
│   ├── AudioRecordingService.swift  # Mic recording → PCM/WAV
│   ├── BackendAPIService.swift      # WebSocket + REST communication
│   └── AudioPlaybackService.swift   # Audio response playback
└── Utilities/
    ├── Configuration.swift          # Backend URL + audio format config
    └── AccessibilityManager.swift   # VoiceOver + haptics + spoken alerts
```

### Running the iOS App

1. Open `blindspot.xcodeproj` in Xcode
2. Select a physical device (camera/mic won't work in Simulator)
3. Update `Configuration.swift` with your backend server IP if not running locally:
   ```swift
   static let backendHost = "YOUR_SERVER_IP"
   ```
4. Build and run (Cmd+R)
5. Grant camera and microphone permissions when prompted

### Key Features

- **Real-time object detection** — Uses Apple Vision to detect people, animals, and classify scenes
- **Spatial awareness** — Objects are labeled as left/center/right with estimated distances
- **Proximity alerts** — Haptic feedback + spoken warnings when hazards are close
- **Hold-to-talk** — Large, accessible talk button for voice interaction
- **Full VoiceOver support** — Every UI element has accessibility labels and hints

---

## Python Backend

### Requirements

- Python 3.11+
- API keys (see below)

### Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure API keys
cp .env.example .env
# Edit .env with your API keys
```

### API Keys

| Key | Required | Used For |
|-----|----------|----------|
| `OPENAI_API_KEY` | Yes | Whisper STT, GPT-4o reasoning, fallback TTS |
| `SMALLEST_AI_API_KEY` | Optional | Smallest.ai Lightning TTS (faster, lower latency) |

### Running the Backend

```bash
cd backend
source venv/bin/activate
python main.py
```

The server starts at `http://0.0.0.0:8000`.

### API Endpoints

#### Health Check

```bash
curl http://localhost:8000/health
```

Response:
```json
{"status": "ok", "service": "blindspot-backend"}
```

#### WebSocket — `/ws/speech-agent`

Low-latency streaming endpoint. Protocol:

```
Client connects → ws://host:8000/ws/speech-agent

1. Client sends:  {"type": "session_start", "scene": "{\"objects\": [...]}"}
   Server sends:  {"type": "session_ready"}

2. Client sends:  <binary WAV audio data>
   Client sends:  {"type": "audio_end"}

3. Server sends:  {"type": "processing"}
   Server sends:  {"type": "transcript", "user_text": "...", "assistant_text": "..."}
   Server sends:  <binary WAV response audio>
   Server sends:  {"type": "response_end"}
```

#### REST — `POST /api/speech-agent`

Multipart form fallback endpoint:

```bash
curl -X POST http://localhost:8000/api/speech-agent \
  -F "audio=@recording.wav" \
  -F 'scene={"objects": [{"label": "pothole", "position": "center", "distance": "5 feet"}]}'
```

Returns: WAV audio response with headers `X-User-Text` and `X-Assistant-Text`.

### Backend Structure

```
backend/
├── main.py                          # FastAPI app + CORS + lifespan
├── requirements.txt
├── .env.example
├── routes/
│   └── speech_agent.py              # WebSocket + REST endpoints
└── services/
    ├── smallest_ai_service.py       # STT + LLM + TTS integration
    ├── audio_processing.py          # WAV/PCM utilities
    └── scene_context_builder.py     # Scene JSON → text context
```

### Processing Pipeline

```
iOS mic audio (WAV)
  → WebSocket
  → Whisper STT (audio → text)
  → GPT-4o (user question + scene context → response text)
  → Smallest.ai Lightning TTS (text → speech audio)
  → WebSocket
  → iOS audio playback
```

---

## WebSocket Streaming Example

### Python Client

```python
import asyncio
import websockets
import json

async def test_speech_agent():
    uri = "ws://localhost:8000/ws/speech-agent"
    async with websockets.connect(uri) as ws:
        # 1. Send scene context
        scene = {
            "objects": [
                {"label": "pothole", "position": "center", "distance": "5 feet"},
                {"label": "construction cone", "position": "right", "distance": "8 feet"},
                {"label": "person", "position": "left", "distance": "10 feet"}
            ]
        }
        await ws.send(json.dumps({
            "type": "session_start",
            "scene": json.dumps(scene)
        }))
        response = await ws.recv()
        print(f"Server: {response}")

        # 2. Send audio (WAV file)
        with open("test_recording.wav", "rb") as f:
            audio_data = f.read()
        await ws.send(audio_data)
        await ws.send(json.dumps({"type": "audio_end"}))

        # 3. Receive responses
        while True:
            msg = await ws.recv()
            if isinstance(msg, bytes):
                print(f"Received audio: {len(msg)} bytes")
                with open("response.wav", "wb") as f:
                    f.write(msg)
            else:
                data = json.loads(msg)
                print(f"Server: {data}")
                if data.get("type") == "response_end":
                    break

asyncio.run(test_speech_agent())
```

---

## Smallest.ai Integration

The backend uses Smallest.ai's Lightning TTS model for low-latency speech synthesis.

### API Call

```python
POST https://waves-api.smallest.ai/api/v1/lightning/get_speech
Headers:
  Authorization: Bearer <SMALLEST_AI_API_KEY>
  Content-Type: application/json
Body:
  {
    "text": "There is a pothole ahead. Move to the right.",
    "voice_id": "emily",
    "sample_rate": 24000,
    "speed": 1.0,
    "add_wav_header": true
  }
Response: WAV audio bytes
```

If `SMALLEST_AI_API_KEY` is not set, the backend automatically falls back to OpenAI's TTS API.

---

## Accessibility

The app is designed for users who cannot see the screen:

- **VoiceOver**: Every button, label, and status element has accessibility labels and hints
- **Large touch targets**: The Talk button is 120pt diameter
- **Haptic feedback**: Triple-pulse vibration for danger, single pulse for proximity
- **Spoken alerts**: AVSpeechSynthesizer warns about nearby hazards even without VoiceOver
- **Audio prompts**: Welcome announcement on launch; status changes are announced
- **High contrast**: White text on dark gradient background for low-vision users

---

## Development Notes

- The iOS app uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-discovers new Swift files
- Vision detection runs throttled at 0.5s intervals to avoid overloading the GPU
- Distance estimation uses bounding-box area heuristics (larger box = closer object)
- The WebSocket connection is established per voice interaction and closed after playback
- For production, deploy the backend behind HTTPS with a proper domain

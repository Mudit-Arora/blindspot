# Blindspot

An accessibility-focused iOS app for blind and visually impaired users. Blindspot uses on-device computer vision to analyze surroundings and a voice AI agent that describes what's happening and helps users navigate safely.

## Demo Video

Checkout the demo:
https://drive.google.com/file/d/1WxWD7MsBLvR-CUFj1B1CwV7Y2t5Os4h_/view?usp=drive_link

## Architecture

```
┌──────────────────┐        REST (multipart/form-data)        ┌──────────────────┐
│                  │  ──── scene JSON + WAV audio ──────────► │                  │
│   iOS App        │                                          │  Python Backend  │
│   (Swift/SwiftUI)│  ◄──── JSON (transcripts + base64 WAV)── │  (FastAPI)       │
│                  │                                          │                  │
└──────────────────┘                                          └──────────────────┘
      │                                                              │
      ├── AVFoundation (camera, mic, playback)                       ├── Smallest.ai Pulse (STT)
      ├── Vision framework (object detection)                        ├── Groq / Llama 3.3 70B (LLM)
      └── Observation (reactive state)                               └── Smallest.ai Lightning v3.1 (TTS)
```

## Example Interaction

**User taps Talk, asks:** "What's going on around me?"

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
│   └── VoiceAssistantViewModel.swift # Record → send → play lifecycle
├── Services/
│   ├── CameraService.swift          # AVCaptureSession management
│   ├── VisionDetectionService.swift # Apple Vision object detection
│   ├── AudioRecordingService.swift  # Mic recording → PCM/WAV
│   ├── BackendAPIService.swift      # REST communication with backend
│   └── AudioPlaybackService.swift   # Audio response playback
└── Utilities/
    ├── Configuration.swift          # Backend URL + audio format config
    └── AccessibilityManager.swift   # VoiceOver + haptics + spoken alerts
```

### Running the iOS App

1. Open `blindspot.xcodeproj` in Xcode
2. Select a physical device (camera/mic won't work in Simulator)
3. Update `Configuration.swift` with your backend server IP:
   ```swift
   static let backendHost = "YOUR_SERVER_IP"
   ```
4. Build and run (Cmd+R)
5. Grant camera and microphone permissions when prompted

### Key Features

- **Real-time object detection** — Apple Vision detects people, animals, vehicles, stairs, construction, and more
- **Spatial awareness** — Objects are labeled as left/center/right with estimated distances
- **Proximity alerts** — Haptic feedback + spoken warnings when hazards are close
- **Tap-to-talk** — Tap once to start recording, tap again to send; 120pt accessible button
- **Transcript bubbles** — User and assistant messages shown as chat-style bubbles
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
| `SMALLEST_AI_API_KEY` | Yes | Pulse STT + Lightning v3.1 TTS |
| `GROQ_API_KEY` | Yes | LLM reasoning (Llama 3.3 70B via Groq) |

Both keys are free to obtain:
- Smallest.ai — [smallest.ai](https://smallest.ai)
- Groq — [console.groq.com](https://console.groq.com)

If either key is missing, the backend returns placeholder responses instead of erroring out.

### Running the Backend

```bash
cd backend
source venv/bin/activate
python main.py
```

The server starts at `http://0.0.0.0:8000` with hot-reload enabled.

### API Endpoints

#### Health Check

```
GET /health
```

```json
{"status": "ok", "service": "blindspot-backend"}
```

#### Speech Agent

```
POST /api/speech-agent
Content-Type: multipart/form-data
```

| Field | Type | Description |
|-------|------|-------------|
| `audio` | file (WAV) | User's recorded audio |
| `scene` | string (JSON) | Scene description from Vision detection |

Response:

```json
{
  "user_text": "What is around me?",
  "assistant_text": "There is a pothole directly ahead, about 5 feet away...",
  "audio_base64": "<base64-encoded WAV audio>"
}
```

Example with curl:

```bash
curl -X POST http://localhost:8000/api/speech-agent \
  -F "audio=@recording.wav" \
  -F 'scene={"objects": [{"label": "pothole", "position": "center", "distance": "5 feet"}]}'
```

### Backend Structure

```
backend/
├── main.py                          # FastAPI app + CORS + lifespan
├── requirements.txt
├── .env.example
├── routes/
│   └── speech_agent.py              # REST endpoint
└── services/
    ├── smallest_ai_service.py       # STT + LLM + TTS integration
    ├── audio_processing.py          # WAV/PCM utilities
    └── scene_context_builder.py     # Scene JSON → text context for LLM
```

### Processing Pipeline

```
iOS mic audio (16kHz WAV)
  → REST POST /api/speech-agent
  → Smallest.ai Pulse STT (audio → text)
  → Groq Llama 3.3 70B (user question + scene context → response text)
  → Smallest.ai Lightning v3.1 TTS (text → 24kHz WAV audio)
  → JSON response (transcripts + base64 audio)
  → iOS decodes base64 → AVAudioPlayer playback
```

---

## Scene Context

The backend converts the structured scene JSON from the iOS app into a human-readable context string for the LLM. Hazards are prioritized and listed first.

**Input:**
```json
{
  "objects": [
    {"label": "pothole", "position": "center", "distance": "5 feet"},
    {"label": "person", "position": "left", "distance": "10 feet"}
  ]
}
```

**Context sent to LLM:**
```
HAZARDS DETECTED:
  - pothole on the center, approximately 5 feet away

Other objects:
  - person on the left, approximately 10 feet away
```

Recognized hazard labels include: pothole, construction, stairs, vehicle, car, truck, bus, bicycle, motorcycle, fire hydrant, pole, barrier, curb, and more.

---

## Accessibility

The app is designed for users who cannot see the screen:

- **VoiceOver** — Every button, label, and status element has accessibility labels and hints
- **Large touch targets** — The Talk button is 120pt diameter
- **Haptic feedback** — Triple-pulse vibration for danger, single pulse for proximity
- **Spoken alerts** — AVSpeechSynthesizer warns about nearby hazards even without VoiceOver
- **Audio prompts** — Welcome announcement on launch; status changes are announced
- **High contrast** — White text on dark gradient background for low-vision users
- **Transcript bubbles** — Chat-style display of user and assistant messages

---

## Development Notes

- The iOS app uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-discovers new Swift files
- Vision detection runs throttled at 0.5s intervals to avoid overloading the GPU
- Distance estimation uses bounding-box area heuristics (larger box = closer object)
- The `@Observable` macro provides reactive UI updates without manual publishers
- Backend uses `httpx.AsyncClient` for non-blocking API calls to all external services
- If API keys are missing, the backend returns placeholder responses and silent WAV audio
- For production, deploy the backend behind HTTPS with a proper domain

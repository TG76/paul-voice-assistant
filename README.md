# Paul - Voice Assistant for OpenClaw

Paul is a native macOS voice assistant that connects to [OpenClaw](https://openclaw.ai) via its Gateway WebSocket API. It listens for the wake word "Paul", records speech, transcribes it with OpenAI Whisper, sends the text to OpenClaw for AI-powered responses, and speaks the answer back using OpenAI TTS.

## Features

- **Wake Word Detection** - Always-on listening for "Paul" using Apple Speech Recognition
- **Live Speech-to-Text** - Apple Speech Recognition (on-device, German) with real-time transcription
- **AI Responses** - Full OpenClaw integration via Gateway WebSocket (protocol v3)
- **Text-to-Speech** - OpenAI TTS with configurable voice and speed
- **Animated Avatar** - Minimalist white-on-black face with state-dependent expressions (listening, thinking, speaking)
- **Overlay UI** - Semi-transparent fullscreen overlay during interaction, mini avatar in corner during follow-up
- **Silence Detection** - Automatic end-of-speech detection (VAD)
- **Follow-up Conversations** - After an answer, Paul listens briefly for follow-up questions
- **Display Control** - Wakes display on activation, prevents sleep during interaction
- **Display Wake Recovery** - Auto-restarts wake word detection after display sleep/wake
- **Global Escape** - ESC key aborts interaction even without window focus
- **Configurable Follow-up** - Toggle follow-up listening in Settings

## Architecture

```
  "hey paul"                    Wake Word
  ──────> WakeWordDetector ────> handleWakeWord()
          (Apple Speech)              |
                                      v
                              LiveTranscriber
                            (Apple Speech, de-DE)
                                      |
                                      v
                              OpenClawClient ───> OpenClaw Gateway
                            (WebSocket, wss://)      (wss://127.0.0.1:18789)
                                      |
                                      v
                                TTSService
                              (OpenAI TTS API)
                                      |
                                      v
                                AudioPlayer
                              (AVAudioPlayer)
```

### State Machine

```
sleep ──> waking ──> listening ──> thinking ──> speaking ──> listening (follow-up)
  ^                                                              |
  └──────────────────── timeout / silence ───────────────────────┘
```

| State | UI | Behavior |
|---|---|---|
| `sleep` | No overlay | Wake word detector active |
| `waking` | Full overlay, sleepy face | Plays greeting ("Ja?", "Hey!", ...) |
| `listening` | Full overlay / mini corner | Recording with waveform |
| `thinking` | Full overlay, eyes wandering | Whisper STT + OpenClaw processing |
| `speaking` | Full overlay, lip-sync | TTS playback with subtitles |

## Project Structure

```
PaulApp/
├── Package.swift              # Swift Package definition (macOS 14+)
└── Paul/
    ├── PaulApp.swift          # App entry point, AppDelegate, main pipeline
    ├── API/
    │   ├── OpenClawClient.swift   # WebSocket client for OpenClaw Gateway
    │   ├── TTSService.swift       # OpenAI Text-to-Speech
    │   └── WhisperService.swift   # OpenAI Speech-to-Text
    ├── Audio/
    │   ├── AudioPlayer.swift      # AVAudioPlayer wrapper with metering
    │   ├── AudioRecorder.swift    # AVAudioEngine recording (legacy)
    │   ├── LiveTranscriber.swift  # Real-time Apple Speech Recognition
    │   └── SilenceDetector.swift  # RMS-based voice activity detection
    ├── Config/
    │   ├── Logger.swift           # File-based logger (~/Paul/paul.log)
    │   └── Settings.swift         # All configuration constants
    ├── Display/
    │   └── DisplayController.swift # IOKit display wake/sleep prevention
    ├── UI/
    │   ├── AvatarView.swift       # Animated face (eyes, mouth, expressions)
    │   ├── ContentView.swift      # Image/web content display
    │   ├── OverlayWindow.swift    # Full + mini overlay windows
    │   ├── StateManager.swift     # Central state machine
    │   └── WaveformView.swift     # Audio level visualization
    └── WakeWord/
        └── WakeWordDetector.swift # Apple Speech-based wake word
```

## Requirements

- macOS 14+ (Sonoma)
- Swift 5.10+
- OpenAI API key (for TTS)
- OpenClaw Gateway running locally (port 18789)
- Microphone permission
- Speech Recognition permission (Dictation must be enabled in System Settings)

## Configuration

Paul reads configuration from environment variables with fallback to UserDefaults (settable via the in-app Settings window).

| Variable | Description | Default |
|---|---|---|
| `OPENAI_API_KEY` | OpenAI API key for Whisper and TTS | - |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw Gateway authentication token | - |
| `OPENCLAW_GATEWAY_URL` | Gateway WebSocket URL | `wss://127.0.0.1:18789` |

### Tunable Parameters (in `Settings.swift`)

| Parameter | Value | Description |
|---|---|---|
| `ttsVoice` | `onyx` | TTS voice (alloy, echo, fable, onyx, nova, shimmer) |
| `ttsSpeed` | `1.2` | Speech speed (0.25 - 4.0) |
| `silenceThreshold` | `0.01` | RMS threshold for silence detection |
| `silenceDuration` | `4.0s` | Seconds of silence before stopping recording |
| `followUpTimeout` | `5.0s` | Seconds to wait for follow-up question |

## Building

```bash
# Build for local architecture
swift build -c release

# Cross-compile for Intel Mac
swift build -c release --arch x86_64

# Cross-compile for Apple Silicon
swift build -c release --arch arm64
```

The binary will be at `.build/<arch>-apple-macosx/release/Paul`.

## Installation

### 1. Build the app

```bash
swift build -c release --arch x86_64  # or arm64
```

### 2. Copy binary to target Mac

```bash
scp .build/x86_64-apple-macosx/release/Paul user@target:/usr/local/bin/Paul
```

### 3. Create a LaunchAgent for auto-start

Create `~/Library/LaunchAgents/com.paul.voiceassistant.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.paul.voiceassistant</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/Paul</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENAI_API_KEY</key>
        <string>sk-...</string>
        <key>OPENCLAW_GATEWAY_TOKEN</key>
        <string>your-gateway-token</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.paul.voiceassistant.plist
launchctl start com.paul.voiceassistant
```

### 4. Grant permissions

On first launch, macOS will prompt for:
- **Microphone access** - Required for recording
- **Speech Recognition** - Required for wake word detection

Dictation must be enabled in **System Settings > Keyboard > Dictation**.

### 5. Optional: Desktop launcher

Create an app bundle at `/Applications/Paul.app` for Dock/Spotlight access. The app bundle just needs a shell script that starts the LaunchAgent.

## OpenClaw Integration

Paul connects to the OpenClaw Gateway using the WebSocket protocol (v3). No channel plugin is required - it connects as an operator client directly.

### Connection Flow

1. Paul opens a WebSocket to `wss://127.0.0.1:18789`
2. Gateway sends `connect.challenge` event
3. Paul responds with a `connect` request including auth token
4. Gateway responds with `hello-ok`
5. Paul sends messages via `chat.send` to session `agent:main:main`
6. Responses arrive as `chat` events with `state: delta/final`

### Gateway Setup

Ensure OpenClaw Gateway is running:

```bash
openclaw gateway start
openclaw status
```

Get the gateway token:

```bash
cat ~/.openclaw/openclaw.json | grep token
```

### Protocol Details

Paul authenticates as:
```json
{
  "client": {
    "id": "gateway-client",
    "displayName": "Paul Voice",
    "version": "1.0.0",
    "platform": "macos",
    "mode": "backend"
  },
  "role": "operator",
  "scopes": ["chat", "operator", "operator.read", "operator.write"]
}
```

Messages are sent to the default session (`agent:main:main`). The AI agent receives the transcribed speech as a regular chat message and responds accordingly.

## Logs

Paul writes logs to `~/Paul/paul.log`:

```bash
tail -f ~/Paul/paul.log
```

## Troubleshooting

| Problem | Solution |
|---|---|
| Paul doesn't wake up | Check `paul.log` for WakeWord errors. Ensure Dictation is enabled. |
| "Speech-Erkennung nicht autorisiert" | Enable Dictation in System Settings > Keyboard |
| No audio response | Check `OPENAI_API_KEY` is set correctly |
| "Nicht mit OpenClaw verbunden" | Ensure Gateway is running (`openclaw status`) and token is correct |
| Whisper hallucinations ("Untertitel...") | Normal for silence - these are filtered automatically |
| Timeout errors | OpenClaw agent may be slow. Timeout is 120s. |

## License

MIT

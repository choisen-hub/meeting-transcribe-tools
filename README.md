# meeting-transcribe-tools

Small macOS helpers for recording a call (Zoom or any other app that plays audio through the system output) and transcribing it locally with Whisper. The main tool is `meet`, a zsh script that captures both sides of a conversation by routing system audio through a temporary multi-output device, mixes it with the microphone using ffmpeg, and runs whisper.cpp when the recording stops. A CoreAudio helper written in Swift creates and removes that multi-output device. A separate Python script transcribes videos stored on Google Drive with the `openai-whisper` package. Nothing leaves the machine: all transcription runs locally.

## Features

- `meet start [name]`: begin recording. The current default output (headphones, speakers) keeps playing, and the same audio is mirrored into BlackHole so that the other party's voice can be captured together with your own microphone.
- `meet stop`: end the recording, restore the original output device, convert the file to 16 kHz mono, and transcribe it with whisper.cpp (`ggml-large-v3-turbo`, automatic language detection). Produces `recording.m4a`, `transcript.txt`, `transcript.srt` and a Markdown `note.md` with duration and the full transcript.
- `meet status`: show whether a recording is in progress and whether the ffmpeg process is still alive.
- `audio-multiout`: a command-line CoreAudio helper (Swift) with five subcommands: `default-output`, `default-input`, `create <mainUID> <blackholeUID>`, `set-default <uid>`, `destroy`.
- `transcribe.py`: download one or more Google Drive video/audio links with `gdown`, extract audio with ffmpeg, transcribe with the `whisper` Python package, and save a timestamped `.txt` per file.
- `tile`: an unrelated convenience script (JXA, `osascript -l JavaScript`) that detaches Terminal tabs into windows and arranges them in an even grid, or merges them back. It lives in the same folder and is included for completeness.

## How it works

### Recording (`meet`)

1. `meet start` asks `audio-multiout` for the current default output and input devices, then creates a stacked aggregate device named `MeetRec` (UID `com.meet.multiout`) whose sub-devices are the original output and `BlackHole 2ch`. Drift compensation is enabled on the BlackHole sub-device.
2. The aggregate device is set as the system default output, so every application plays through both the real output and BlackHole.
3. ffmpeg records two avfoundation inputs, BlackHole (the remote side) and the microphone (your side), downmixes each to mono, mixes them with `amix`, and writes `recording.m4a` (AAC, 96 kbps, 44.1 kHz mono). The ffmpeg process runs detached with `nohup`; its pid and the original output device are written to a session file under `~/.local/state/meet/`.
4. `meet stop` sends SIGINT to ffmpeg so the file is finalised, restores the previous default output, destroys the aggregate device, converts the recording to 16 kHz PCM, runs `whisper-cli`, and assembles `note.md`.

The device indices that ffmpeg needs are looked up at run time by parsing `ffmpeg -f avfoundation -list_devices true` and matching the device names, so the script does not hardcode index numbers.

### Transcribing Google Drive files (`transcribe.py`)

For each URL the script extracts the Drive file id, downloads it into a temporary directory with `gdown`, extracts 16 kHz mono audio with ffmpeg (falls back to the original file if extraction fails), runs `whisper.load_model(name).transcribe(...)`, and writes `<title>.txt` with `[HH:MM:SS]` prefixes per segment.

## Requirements

- macOS (CoreAudio, avfoundation). Tested on an Apple Silicon Mac; Intel should work but is untested.
- Homebrew packages: `ffmpeg`, `whisper-cpp` (provides `whisper-cli`), and the `blackhole-2ch` cask.
- A whisper.cpp model file. The script expects `ggml-large-v3-turbo.bin` under `~/.local/share/whisper/`.
- Xcode command line tools (`swiftc`) to build `audio-multiout`.
- Microphone permission for the terminal application that runs `meet` (System Settings > Privacy & Security > Microphone). The first run fails with an ffmpeg error until permission is granted.
- For `transcribe.py` only: Python 3 with `gdown` and `openai-whisper` installed, plus ffmpeg.
- For `tile` only: Terminal.app and Accessibility permission for the script runner (System Events is used to click menu items and move windows).

## Installation and running

```bash
# 1. Dependencies
brew install ffmpeg whisper-cpp
brew install --cask blackhole-2ch

# 2. Whisper model (about 1.6 GB)
mkdir -p ~/.local/share/whisper
curl -L -o ~/.local/share/whisper/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin

# 3. Clone into ~/scripts (the meet script looks for its helper at ~/scripts/.bin/audio-multiout)
git clone <repo-url> ~/scripts
cd ~/scripts

# 4. Build the CoreAudio helper
mkdir -p .bin
swiftc -O -framework CoreAudio -framework Foundation -o .bin/audio-multiout audio-multiout.swift

# 5. Put the scripts on PATH (or call them with a full path)
chmod +x meet tile
export PATH="$HOME/scripts:$PATH"
```

Record a meeting:

```bash
meet start "weekly sync"
# ... talk ...
meet stop
meet status
```

Transcribe Google Drive videos (optional tool):

```bash
pip3 install gdown openai-whisper
python3 transcribe.py "https://drive.google.com/file/d/<id>/view" --model small --language ko --output ./transcripts
```

Arrange Terminal windows (optional tool):

```bash
tile        # auto grid
tile 2      # two columns
tile merge  # merge back into one tabbed window
```

## Configuration

There is no config file. Settings are constants at the top of `meet`:

| Variable | Default | Meaning |
|---|---|---|
| `HELPER` | `$HOME/scripts/.bin/audio-multiout` | Path to the compiled Swift helper |
| `STATE_DIR` | `$HOME/.local/state/meet` | Where the active-session file is kept |
| `MEETINGS_DIR` | `$HOME/Desktop/knowledge-hub/meetings` | Output root; each recording gets `YYYY-MM-DD_HHMM_<name>/` |
| `MODEL` | `$HOME/.local/share/whisper/ggml-large-v3-turbo.bin` | whisper.cpp model |
| `BH_UID` | `BlackHole2ch_UID` | Device UID of BlackHole 2ch |
| `MULTI_UID` | `com.meet.multiout` | UID of the temporary aggregate device |

Edit `MEETINGS_DIR` to point at any folder you like. The whisper thread count (`-t 8`) and language mode (`-l auto`) are set in the `whisper-cli` call inside `cmd_stop`.

`transcribe.py` takes its settings from the command line: `--model` (tiny, base, small, medium, large; default small), `--language` (default `ko`), `--output` (default `~/Desktop/대화록`).

## Project structure

```
.
├── meet                  # zsh: start / stop / status
├── audio-multiout.swift  # CoreAudio aggregate-device helper (source)
├── .bin/audio-multiout   # compiled helper (build it yourself if missing)
├── transcribe.py         # Google Drive link -> local whisper transcript
├── tile                  # JXA Terminal window tiler (unrelated utility)
├── LICENSE
└── README.md
```

Output layout produced by `meet stop`:

```
<MEETINGS_DIR>/2026-10-06_1430_weekly_sync/
├── recording.m4a
├── transcript.txt
├── transcript.srt
├── note.md
└── .ffmpeg.log
```

## Usage examples

Check devices before a first run:

```bash
~/scripts/.bin/audio-multiout default-output   # prints "UID<TAB>Name"
~/scripts/.bin/audio-multiout default-input
ffmpeg -f avfoundation -list_devices true -i ""
```

Re-run transcription by hand if the automatic step failed:

```bash
whisper-cli -m ~/.local/share/whisper/ggml-large-v3-turbo.bin \
  -f <dir>/recording.m4a -l auto -t 8 -otxt -osrt -of <dir>/transcript
```

Recover audio routing if `meet stop` could not restore it (for example after a crash):

```bash
~/scripts/.bin/audio-multiout destroy
# then pick your usual output in System Settings > Sound
```

## Data sources, licensing and attribution

- whisper.cpp and its ggml model conversions: MIT (model weights are OpenAI Whisper weights, MIT).
- BlackHole virtual audio driver: GPL-3.0, installed separately via Homebrew cask.
- ffmpeg: LGPL/GPL depending on build, installed separately.
- `gdown` and `openai-whisper` Python packages: MIT.
- No audio or transcripts are included in this repository.

## Known limitations

- macOS only. The aggregate device API, avfoundation capture and the JXA tiler have no equivalents in the script for other platforms.
- The helper path, state dir and output dir are hardcoded; the repository must be cloned to `~/scripts` or the constants edited.
- If the default output device changes mid-call (for example headphones disconnect), the aggregate device keeps pointing at the old device and audio may stop; run `meet stop` and start again.
- Only one recording at a time; `meet start` refuses to run while a session file exists.
- Transcription runs after the call ends, not live, and large-v3-turbo on CPU/Metal can take several minutes for a one-hour call.
- Whisper occasionally hallucinates text during silence or music; the script does not filter those segments.
- `transcribe.py` uses the Python `whisper` package, not whisper.cpp, and therefore has a different model set and speed profile than `meet`.
- `tile` depends on Terminal menu item names in English ("Move Tab to New Window", "Merge All Windows") and on Accessibility permission.

## License

MIT. See `LICENSE`.

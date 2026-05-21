# Gaze Trigger PoC

Detects when you're looking at an OAK-D Lite camera and emits a trigger event
after sustained gaze. Proof of concept for hands-free dictation activation.

## Setup

```bash
# Install uv if needed
brew install uv

# Run (uv handles the venv and deps automatically)
uv run main.py

# With camera preview window (useful for tuning thresholds)
uv run --extra preview main.py --preview

# Custom thresholds
uv run main.py --threshold 20 --dwell 0.5 --cooldown 3
```

## Output

JSON lines on stdout:

```jsonl
{"event": "starting", "threshold": 15.0, "dwell_time": 1.0}
{"event": "running", "camera": "OAK-D-LITE"}
{"event": "looking", "yaw": 2.3, "pitch": -1.1, "roll": 0.5}
{"event": "dwell_progress", "progress": 0.5, "yaw": 2.1, "pitch": -0.8}
{"event": "trigger", "yaw": 1.9, "pitch": -1.0, "dwell_frames": 20}
{"event": "armed"}
{"event": "look_away", "was_at_frame": 8}
{"event": "stopped"}
```

## Args

| Flag | Default | Description |
|------|---------|-------------|
| `--threshold` | 15.0 | Max yaw/pitch degrees to count as "looking" |
| `--dwell` | 1.0 | Seconds of sustained gaze before trigger fires |
| `--cooldown` | 2.0 | Seconds after trigger before re-arming |
| `--preview` | off | Show OpenCV camera window with overlay |

## How it works

Two neural networks run on the OAK-D Lite's Myriad X chip:
1. **YuNet** face detection (640x480)
2. **Head pose estimation** (60x60 crop of detected face) → yaw, pitch, roll

If both yaw and pitch are within `--threshold` degrees for `--dwell` seconds,
a trigger event fires. After triggering, gaze is ignored for `--cooldown` seconds.

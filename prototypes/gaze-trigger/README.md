# Gaze Trigger PoC

Detects when you're looking at an OAK-D Lite camera and emits a trigger event
after sustained gaze. Proof of concept for hands-free dictation activation.

## Setup

```bash
# Plug in the OAK-D Lite via USB-C, then:
uv run main.py --preview

# Custom dwell time (default 1s)
uv run main.py --dwell 0.5 --preview
```

If the device crashed on a previous run, unplug and replug the USB-C cable.

## How it works

1. OAK-D Lite streams 640x480 BGR frames at 20fps via DepthAI
2. OpenCV Haar cascade detects frontal faces on each frame (host-side)
3. A sustained face detection for `--dwell` seconds triggers an event
4. After triggering, gaze is ignored for `--cooldown` seconds

The Haar cascade only detects frontal faces, so turning your head away
naturally stops detection. At desk distance with a fixed camera, this is
a reliable proxy for "looking at the camera."

## Output

JSON lines on stdout:

```jsonl
{"event": "starting", "dwell_time": 1.0}
{"event": "device_found", "camera": "OAK-D-LITE"}
{"event": "running"}
{"event": "looking", "face_x": 210, "face_y": 140, "face_w": 180, "face_h": 180}
{"event": "dwell_progress", "progress": 0.5}
{"event": "trigger", "dwell_frames": 20}
{"event": "armed"}
{"event": "look_away", "was_at_frame": 8}
{"event": "stopped"}
```

## Args

| Flag | Default | Description |
|------|---------|-------------|
| `--dwell` | 1.0 | Seconds of sustained face detection before trigger fires |
| `--cooldown` | 2.0 | Seconds after trigger before re-arming |
| `--preview` | off | Show camera window with face rectangle and progress bar |

## Future improvements

- Add head pose estimation (MediaPipe or on-device) for more precise gaze detection
- Move face detection on-device (Myriad X) to free host CPU
- Add depth filtering to ignore faces beyond desk distance

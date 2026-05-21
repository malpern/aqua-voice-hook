# OAK-D Lite: Gaze-Triggered Dictation

*Research date: 2026-05-20*

## Goal

Use the OAK-D Lite Fixed Focus depth camera to detect when the user is looking at it, and trigger Aqua Voice dictation mode -- enabling fully hands-free voice input.

## Hardware: OAK-D Lite Fixed Focus

| Spec | Value |
|------|-------|
| Processor | Intel Myriad X (4 TOPS, 1.4 TOPS AI) |
| RGB Camera | IMX214, 13MP, 4K/30fps or 1080p/60fps |
| RGB FOV | 69 deg horizontal, 54 deg vertical |
| Stereo Pair | OV7251 x2, 640x480, monochrome, global shutter |
| Depth Range | ~20cm (extended) to 12m |
| Depth Accuracy | <2% error under 4m |
| IMU | BMI270 6-axis |
| Connection | USB-C (USB 3.2 Gen1, 5 Gbps) |
| Power | Bus-powered, 2.5-5W |
| Fixed Focus | Lens locked, consistent focus at 50cm+ |

## Approach: Head Pose Estimation

### Recommended: 2-stage on-device pipeline

Two neural models running entirely on the Myriad X chip:

1. **face-detection-retail-0004** (MobileNet SSD, 300x300 input)
   - Detects face bounding boxes
   - Runs at 30+ FPS on Myriad X

2. **head-pose-estimation-adas-0001** (60x60 input)
   - Outputs yaw, pitch, roll in degrees
   - 638 inferences/sec on Myriad X
   - Mean error ~5 degrees

### "Looking at camera" logic

```python
LOOKING_THRESHOLD_YAW = 15    # degrees
LOOKING_THRESHOLD_PITCH = 15  # degrees
DWELL_FRAMES = 10             # ~0.5s at 20fps

if abs(yaw) < LOOKING_THRESHOLD_YAW and abs(pitch) < LOOKING_THRESHOLD_PITCH:
    consecutive_looking_frames += 1
else:
    consecutive_looking_frames = 0

if consecutive_looking_frames >= DWELL_FRAMES:
    trigger_dictation()
```

### Performance

| Metric | Value |
|--------|-------|
| Pipeline FPS | 20-30 FPS |
| End-to-end latency | 50-100ms per frame |
| Time to trigger (with dwell) | ~500ms (10 frames at 20fps) |
| CPU usage on Mac | Minimal (inference runs on Myriad X) |

## Alternative Approaches

### Full gaze estimation (4-model pipeline)

More accurate -- catches "head straight but eyes averted" cases:

1. face-detection-retail-0004
2. head-pose-estimation-adas-0001
3. landmarks-regression-retail-0009 (5 facial landmarks, crops eye regions)
4. gaze-estimation-adas-0002 (3D gaze vector from eye crops + head pose)

- Runs at ~20 FPS on-device
- Reference: [gen2-gaze-estimation](https://github.com/luxonis/depthai-experiments/tree/master/gen2-gaze-estimation)

### L2CS-Net (single model, higher accuracy)

- ResNet-50 backbone, 448x448 input
- 3.92 deg mean angular error (better than ADAS)
- Only 4.3 FPS on Myriad X -- too slow for responsive trigger
- Better suited if we offload to Mac GPU in the future

### Face detection + proximity only

- Simplest: detect face, check bounding box size
- Fast but can't distinguish "facing camera" from "facing away slightly"
- Not recommended

## macOS Integration

### Recommended: Python subprocess

```
Swift App  <--stdout JSON-->  Python Script  <--USB/XLink-->  OAK-D Lite
```

1. Swift app spawns a Python process at launch
2. Python script runs the DepthAI pipeline
3. Sends JSON events over stdout: `{"looking": true, "yaw": 2.3, "pitch": -1.1}`
4. Swift app reads events and triggers Aqua Voice hotkey via CGEvent

### Why subprocess over C++ bridge
- All DepthAI examples and docs are Python-first
- No Swift bindings exist
- C++ bridging adds CMake/build complexity for minimal benefit
- Python process is isolated -- crashes don't take down the main app
- Easy to iterate on the detection logic

### SDK Installation

```bash
pip install depthai   # v3.6.1+, macOS 11.0+ ARM64 and x86-64
```

No special drivers needed. The camera does NOT appear as a standard webcam -- it uses XLink protocol via the DepthAI library.

## Existing Reference Code

| Example | URL | What it does |
|---------|-----|-------------|
| gen2-head-posture-detection | [oak-examples](https://github.com/luxonis/oak-examples/tree/master/gen2-head-posture-detection) | 2-stage face + head pose (start here) |
| gen2-gaze-estimation | [depthai-experiments](https://github.com/luxonis/depthai-experiments/tree/master/gen2-gaze-estimation) | Full 4-model gaze pipeline |
| L2CS-Net | [model zoo](https://models.luxonis.com/luxonis/l2cs-net/) | Single-model gaze (slow on RVC2) |

## Interaction Design (TBD)

Open questions:
- **Dwell time**: How long must you look before triggering? 0.5s? 1s?
- **Visual feedback**: Should the menu bar icon change when the camera detects you're looking?
- **Cancel gesture**: Look away to cancel? Or only keyboard cancel?
- **"Cooldown"**: After dictation ends, ignore gaze for N seconds to prevent re-trigger?
- **Multiple faces**: Ignore if multiple faces detected? Or use depth to pick closest?
- **Low light**: OAK-D Lite has no IR illuminator -- how does it perform in dim rooms?

## Implementation Phases

### Phase 1: Proof of concept
- Python script with gen2-head-posture-detection example
- Print "LOOKING" / "NOT LOOKING" to terminal
- Tune yaw/pitch thresholds and dwell time at your desk

### Phase 2: Swift integration
- Subprocess launcher in the app
- JSON event parsing
- Trigger Aqua Voice hotkey (CGEvent)
- Menu bar indicator for camera status

### Phase 3: Polish
- Settings UI: enable/disable camera trigger, dwell time slider
- Graceful handling: camera disconnected, USB errors, sleep/wake
- Battery/power considerations (continuous inference)

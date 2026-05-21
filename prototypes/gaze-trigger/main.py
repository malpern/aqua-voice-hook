#!/usr/bin/env python3
"""
Gaze trigger proof-of-concept for OAK-D Lite.

Detects when the user is looking at the camera using a two-stage pipeline:
  1. YuNet face detection
  2. Head pose estimation (yaw/pitch/roll)

When the user sustains gaze for DWELL_FRAMES consecutive frames, prints TRIGGER.
Outputs JSON lines to stdout for future integration with the Swift app.

Usage:
    uv run main.py
    uv run main.py --dwell 0.5 --threshold 20 --preview
"""

import argparse
import json
import sys
import time

import depthai as dai
from depthai_nodes import ParsingNeuralNetwork, FrameCropper, GatherData


LOOKING_THRESHOLD_DEFAULT = 15.0  # degrees
DWELL_TIME_DEFAULT = 1.0  # seconds
COOLDOWN_DEFAULT = 2.0  # seconds after trigger before re-arming
CAMERA_FPS = 20


def build_pipeline(device: dai.Device, preview: bool = False):
    pipeline = dai.Pipeline(device)

    # --- Stage 1: Camera + Face Detection ---
    cam = pipeline.create(dai.node.Camera).build(dai.CameraBoardSocket.CAM_A)
    cam_out = cam.requestOutput(size=(640, 480), type=dai.ImgFrame.Type.BGR888p, fps=CAMERA_FPS)

    face_desc = dai.NNModelDescription("luxonis/yunet:640x480")
    face_desc.platform = device.getPlatformAsString()
    face_archive = dai.NNArchive(dai.getModelFromZoo(face_desc))
    face_nn = pipeline.create(ParsingNeuralNetwork).build(cam_out, face_archive)

    # --- Stage 2: Crop faces + Head Pose Estimation ---
    cropper = pipeline.create(FrameCropper).build(
        cam_out, face_nn.out, resize=(60, 60)
    )

    pose_desc = dai.NNModelDescription("luxonis/head-pose-estimation:60x60")
    pose_desc.platform = device.getPlatformAsString()
    pose_archive = dai.NNArchive(dai.getModelFromZoo(pose_desc))
    pose_nn = pipeline.create(ParsingNeuralNetwork).build(cropper.out, pose_archive)

    # --- Sync detections with pose results ---
    gather = pipeline.create(GatherData).build(face_nn.out, pose_nn.out)
    gather_q = gather.out.createOutputQueue(maxSize=4, blocking=False)

    preview_q = None
    if preview:
        preview_q = cam_out.createOutputQueue(maxSize=4, blocking=False)

    return pipeline, gather_q, preview_q


def extract_head_pose(predictions):
    """Extract yaw, pitch, roll from head pose prediction."""
    if hasattr(predictions, "yaw"):
        return predictions.yaw, predictions.pitch, predictions.roll

    if hasattr(predictions, "getTensor"):
        yaw = float(predictions.getTensor("angle_y_fc").flatten()[0])
        pitch = float(predictions.getTensor("angle_p_fc").flatten()[0])
        roll = float(predictions.getTensor("angle_r_fc").flatten()[0])
        return yaw, pitch, roll

    raise ValueError(f"Cannot extract head pose from {type(predictions)}")


def run(threshold: float, dwell_time: float, cooldown: float, preview: bool):
    print(json.dumps({"event": "starting", "threshold": threshold, "dwell_time": dwell_time}),
          flush=True)

    device = dai.Device()
    pipeline, gather_q, preview_q = build_pipeline(device, preview)

    if preview:
        import cv2

    pipeline.start()
    print(json.dumps({"event": "running", "camera": device.getDeviceName()}), flush=True)

    consecutive = 0
    dwell_frames = int(dwell_time * CAMERA_FPS)
    state = "idle"  # idle | dwelling | triggered | cooldown
    last_trigger_time = 0.0

    try:
        while pipeline.isRunning():
            gather_msg = gather_q.tryGet()
            if gather_msg is None:
                time.sleep(0.005)
                continue

            now = time.time()

            # Cooldown check
            if state == "cooldown":
                if now - last_trigger_time > cooldown:
                    state = "idle"
                    consecutive = 0
                    print(json.dumps({"event": "armed"}), flush=True)
                else:
                    continue

            detections = gather_msg.first
            pose_results = gather_msg.second

            looking = False
            yaw = pitch = roll = 0.0

            if detections and pose_results:
                for det, pose_data in zip(detections, pose_results):
                    try:
                        yaw, pitch, roll = extract_head_pose(pose_data)
                        if abs(yaw) < threshold and abs(pitch) < threshold:
                            looking = True
                            break
                    except (ValueError, IndexError, AttributeError):
                        continue

            if looking:
                consecutive += 1
                if state == "idle":
                    state = "dwelling"
                    print(json.dumps({
                        "event": "looking",
                        "yaw": round(yaw, 1),
                        "pitch": round(pitch, 1),
                        "roll": round(roll, 1),
                    }), flush=True)

                if state == "dwelling" and consecutive >= dwell_frames:
                    state = "triggered"
                    last_trigger_time = now
                    print(json.dumps({
                        "event": "trigger",
                        "yaw": round(yaw, 1),
                        "pitch": round(pitch, 1),
                        "dwell_frames": consecutive,
                    }), flush=True)
                    state = "cooldown"

                elif state == "dwelling" and consecutive % 5 == 0:
                    progress = min(1.0, consecutive / dwell_frames)
                    print(json.dumps({
                        "event": "dwell_progress",
                        "progress": round(progress, 2),
                        "yaw": round(yaw, 1),
                        "pitch": round(pitch, 1),
                    }), flush=True)
            else:
                if state == "dwelling" and consecutive > 0:
                    print(json.dumps({"event": "look_away", "was_at_frame": consecutive}),
                          flush=True)
                consecutive = 0
                if state != "cooldown":
                    state = "idle"

            if preview and preview_q:
                frame = preview_q.tryGet()
                if frame is not None:
                    img = frame.getCvFrame()
                    label = f"yaw:{yaw:.0f} pitch:{pitch:.0f} [{state}]"
                    color = (0, 255, 0) if looking else (0, 0, 255)
                    cv2.putText(img, label, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
                    if state == "dwelling":
                        progress = min(1.0, consecutive / dwell_frames)
                        bar_w = int(img.shape[1] * progress)
                        cv2.rectangle(img, (0, img.shape[0] - 10), (bar_w, img.shape[0]), (0, 255, 200), -1)
                    cv2.imshow("Gaze Trigger", img)
                    if cv2.waitKey(1) == ord("q"):
                        break

    except KeyboardInterrupt:
        pass
    finally:
        print(json.dumps({"event": "stopped"}), flush=True)
        if preview:
            import cv2
            cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description="OAK-D Lite gaze trigger PoC")
    parser.add_argument("--threshold", type=float, default=LOOKING_THRESHOLD_DEFAULT,
                        help=f"Yaw/pitch threshold in degrees (default: {LOOKING_THRESHOLD_DEFAULT})")
    parser.add_argument("--dwell", type=float, default=DWELL_TIME_DEFAULT,
                        help=f"Seconds of sustained gaze to trigger (default: {DWELL_TIME_DEFAULT})")
    parser.add_argument("--cooldown", type=float, default=COOLDOWN_DEFAULT,
                        help=f"Seconds after trigger before re-arming (default: {COOLDOWN_DEFAULT})")
    parser.add_argument("--preview", action="store_true",
                        help="Show camera preview with OpenCV (requires opencv-python)")
    args = parser.parse_args()
    run(args.threshold, args.dwell, args.cooldown, args.preview)


if __name__ == "__main__":
    main()

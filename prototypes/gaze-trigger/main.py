#!/usr/bin/env python3
"""
Gaze trigger proof-of-concept for OAK-D Lite.

Detects when the user is looking at the camera using a two-stage pipeline:
  1. YuNet face detection (on-device)
  2. Head pose estimation (on-device, per detected face)

When the user sustains gaze for --dwell seconds, emits a trigger event.
Outputs JSON lines to stdout for future integration with the Swift app.

Usage:
    uv run main.py
    uv run main.py --dwell 0.5 --threshold 20 --preview
"""

import argparse
import json
import time

import depthai as dai
import numpy as np
from depthai_nodes.node import ParsingNeuralNetwork, FrameCropper


LOOKING_THRESHOLD_DEFAULT = 15.0  # degrees
DWELL_TIME_DEFAULT = 1.0  # seconds
COOLDOWN_DEFAULT = 2.0  # seconds after trigger before re-arming
CAMERA_FPS = 20


def run(threshold: float, dwell_time: float, cooldown: float, preview: bool):
    print(json.dumps({"event": "starting", "threshold": threshold, "dwell_time": dwell_time}),
          flush=True)

    device = dai.Device()
    print(json.dumps({"event": "device_found", "camera": device.getDeviceName()}), flush=True)

    with dai.Pipeline(device) as pipeline:
        # --- Stage 1: Camera + Face Detection ---
        cam = pipeline.create(dai.node.Camera).build(sensorFps=CAMERA_FPS)
        cam_out = cam.requestOutput(
            size=(640, 480), type=dai.ImgFrame.Type.BGR888p, fps=CAMERA_FPS,
        )

        face_nn = pipeline.create(ParsingNeuralNetwork).build(
            input=cam_out, nnSource="luxonis/yunet:640x480",
        )

        # --- Stage 2: Crop detected faces + Head Pose Estimation ---
        cropper = (
            pipeline.create(FrameCropper)
            .fromImgDetections(
                inputImgDetections=face_nn.out,
                outputSize=(60, 60),
                resizeMode=dai.ImageManipConfig.ResizeMode.LETTERBOX,
            )
            .build(inputImage=cam_out)
        )

        # Use raw NeuralNetwork for head pose — the model has 3 output heads
        # (angle_y_fc, angle_p_fc, angle_r_fc) and ParsingNeuralNetwork.out
        # requires exactly 1 head. NeuralNetwork bundles all into one NNData.
        pose_desc = dai.NNModelDescription("luxonis/head-pose-estimation:60x60")
        pose_desc.platform = device.getPlatformAsString()
        pose_archive = dai.NNArchive(dai.getModelFromZoo(pose_desc))

        pose_nn = pipeline.create(dai.node.NeuralNetwork)
        pose_nn.setNNArchive(pose_archive)
        cropper.out.link(pose_nn.input)

        pose_q = pose_nn.out.createOutputQueue(maxSize=4, blocking=False)
        det_q = face_nn.out.createOutputQueue(maxSize=4, blocking=False)

        preview_q = None
        if preview:
            preview_q = cam_out.createOutputQueue(maxSize=4, blocking=False)

        pipeline.start()
        print(json.dumps({"event": "running"}), flush=True)

        consecutive = 0
        dwell_frames = int(dwell_time * CAMERA_FPS)
        state = "idle"  # idle | dwelling | cooldown
        last_trigger_time = 0.0
        yaw = pitch = roll = 0.0

        if preview:
            import cv2

        try:
            while pipeline.isRunning():
                pipeline.processTasks()

                # Check for new detections (tells us if any face is visible)
                det_msg = det_q.tryGet()
                has_face = False
                if det_msg is not None:
                    dets = det_msg.detections if hasattr(det_msg, "detections") else []
                    has_face = len(dets) > 0

                # Check for pose results (one per cropped face)
                pose_msg = pose_q.tryGet()
                looking = False

                if pose_msg is not None:
                    try:
                        yaw = float(np.array(pose_msg.getTensor("angle_y_fc")).flatten()[0])
                        pitch = float(np.array(pose_msg.getTensor("angle_p_fc")).flatten()[0])
                        roll = float(np.array(pose_msg.getTensor("angle_r_fc")).flatten()[0])
                        looking = abs(yaw) < threshold and abs(pitch) < threshold
                    except Exception:
                        pass

                now = time.time()

                # Cooldown: ignore gaze after a trigger
                if state == "cooldown":
                    if now - last_trigger_time > cooldown:
                        state = "idle"
                        consecutive = 0
                        print(json.dumps({"event": "armed"}), flush=True)
                    else:
                        _drain_preview(preview, preview_q, yaw, pitch, state, False, 0, dwell_frames)
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
                    if pose_msg is not None or (det_msg is not None and not has_face):
                        if state == "dwelling" and consecutive > 0:
                            print(json.dumps({"event": "look_away", "was_at_frame": consecutive}),
                                  flush=True)
                        consecutive = 0
                        if state != "cooldown":
                            state = "idle"

                _drain_preview(preview, preview_q, yaw, pitch, state, looking, consecutive, dwell_frames)

                if pose_msg is None and det_msg is None:
                    time.sleep(0.005)

        except KeyboardInterrupt:
            pass
        finally:
            print(json.dumps({"event": "stopped"}), flush=True)
            if preview:
                import cv2
                cv2.destroyAllWindows()


def _drain_preview(preview, preview_q, yaw, pitch, state, looking, consecutive, dwell_frames):
    if not preview or preview_q is None:
        return
    import cv2
    frame = preview_q.tryGet()
    if frame is None:
        return
    img = frame.getCvFrame()
    label = f"yaw:{yaw:.0f} pitch:{pitch:.0f} [{state}]"
    color = (0, 255, 0) if looking else (0, 0, 255)
    cv2.putText(img, label, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
    if state == "dwelling" and dwell_frames > 0:
        progress = min(1.0, consecutive / dwell_frames)
        bar_w = int(img.shape[1] * progress)
        cv2.rectangle(img, (0, img.shape[0] - 10), (bar_w, img.shape[0]), (0, 255, 200), -1)
    cv2.imshow("Gaze Trigger", img)
    if cv2.waitKey(1) == ord("q"):
        raise KeyboardInterrupt


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

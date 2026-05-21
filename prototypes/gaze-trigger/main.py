#!/usr/bin/env python3
"""
Gaze trigger proof-of-concept for OAK-D Lite.

Uses the OAK-D Lite as a camera source and MediaPipe Face Mesh on the
host to estimate head pose. When the user looks at the camera for
--dwell seconds, emits a trigger event.

Outputs JSON lines to stdout for future integration with the Swift app.

Usage:
    uv run main.py
    uv run main.py --dwell 0.5 --threshold 20 --preview
"""

import argparse
import json
import time

import cv2
import depthai as dai
import mediapipe as mp
import numpy as np


LOOKING_THRESHOLD_DEFAULT = 15.0  # degrees
DWELL_TIME_DEFAULT = 1.0  # seconds
COOLDOWN_DEFAULT = 2.0  # seconds after trigger before re-arming
CAMERA_FPS = 20

# MediaPipe face mesh landmarks used for head pose estimation.
# These 6 points give a stable solvePnP result.
FACE_LANDMARKS = {
    "nose_tip": 1,
    "chin": 152,
    "left_eye_outer": 263,
    "right_eye_outer": 33,
    "left_mouth": 287,
    "right_mouth": 57,
}

# Corresponding 3D model points (generic face model, arbitrary units).
MODEL_POINTS = np.array([
    (0.0, 0.0, 0.0),          # nose tip
    (0.0, -330.0, -65.0),     # chin
    (-225.0, 170.0, -135.0),  # left eye outer
    (225.0, 170.0, -135.0),   # right eye outer
    (-150.0, -150.0, -125.0), # left mouth
    (150.0, -150.0, -125.0),  # right mouth
], dtype=np.float64)


def estimate_head_pose(landmarks, img_w: int, img_h: int):
    """Estimate yaw and pitch from MediaPipe face landmarks using solvePnP."""
    image_points = np.array([
        (landmarks[idx].x * img_w, landmarks[idx].y * img_h)
        for idx in FACE_LANDMARKS.values()
    ], dtype=np.float64)

    focal_length = img_w
    center = (img_w / 2, img_h / 2)
    camera_matrix = np.array([
        [focal_length, 0, center[0]],
        [0, focal_length, center[1]],
        [0, 0, 1],
    ], dtype=np.float64)
    dist_coeffs = np.zeros((4, 1))

    _, rotation_vec, _ = cv2.solvePnP(
        MODEL_POINTS, image_points, camera_matrix, dist_coeffs,
        flags=cv2.SOLVEPNP_ITERATIVE,
    )

    rmat, _ = cv2.Rodrigues(rotation_vec)
    angles, _, _, _, _, _ = cv2.RQDecomp3x3(rmat)
    return angles[1], angles[0], angles[2]  # yaw, pitch, roll


def run(threshold: float, dwell_time: float, cooldown: float, preview: bool):
    print(json.dumps({"event": "starting", "threshold": threshold, "dwell_time": dwell_time}),
          flush=True)

    device = dai.Device()
    print(json.dumps({"event": "device_found", "camera": device.getDeviceName()}), flush=True)

    with dai.Pipeline(device) as pipeline:
        cam = pipeline.create(dai.node.Camera).build(sensorFps=CAMERA_FPS)
        cam_out = cam.requestOutput(
            size=(640, 480), type=dai.ImgFrame.Type.BGR888p, fps=CAMERA_FPS,
        )
        frame_q = cam_out.createOutputQueue(maxSize=4, blocking=False)

        pipeline.start()
        print(json.dumps({"event": "running"}), flush=True)

        face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=False,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

        consecutive = 0
        dwell_frames = int(dwell_time * CAMERA_FPS)
        state = "idle"
        last_trigger_time = 0.0
        yaw = pitch = roll = 0.0

        try:
            while pipeline.isRunning():
                pipeline.processTasks()

                frame_msg = frame_q.tryGet()
                if frame_msg is None:
                    time.sleep(0.005)
                    continue

                img = frame_msg.getCvFrame()
                img_h, img_w = img.shape[:2]

                rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                results = face_mesh.process(rgb)

                now = time.time()
                looking = False

                if results.multi_face_landmarks:
                    landmarks = results.multi_face_landmarks[0].landmark
                    try:
                        yaw, pitch, roll = estimate_head_pose(landmarks, img_w, img_h)
                        looking = abs(yaw) < threshold and abs(pitch) < threshold
                    except Exception:
                        pass

                if state == "cooldown":
                    if now - last_trigger_time > cooldown:
                        state = "idle"
                        consecutive = 0
                        print(json.dumps({"event": "armed"}), flush=True)
                    else:
                        if preview:
                            _show_preview(img, yaw, pitch, state, False, 0, dwell_frames)
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
                    if state == "dwelling" and consecutive > 0:
                        print(json.dumps({"event": "look_away", "was_at_frame": consecutive}),
                              flush=True)
                    consecutive = 0
                    if state != "cooldown":
                        state = "idle"

                if preview:
                    _show_preview(img, yaw, pitch, state, looking, consecutive, dwell_frames)

        except KeyboardInterrupt:
            pass
        finally:
            face_mesh.close()
            print(json.dumps({"event": "stopped"}), flush=True)
            if preview:
                cv2.destroyAllWindows()


def _show_preview(img, yaw, pitch, state, looking, consecutive, dwell_frames):
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
                        help="Show camera preview window with head pose overlay")
    args = parser.parse_args()
    run(args.threshold, args.dwell, args.cooldown, args.preview)


if __name__ == "__main__":
    main()

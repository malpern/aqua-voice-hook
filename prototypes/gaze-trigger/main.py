#!/usr/bin/env python3
"""
Gaze trigger proof-of-concept for OAK-D Lite.

Uses the OAK-D Lite as a camera source and OpenCV's Haar cascade face
detector on the host. A frontal face detection at desk distance is a
reliable proxy for "looking at the camera." When sustained for --dwell
seconds, emits a trigger event.

Outputs JSON lines to stdout for future integration with the Swift app.

Usage:
    uv run main.py --preview
    uv run main.py --dwell 0.5 --preview
"""

import argparse
import json
import time

import cv2
import depthai as dai


LOOKING_THRESHOLD_DEFAULT = 15.0  # degrees (unused for now, kept for future head pose)
DWELL_TIME_DEFAULT = 1.0  # seconds
COOLDOWN_DEFAULT = 2.0  # seconds after trigger before re-arming
CAMERA_FPS = 20


def run(dwell_time: float, cooldown: float, preview: bool):
    print(json.dumps({"event": "starting", "dwell_time": dwell_time}), flush=True)

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    if face_cascade.empty():
        print(json.dumps({"event": "error", "msg": "Failed to load Haar cascade"}), flush=True)
        return

    device = dai.Device()
    print(json.dumps({"event": "device_found", "camera": device.getDeviceName()}), flush=True)

    with dai.Pipeline(device) as pipeline:
        cam = pipeline.create(dai.node.Camera).build(sensorFps=CAMERA_FPS)
        cam_out = cam.requestOutput(
            size=(640, 480), type=dai.ImgFrame.Type.BGR888p, fps=CAMERA_FPS,
        )
        frame_q = cam_out.createOutputQueue(maxSize=2, blocking=False)

        pipeline.start()
        print(json.dumps({"event": "running"}), flush=True)

        consecutive = 0
        dwell_frames = max(1, int(dwell_time * CAMERA_FPS))
        state = "idle"
        last_trigger_time = 0.0

        try:
            while pipeline.isRunning():
                pipeline.processTasks()

                frame_msg = frame_q.tryGet()
                if frame_msg is None:
                    time.sleep(0.005)
                    continue

                img = frame_msg.getCvFrame()
                gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

                faces = face_cascade.detectMultiScale(
                    gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80),
                )
                looking = len(faces) > 0

                now = time.time()

                if state == "cooldown":
                    if now - last_trigger_time > cooldown:
                        state = "idle"
                        consecutive = 0
                        print(json.dumps({"event": "armed"}), flush=True)
                    else:
                        if preview:
                            _show_preview(img, faces, state, False, 0, dwell_frames)
                        continue

                if looking:
                    consecutive += 1
                    if state == "idle":
                        state = "dwelling"
                        x, y, w, h = faces[0]
                        print(json.dumps({
                            "event": "looking",
                            "face_x": int(x), "face_y": int(y),
                            "face_w": int(w), "face_h": int(h),
                        }), flush=True)

                    if state == "dwelling" and consecutive >= dwell_frames:
                        last_trigger_time = now
                        print(json.dumps({
                            "event": "trigger",
                            "dwell_frames": consecutive,
                        }), flush=True)
                        state = "cooldown"

                    elif state == "dwelling" and consecutive % 5 == 0:
                        progress = min(1.0, consecutive / dwell_frames)
                        print(json.dumps({
                            "event": "dwell_progress",
                            "progress": round(progress, 2),
                        }), flush=True)
                else:
                    if state == "dwelling" and consecutive > 0:
                        print(json.dumps({"event": "look_away", "was_at_frame": consecutive}),
                              flush=True)
                    consecutive = 0
                    if state != "cooldown":
                        state = "idle"

                if preview:
                    _show_preview(img, faces, state, looking, consecutive, dwell_frames)

        except KeyboardInterrupt:
            pass
        finally:
            print(json.dumps({"event": "stopped"}), flush=True)
            if preview:
                cv2.destroyAllWindows()


def _show_preview(img, faces, state, looking, consecutive, dwell_frames):
    color = (0, 255, 0) if looking else (0, 0, 255)
    for (x, y, w, h) in faces:
        cv2.rectangle(img, (x, y), (x + w, y + h), color, 2)

    label = f"[{state}] faces:{len(faces)}"
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
    parser.add_argument("--dwell", type=float, default=DWELL_TIME_DEFAULT,
                        help=f"Seconds of sustained gaze to trigger (default: {DWELL_TIME_DEFAULT})")
    parser.add_argument("--cooldown", type=float, default=COOLDOWN_DEFAULT,
                        help=f"Seconds after trigger before re-arming (default: {COOLDOWN_DEFAULT})")
    parser.add_argument("--preview", action="store_true",
                        help="Show camera preview window with face detection overlay")
    args = parser.parse_args()
    run(args.dwell, args.cooldown, args.preview)


if __name__ == "__main__":
    main()

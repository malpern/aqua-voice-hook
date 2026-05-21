import AppKit
import Foundation

final class GazeTriggerManager {
    private var process: Process?
    private var overlay: GazeOverlayWindow?

    func start() {
        guard process == nil else { return }

        let scriptPath = findGazeScript()
        guard let scriptPath else {
            NSLog("GazeTrigger: gaze script not found")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", "--python", "3.12", scriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let line = String(data: data, encoding: .utf8) else { return }
            for part in line.split(separator: "\n") {
                self?.handleEvent(String(part))
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                NSLog("GazeTrigger: process exited")
            }
        }

        do {
            try proc.run()
            process = proc
            NSLog("GazeTrigger: started (pid %d)", proc.processIdentifier)
        } catch {
            NSLog("GazeTrigger: failed to launch: %@", error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        DispatchQueue.main.async { [weak self] in
            self?.overlay?.dismiss()
        }
    }

    private func handleEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = dict["event"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            switch event {
            case "trigger":
                NSLog("GazeTrigger: TRIGGER")
                self?.showOverlay()
            case "armed":
                self?.dismissOverlay()
            case "running":
                NSLog("GazeTrigger: pipeline running")
            case "stopped":
                self?.dismissOverlay()
            default:
                break
            }
        }
    }

    private func showOverlay() {
        if overlay == nil {
            overlay = GazeOverlayWindow()
        }
        overlay?.show()
    }

    private func dismissOverlay() {
        overlay?.dismiss()
    }

    private func findGazeScript() -> String? {
        let candidates = [
            Bundle.main.bundlePath + "/../../../prototypes/gaze-trigger/main.py",
            NSHomeDirectory() + "/local-code/aqua-voice-automation/prototypes/gaze-trigger/main.py",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }
}

#!/usr/bin/env swift
// Aqua Voice Post-Dictation Hook
//
// Detects Aqua Voice transcriptions by monitoring NSPasteboard.changeCount.
// Aqua Voice's signature: a +2 changeCount jump (transcription written),
// followed ~750ms later by a +1 jump (original clipboard restored).
//
// This script fires a hook ONLY on real dictation events, filtering out
// the restore events and normal clipboard activity.
//
// Usage:
//   swift aqua-voice-hook.swift                          # just log detections
//   swift aqua-voice-hook.swift ./my-hook.sh             # run hook with text as $1
//   swift aqua-voice-hook.swift "shortcuts run MyShortcut" # run any command
//
// The hook receives:
//   $1 = transcribed text
//   $AQUA_FRONTMOST_APP = the app that was focused during dictation
//   $AQUA_TIMESTAMP = ISO 8601 timestamp of the dictation
//   stdin = transcribed text (for piping)

import AppKit
import Foundation

let pasteboard = NSPasteboard.general
var lastChangeCount = pasteboard.changeCount
var lastContent = pasteboard.string(forType: .string) ?? ""
var lastChangeTime = Date.distantPast

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "HH:mm:ss.SSS"

let isoFormatter = ISO8601DateFormatter()
isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

let workspace = NSWorkspace.shared
let hookCommand = CommandLine.arguments.count > 1
    ? CommandLine.arguments.dropFirst().joined(separator: " ")
    : nil

print("=== Aqua Voice Post-Dictation Hook ===")
if let hook = hookCommand {
    print("Hook: \(hook)")
} else {
    print("No hook configured — logging detections only.")
    print("Pass a command as argument to run it on each dictation.")
}
print("Monitoring pasteboard... Ctrl+C to stop.\n")

func isAquaVoiceRunning() -> Bool {
    workspace.runningApplications.contains {
        ($0.bundleIdentifier ?? "").lowercased().contains("aquavoice") ||
        ($0.bundleIdentifier ?? "").lowercased().contains("aqua-voice") ||
        ($0.localizedName ?? "").lowercased().contains("aqua voice")
    }
}

func runHook(text: String, frontApp: String) {
    guard let hook = hookCommand else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", hook + " \"$1\"", "--", text]
    process.environment = ProcessInfo.processInfo.environment.merging([
        "AQUA_TRANSCRIPTION": text,
        "AQUA_FRONTMOST_APP": frontApp,
        "AQUA_TIMESTAMP": isoFormatter.string(from: Date()),
    ]) { _, new in new }

    let pipe = Pipe()
    process.standardInput = pipe
    pipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
    pipe.fileHandleForWriting.closeFile()

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            print("  ⚠ Hook exited with status \(process.terminationStatus)")
        }
    } catch {
        print("  ⚠ Hook failed: \(error.localizedDescription)")
    }
}

while true {
    let currentCount = pasteboard.changeCount
    if currentCount != lastChangeCount {
        let now = Date()
        let jump = currentCount - lastChangeCount
        let timeSinceLast = now.timeIntervalSince(lastChangeTime)
        let content = pasteboard.string(forType: .string) ?? "(non-text)"
        let frontApp = workspace.frontmostApplication?.localizedName ?? "unknown"
        let bundleId = workspace.frontmostApplication?.bundleIdentifier ?? "unknown"
        let aquaRunning = isAquaVoiceRunning()
        let timestamp = dateFormatter.string(from: now)

        // Aqua Voice signature: +2 jump with Aqua Voice running.
        // The +1 restore event comes ~750ms later — skip it.
        let isAquaDictation = jump >= 2 && aquaRunning
        let isAquaRestore = jump == 1 && aquaRunning && timeSinceLast < 2.0

        if isAquaDictation {
            print("[\(timestamp)] ✦ DICTATION DETECTED")
            print("  App:     \(frontApp) (\(bundleId))")
            print("  Length:  \(content.count) chars")
            print("  Text:    \(String(content.prefix(300)))")

            if let _ = hookCommand {
                print("  Running hook...")
                runHook(text: content, frontApp: frontApp)
            }
            print()
        } else if isAquaRestore {
            // Aqua Voice restoring the original clipboard — silently skip
        } else {
            // Normal clipboard activity (user copy, other apps)
            print("[\(timestamp)] (clipboard: \(jump > 0 ? "+\(jump)" : "\(jump)"), \(content.count) chars, \(frontApp)) — not Aqua Voice")
        }

        lastChangeCount = currentCount
        lastContent = content
        lastChangeTime = now
    }
    Thread.sleep(forTimeInterval: 0.05)
}

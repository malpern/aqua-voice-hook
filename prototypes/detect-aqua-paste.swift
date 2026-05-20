#!/usr/bin/env swift
// Detect Aqua Voice pastes by monitoring NSPasteboard.changeCount.
// This is the canonical way to observe clipboard changes on macOS.
// Run: swift detect-aqua-paste.swift
// Then dictate with Aqua Voice. Ctrl+C to stop.

import AppKit
import Foundation

let pasteboard = NSPasteboard.general
var lastChangeCount = pasteboard.changeCount
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "HH:mm:ss.SSS"

print("=== Aqua Voice Paste Detector (Swift) ===")
print("Monitoring NSPasteboard.changeCount for changes...")
print("Dictate something with Aqua Voice. Ctrl+C to stop.\n")

let workspace = NSWorkspace.shared

while true {
    let currentCount = pasteboard.changeCount
    if currentCount != lastChangeCount {
        let now = dateFormatter.string(from: Date())
        let frontApp = workspace.frontmostApplication?.localizedName ?? "unknown"
        let sourceApp = workspace.frontmostApplication?.bundleIdentifier ?? "unknown"
        let content = pasteboard.string(forType: .string) ?? "(non-text)"
        let charCount = content.count
        let preview = String(content.prefix(200))

        print("[\(now)] CLIPBOARD CHANGED (changeCount: \(lastChangeCount) → \(currentCount))")
        print("  Frontmost app:  \(frontApp) (\(sourceApp))")
        print("  Length:          \(charCount) chars")
        print("  Content:         \(preview)")

        // Check if Aqua Voice is running
        let aquaRunning = workspace.runningApplications.contains {
            $0.bundleIdentifier?.contains("aquavoice") == true ||
            $0.localizedName?.lowercased().contains("aqua") == true
        }
        print("  Aqua Voice running: \(aquaRunning)")
        print()

        lastChangeCount = currentCount
    }
    Thread.sleep(forTimeInterval: 0.05) // 50ms poll — light on CPU
}

import AppKit
import Foundation

struct DictationEvent {
    let text: String
    let frontmostApp: String
    let bundleIdentifier: String
    let timestamp: Date
}

final class PasteboardMonitor {
    static let didDetect = Notification.Name("PasteboardMonitorDidDetect")

    private(set) var isRunning = false
    private(set) var lastDictation: DictationEvent?
    private(set) var detectionCount = 0

    var onDictation: ((DictationEvent) -> Void)?
    var clipboardHistoryEnabled = true

    private var timer: DispatchSourceTimer?
    private var pendingTranscription: String?
    private var pendingTimestamp = Date.distantPast
    private var isInjecting = false

    func start(pollIntervalMs: Int) {
        guard !isRunning else { return }
        isRunning = true

        let pasteboard = NSPasteboard.general
        var lastChangeCount = pasteboard.changeCount

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(pollIntervalMs), leeway: .milliseconds(50))

        timer.setEventHandler { [weak self] in
            guard let self, !self.isInjecting else { return }

            let currentCount = pasteboard.changeCount
            guard currentCount != lastChangeCount else { return }

            let jump = currentCount - lastChangeCount
            let timeSincePending = Date().timeIntervalSince(self.pendingTimestamp)
            lastChangeCount = currentCount

            let workspace = NSWorkspace.shared
            let aquaRunning = workspace.runningApplications.contains {
                ($0.bundleIdentifier ?? "").lowercased().contains("aquavoice")
            }

            // +2 jump with Aqua Voice running = new dictation
            if jump >= 2, aquaRunning {
                guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

                let event = DictationEvent(
                    text: text,
                    frontmostApp: workspace.frontmostApplication?.localizedName ?? "unknown",
                    bundleIdentifier: workspace.frontmostApplication?.bundleIdentifier ?? "unknown",
                    timestamp: Date()
                )

                if self.clipboardHistoryEnabled {
                    self.pendingTranscription = text
                    self.pendingTimestamp = Date()
                }

                DispatchQueue.main.async {
                    self.lastDictation = event
                    self.detectionCount += 1
                    self.onDictation?(event)
                    NotificationCenter.default.post(name: PasteboardMonitor.didDetect, object: self)
                }
                return
            }

            // +1 jump shortly after a dictation = Aqua Voice restoring clipboard
            // Inject the transcription into clipboard history then restore
            if jump == 1, aquaRunning, self.pendingTranscription != nil, timeSincePending < 2.0 {
                let transcription = self.pendingTranscription!
                self.pendingTranscription = nil

                let restoredContent = pasteboard.string(forType: .string)

                self.isInjecting = true

                // Write transcription as a clean pasteboard item — no hide markers
                pasteboard.clearContents()
                let item = NSPasteboardItem()
                item.setString(transcription, forType: .string)
                item.setString("com.aqua-voice-hook.app", forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
                pasteboard.writeObjects([item])

                // Wait 750ms for clipboard managers to capture, then restore original
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(750)) {
                    if let original = restoredContent {
                        pasteboard.clearContents()
                        pasteboard.setString(original, forType: .string)
                    }
                    lastChangeCount = pasteboard.changeCount
                    self.isInjecting = false
                }
                return
            }
        }

        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }
}

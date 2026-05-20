import Foundation

final class HookRunner {
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func run(hook: HookConfig, event: DictationEvent) {
        if let filter = hook.appFilter, !filter.isEmpty {
            let matches = event.frontmostApp.localizedCaseInsensitiveContains(filter)
                || event.bundleIdentifier.localizedCaseInsensitiveContains(filter)
            guard matches else { return }
        }

        let command = expandPath(hook.command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command + " \"$1\"", "--", event.text]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "AQUA_TRANSCRIPTION": event.text,
            "AQUA_FRONTMOST_APP": event.frontmostApp,
            "AQUA_BUNDLE_ID": event.bundleIdentifier,
            "AQUA_TIMESTAMP": isoFormatter.string(from: event.timestamp),
        ]) { _, new in new }

        let stdin = Pipe()
        process.standardInput = stdin
        if let data = event.text.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        stdin.fileHandleForWriting.closeFile()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
    }

    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst(1))
        }
        return path
    }
}

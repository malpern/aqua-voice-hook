import Foundation

struct HookConfig: Codable {
    var name: String
    var enabled: Bool
    var command: String
    var appFilter: String?
}

struct AutoReturnConfig: Codable {
    var enabled: Bool
    var delayMs: Int
    var apps: [String]

    static let defaultApps: [String] = [
        // Terminals
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.cmuxterm.app",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        // Dev / AI tools
        "com.todesktop.230313mzl4w4u92",
        "com.openai.chat",
        "com.anthropic.claudefordesktop",
    ]

    static let `default` = AutoReturnConfig(
        enabled: true,
        delayMs: 50,
        apps: defaultApps
    )
}

struct AppConfig: Codable {
    var enabled: Bool
    var showMenuBarIcon: Bool
    var pollIntervalMs: Int
    var clipboardHistory: Bool
    var autoReturn: AutoReturnConfig
    var hooks: [HookConfig]

    static let `default` = AppConfig(
        enabled: true,
        showMenuBarIcon: true,
        pollIntervalMs: 100,
        clipboardHistory: true,
        autoReturn: .default,
        hooks: []
    )

    init(enabled: Bool, showMenuBarIcon: Bool, pollIntervalMs: Int, clipboardHistory: Bool, autoReturn: AutoReturnConfig, hooks: [HookConfig]) {
        self.enabled = enabled
        self.showMenuBarIcon = showMenuBarIcon
        self.pollIntervalMs = pollIntervalMs
        self.clipboardHistory = clipboardHistory
        self.autoReturn = autoReturn
        self.hooks = hooks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        showMenuBarIcon = try container.decode(Bool.self, forKey: .showMenuBarIcon)
        pollIntervalMs = try container.decode(Int.self, forKey: .pollIntervalMs)
        clipboardHistory = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistory) ?? true
        autoReturn = try container.decodeIfPresent(AutoReturnConfig.self, forKey: .autoReturn) ?? .default
        hooks = try container.decode([HookConfig].self, forKey: .hooks)
    }

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aqua-voice-hook")
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    static var hooksDir: URL {
        configDir.appendingPathComponent("hooks")
    }
}

final class ConfigManager {
    static let didChange = Notification.Name("ConfigManagerDidChange")

    private(set) var config: AppConfig
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var isSaving = false
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    init() {
        self.config = Self.loadFromDisk() ?? .default
        ensureDirectories()
        if !FileManager.default.fileExists(atPath: AppConfig.configFile.path) {
            save()
        }
        watchConfigFile()
    }

    func update(_ mutation: (inout AppConfig) -> Void) {
        mutation(&config)
        save()
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: AppConfig.hooksDir, withIntermediateDirectories: true)
    }

    private static func loadFromDisk() -> AppConfig? {
        guard let data = try? Data(contentsOf: AppConfig.configFile) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    private func save() {
        isSaving = true
        guard let data = try? encoder.encode(config) else { isSaving = false; return }
        try? data.write(to: AppConfig.configFile, options: .atomic)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.isSaving = false }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func reload() {
        guard !isSaving else { return }
        if let loaded = Self.loadFromDisk() {
            config = loaded
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private func watchConfigFile() {
        let path = AppConfig.configFile.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }
}

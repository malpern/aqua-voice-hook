import AppKit
import CoreGraphics
import ApplicationServices
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    let configManager = ConfigManager()
    let monitor = PasteboardMonitor()
    let hookRunner = HookRunner()
    let gazeTrigger = GazeTriggerManager()
    let updaterController: SPUStandardUpdaterController

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startMonitoring()
        updateStatusItem()
        checkAccessibility()
        gazeTrigger.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(configDidChange), name: ConfigManager.didChange, object: nil
        )
    }

    private func checkAccessibility() {
        guard configManager.config.autoReturn.enabled else { return }
        if AXIsProcessTrusted() { return }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Auto-Return needs Accessibility permission to press the Return key after dictation. Without it, Auto-Return won't work.\n\nClick \"Open Settings\" to grant permission, then restart Aqua Voice Hook."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "aqua-hook" {
            if url.host == "settings" { showSettings() }
        }
    }

    private func startMonitoring() {
        guard configManager.config.enabled else { return }

        monitor.clipboardHistoryEnabled = configManager.config.clipboardHistory

        monitor.onDictation = { [weak self] event in
            guard let self else { return }

            let config = self.configManager.config

            for hook in config.hooks where hook.enabled {
                DispatchQueue.global(qos: .utility).async {
                    self.hookRunner.run(hook: hook, event: event)
                }
            }

            if config.autoReturn.enabled,
               config.autoReturn.apps.contains(event.bundleIdentifier) {
                let delayMs = config.autoReturn.delayMs
                let playSound = config.autoReturn.playSound
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                    Self.pressReturn(playSound: playSound)
                }
            }
        }

        monitor.start(pollIntervalMs: configManager.config.pollIntervalMs)
    }

    private static func pressReturn(playSound: Bool) {
        if playSound {
            NSSound(named: "Purr")?.play()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to keystroke return"]
        try? process.run()
    }

    @objc private func configDidChange() {
        updateStatusItem()
        monitor.clipboardHistoryEnabled = configManager.config.clipboardHistory
    }

    private func updateStatusItem() {
        if configManager.config.showMenuBarIcon {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                statusItem?.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Aqua Voice Hook")
                statusItem?.button?.image?.size = NSSize(width: 16, height: 16)
                buildMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let dot = monitor.isRunning ? "🟢" : "🔴"
        let statusTitle = "\(dot) \(monitor.isRunning ? "Monitoring" : "Stopped") · \(monitor.detectionCount) dictations"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(configManager: configManager, monitor: monitor)
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func quit() {
        gazeTrigger.stop()
        NSApp.terminate(nil)
    }
}

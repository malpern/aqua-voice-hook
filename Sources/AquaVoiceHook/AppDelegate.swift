import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    let configManager = ConfigManager()
    let monitor = PasteboardMonitor()
    let hookRunner = HookRunner()

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startMonitoring()
        updateStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(configDidChange), name: ConfigManager.didChange, object: nil
        )
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
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                    Self.pressReturn()
                }
            }
        }

        monitor.start(pollIntervalMs: configManager.config.pollIntervalMs)
    }

    private static func pressReturn() {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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

        let statusTitle = monitor.isRunning ? "Monitoring" : "Stopped"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        let dot = monitor.isRunning ? "🟢" : "🔴"
        statusItem.title = "\(dot) \(statusTitle)"
        menu.addItem(statusItem)

        let countItem = NSMenuItem(
            title: "\(monitor.detectionCount) dictations detected", action: nil, keyEquivalent: ""
        )
        menu.addItem(countItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

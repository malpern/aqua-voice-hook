import AppKit

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let configManager: ConfigManager
    private let monitor: PasteboardMonitor
    private var observers: [NSObjectProtocol] = []

    private var tabViews: [String: NSView] = [:]
    private var currentTab = "general"

    // General
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Detect Aqua Voice dictations", target: nil, action: nil)
    private let clipboardHistoryCheckbox = NSButton(checkboxWithTitle: "Add dictations to clipboard history", target: nil, action: nil)
    private let menuBarCheckbox = NSButton(checkboxWithTitle: "Show menu bar icon", target: nil, action: nil)

    // Auto-Return
    private let autoReturnCheckbox = NSButton(checkboxWithTitle: "Press Return after dictation", target: nil, action: nil)
    private let soundCheckbox = NSButton(checkboxWithTitle: "Play confirmation sound", target: nil, action: nil)
    private let autoReturnTableView = NSTableView()

    // Hooks
    private let hooksTableView = NSTableView()

    // Status
    private let statusDot = NSView()
    private let statusText = NSTextField(labelWithString: "")
    private let countText = NSTextField(labelWithString: "")
    private let lastAppText = NSTextField(labelWithString: "")
    private let lastTimeText = NSTextField(labelWithString: "")
    private let lastDictationText = NSTextField(wrappingLabelWithString: "")

    private static let tabItems: [(id: String, label: String, icon: String)] = [
        ("general", "General", "gear"),
        ("autoReturn", "Auto-Return", "return"),
        ("hooks", "Hooks", "terminal"),
        ("status", "Status", "heart.text.square"),
    ]

    init(configManager: ConfigManager, monitor: PasteboardMonitor) {
        self.configManager = configManager
        self.monitor = monitor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "General"
        window.titlebarAppearsTransparent = false
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)

        setupToolbar()
        buildAllTabs()
        showTab("general")
        loadValues()

        observers.append(NotificationCenter.default.addObserver(
            forName: ConfigManager.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.loadValues() })

        observers.append(NotificationCenter.default.addObserver(
            forName: PasteboardMonitor.didDetect, object: nil, queue: .main
        ) { [weak self] _ in self?.loadStatusValues() })
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("general")
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.tabItems.map { .init($0.id) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.tabItems.map { .init($0.id) }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.tabItems.map { .init($0.id) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Self.tabItems.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(toolbarTabClicked(_:))
        return item
    }

    @objc private func toolbarTabClicked(_ sender: NSToolbarItem) {
        showTab(sender.itemIdentifier.rawValue)
    }

    private func showTab(_ id: String) {
        currentTab = id
        window?.title = Self.tabItems.first { $0.id == id }?.label ?? ""
        window?.toolbar?.selectedItemIdentifier = .init(id)

        guard let view = tabViews[id] else { return }
        window?.contentView = view
    }

    // MARK: - Build Tabs

    private func buildAllTabs() {
        tabViews["general"] = buildGeneralTab()
        tabViews["autoReturn"] = buildAutoReturnTab()
        tabViews["hooks"] = buildHooksTab()
        tabViews["status"] = buildStatusTab()
    }

    // MARK: - General Tab

    private func buildGeneralTab() -> NSView {
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(toggleEnabled)

        clipboardHistoryCheckbox.target = self
        clipboardHistoryCheckbox.action = #selector(toggleClipboardHistory)
        let clipboardTip = secondaryLabel("Makes dictations visible in Raycast and other clipboard managers.")

        let monitoringGroup = GroupBox(title: "Dictation", content: [
            enabledCheckbox,
            clipboardHistoryCheckbox,
            clipboardTip,
        ])

        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(toggleMenuBar)
        let menuBarTip = secondaryLabel("You can always open settings by double-clicking the app or running:  open aqua-hook://settings")

        let appearanceGroup = GroupBox(title: "Appearance", content: [
            menuBarCheckbox,
            menuBarTip,
        ])

        let editConfigButton = NSButton(title: "Edit Config File…", target: self, action: #selector(editConfig))
        editConfigButton.controlSize = .regular
        let configTip = secondaryLabel("All settings are stored in a JSON file that scripts and agents can edit directly.")

        let configGroup = GroupBox(title: "Advanced", content: [editConfigButton, configTip])

        return tabContainer([monitoringGroup, appearanceGroup, configGroup])
    }

    // MARK: - Auto-Return Tab

    private func buildAutoReturnTab() -> NSView {
        autoReturnCheckbox.target = self
        autoReturnCheckbox.action = #selector(toggleAutoReturn)

        soundCheckbox.target = self
        soundCheckbox.action = #selector(toggleSound)

        let desc = secondaryLabel("When you dictate into one of these apps, Return is pressed automatically so your text is submitted.")

        let settingsGroup = GroupBox(title: "Auto-Return", content: [
            autoReturnCheckbox,
            soundCheckbox,
            desc,
        ])

        autoReturnTableView.delegate = self
        autoReturnTableView.dataSource = self
        autoReturnTableView.headerView = nil
        autoReturnTableView.rowHeight = 28
        autoReturnTableView.tag = 1
        autoReturnTableView.backgroundColor = .controlBackgroundColor

        let iconCol = NSTableColumn(identifier: .init("icon"))
        iconCol.width = 24
        autoReturnTableView.addTableColumn(iconCol)

        let appCol = NSTableColumn(identifier: .init("app"))
        appCol.title = "App"
        autoReturnTableView.addTableColumn(appCol)

        let scrollView = NSScrollView()
        scrollView.documentView = autoReturnTableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        let addRemove = makeAddRemoveControl(
            addAction: #selector(showAutoReturnAddMenu(_:)),
            removeAction: #selector(removeAutoReturnApp)
        )

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAutoReturnApps))
        resetButton.controlSize = .small

        let bottomBar = NSStackView(views: [addRemove, NSView(), resetButton])
        bottomBar.spacing = 8

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        settingsGroup.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(settingsGroup)
        container.addSubview(scrollView)
        container.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            settingsGroup.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            settingsGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            settingsGroup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: settingsGroup.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6),

            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        return container
    }

    // MARK: - Hooks Tab

    private func buildHooksTab() -> NSView {
        let desc = secondaryLabel("Run shell scripts after each dictation. Scripts receive the transcribed text as $1 and via environment variables (AQUA_TRANSCRIPTION, AQUA_FRONTMOST_APP, AQUA_TIMESTAMP).")
        desc.preferredMaxLayoutWidth = 500

        hooksTableView.delegate = self
        hooksTableView.dataSource = self
        hooksTableView.headerView = nil
        hooksTableView.rowHeight = 44
        hooksTableView.backgroundColor = .controlBackgroundColor

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "Hook"
        hooksTableView.addTableColumn(nameCol)

        let enabledCol = NSTableColumn(identifier: .init("enabled"))
        enabledCol.title = "On"
        enabledCol.width = 40
        hooksTableView.addTableColumn(enabledCol)

        let scrollView = NSScrollView()
        scrollView.documentView = hooksTableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addRemove = makeAddRemoveControl(
            addAction: #selector(addHook),
            removeAction: #selector(removeHook)
        )

        let editButton = NSButton(title: "Edit", target: self, action: #selector(editHook))
        editButton.controlSize = .small

        let bottomBar = NSStackView(views: [addRemove, editButton, NSView()])
        bottomBar.spacing = 8

        let container = NSView()
        desc.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(desc)
        container.addSubview(scrollView)
        container.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            desc.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            desc.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            desc.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6),

            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        return container
    }

    // MARK: - Status Tab

    private func buildStatusTab() -> NSView {
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),
        ])

        statusText.font = .systemFont(ofSize: 13)
        countText.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let statusRow = NSStackView(views: [NSTextField(labelWithString: "Status"), statusDot, statusText])
        statusRow.spacing = 6
        let countRow = formRow("Dictations detected", countText)

        let monitorGroup = GroupBox(title: "Monitor", content: [statusRow, countRow])

        lastAppText.font = .systemFont(ofSize: 13)
        lastTimeText.font = .systemFont(ofSize: 13)
        lastDictationText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        lastDictationText.textColor = .secondaryLabelColor
        lastDictationText.maximumNumberOfLines = 3
        lastDictationText.preferredMaxLayoutWidth = 420

        let copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!, target: self, action: #selector(copyLastDictation))
        copyButton.bezelStyle = .accessoryBarAction
        copyButton.isBordered = false
        copyButton.toolTip = "Copy to clipboard"

        let textRow = NSStackView(views: [lastDictationText, copyButton])
        textRow.alignment = .top
        textRow.spacing = 4

        let lastGroup = GroupBox(title: "Last Dictation", content: [
            formRow("App", lastAppText),
            formRow("Time", lastTimeText),
            textRow,
        ])

        return tabContainer([monitorGroup, lastGroup])
    }

    // MARK: - Helpers

    private func tabContainer(_ groups: [NSView]) -> NSView {
        let stack = NSStackView(views: groups)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])

        for group in groups {
            group.translatesAutoresizingMaskIntoConstraints = false
            group.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return container
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func monoLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func formRow(_ label: String, _ control: NSView) -> NSStackView {
        let row = NSStackView(views: [NSTextField(labelWithString: label), control])
        row.spacing = 8
        return row
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func makeAddRemoveControl(addAction: Selector, removeAction: Selector) -> NSSegmentedControl {
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
            NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!,
        ], trackingMode: .momentary, target: self, action: nil)
        control.segmentStyle = .smallSquare
        control.controlSize = .small

        control.setTag(0, forSegment: 0)
        control.setTag(1, forSegment: 1)
        control.target = self
        control.action = #selector(segmentedAction(_:))

        objc_setAssociatedObject(control, &AssociatedKeys.addAction, addAction, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(control, &AssociatedKeys.removeAction, removeAction, .OBJC_ASSOCIATION_RETAIN)

        return control
    }

    @objc private func segmentedAction(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        let action: Selector?
        if segment == 0 {
            action = objc_getAssociatedObject(sender, &AssociatedKeys.addAction) as? Selector
        } else {
            action = objc_getAssociatedObject(sender, &AssociatedKeys.removeAction) as? Selector
        }
        guard let action else { return }
        perform(action, with: sender)
    }

    // MARK: - Load / Save

    private func loadValues() {
        let c = configManager.config
        enabledCheckbox.state = c.enabled ? .on : .off
        clipboardHistoryCheckbox.state = c.clipboardHistory ? .on : .off
        menuBarCheckbox.state = c.showMenuBarIcon ? .on : .off
        autoReturnCheckbox.state = c.autoReturn.enabled ? .on : .off
        soundCheckbox.state = c.autoReturn.playSound ? .on : .off
        autoReturnTableView.reloadData()
        hooksTableView.reloadData()
        loadStatusValues()
    }

    private func loadStatusValues() {
        let running = monitor.isRunning
        statusDot.layer?.backgroundColor = (running ? NSColor.systemGreen : NSColor.systemRed).cgColor
        statusText.stringValue = running ? "Running" : "Stopped"
        countText.stringValue = "\(monitor.detectionCount)"

        if let last = monitor.lastDictation {
            let fmt = DateFormatter()
            fmt.timeStyle = .medium
            lastAppText.stringValue = last.frontmostApp
            lastTimeText.stringValue = fmt.string(from: last.timestamp)
            lastDictationText.stringValue = String(last.text.prefix(200))
        } else {
            lastAppText.stringValue = "—"
            lastTimeText.stringValue = "—"
            lastDictationText.stringValue = "No dictations detected yet."
        }
    }

    // MARK: - General Actions

    @objc private func toggleEnabled(_ sender: NSButton) {
        configManager.update { $0.enabled = sender.state == .on }
    }

    @objc private func toggleClipboardHistory(_ sender: NSButton) {
        configManager.update { $0.clipboardHistory = sender.state == .on }
    }

    @objc private func toggleMenuBar(_ sender: NSButton) {
        configManager.update { $0.showMenuBarIcon = sender.state == .on }
    }

    @objc private func copyLastDictation() {
        guard let text = monitor.lastDictation?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func editConfig() {
        let configURL = AppConfig.configFile
        if let zedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed") {
            NSWorkspace.shared.open([configURL], withApplicationAt: zedURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(configURL)
        }
    }

    // MARK: - Auto-Return Actions

    @objc private func toggleAutoReturn(_ sender: NSButton) {
        configManager.update { $0.autoReturn.enabled = sender.state == .on }
    }

    @objc private func toggleSound(_ sender: NSButton) {
        configManager.update { $0.autoReturn.playSound = sender.state == .on }
    }

    @objc private func showAutoReturnAddMenu(_ sender: Any?) {
        let menu = NSMenu()
        let runningItem = NSMenuItem(title: "Add Running App...", action: #selector(addRunningApp), keyEquivalent: "")
        runningItem.target = self
        let manualItem = NSMenuItem(title: "Add by Bundle ID...", action: #selector(addManualApp), keyEquivalent: "")
        manualItem.target = self
        menu.addItem(runningItem)
        menu.addItem(manualItem)

        if let control = sender as? NSSegmentedControl {
            let rect = control.bounds
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY), in: control)
        }
    }

    @objc private func removeAutoReturnApp() {
        let row = autoReturnTableView.selectedRow
        guard row >= 0, row < configManager.config.autoReturn.apps.count else { return }
        configManager.update { $0.autoReturn.apps.remove(at: row) }
    }

    @objc private func resetAutoReturnApps() {
        configManager.update { $0.autoReturn.apps = AutoReturnConfig.defaultApps }
    }

    @objc private func addManualApp() {
        let alert = NSAlert()
        alert.messageText = "Add App by Bundle ID"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "com.example.app"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = field

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let bundleId = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !bundleId.isEmpty else { return }
            self?.configManager.update { config in
                if !config.autoReturn.apps.contains(bundleId) {
                    config.autoReturn.apps.append(bundleId)
                }
            }
        }
    }

    @objc private func addRunningApp() {
        guard let window else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Select Running App"

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        let picker = RunningAppPicker(apps: runningApps) { [weak self, weak panel] bundleId in
            if let panel { window.endSheet(panel) }
            self?.configManager.update { config in
                if !config.autoReturn.apps.contains(bundleId) {
                    config.autoReturn.apps.append(bundleId)
                }
            }
        }
        picker.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            picker.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
        ])

        window.beginSheet(panel)
    }

    // MARK: - Hook Actions

    @objc private func addHook() {
        promptForHook(existing: nil) { [weak self] hook in
            self?.configManager.update { $0.hooks.append(hook) }
        }
    }

    @objc private func editHook() {
        let row = hooksTableView.selectedRow
        guard row >= 0, row < configManager.config.hooks.count else { return }
        let existing = configManager.config.hooks[row]
        promptForHook(existing: existing) { [weak self] updated in
            self?.configManager.update { $0.hooks[row] = updated }
        }
    }

    @objc private func removeHook() {
        let row = hooksTableView.selectedRow
        guard row >= 0, row < configManager.config.hooks.count else { return }
        configManager.update { $0.hooks.remove(at: row) }
    }

    private func promptForHook(existing: HookConfig?, completion: @escaping (HookConfig) -> Void) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "New Hook" : "Edit Hook"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8

        let nameField = NSTextField()
        nameField.placeholderString = "My Hook"
        nameField.stringValue = existing?.name ?? ""
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        grid.addRow(with: [NSTextField(labelWithString: "Name:"), nameField])

        let commandField = NSTextField()
        commandField.placeholderString = "~/.config/aqua-voice-hook/hooks/my-hook.sh"
        commandField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        commandField.stringValue = existing?.command ?? ""
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        grid.addRow(with: [NSTextField(labelWithString: "Command:"), commandField])

        let filterField = NSTextField()
        filterField.placeholderString = "e.g. Zed, com.apple.mail (optional)"
        filterField.stringValue = existing?.appFilter ?? ""
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        grid.addRow(with: [NSTextField(labelWithString: "App filter:"), filterField])

        let wrapper = NSView()
        wrapper.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: wrapper.topAnchor),
            grid.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        wrapper.layoutSubtreeIfNeeded()
        wrapper.setFrameSize(wrapper.fittingSize)
        alert.accessoryView = wrapper

        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue
            let command = commandField.stringValue
            guard !name.isEmpty, !command.isEmpty else { return }
            let filter = filterField.stringValue.isEmpty ? nil : filterField.stringValue
            completion(HookConfig(name: name, enabled: existing?.enabled ?? true, command: command, appFilter: filter))
        }
    }
}

// MARK: - Associated Keys

private enum AssociatedKeys {
    static var addAction = 0
    static var removeAction = 0
}

// MARK: - NSTableView

extension SettingsWindowController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView.tag == 1 { return configManager.config.autoReturn.apps.count }
        return configManager.config.hooks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView.tag == 1 { return autoReturnCell(tableColumn: tableColumn, row: row) }
        return hookCell(tableColumn: tableColumn, row: row)
    }

    private func autoReturnCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bundleId = configManager.config.autoReturn.apps[row]

        if tableColumn?.identifier.rawValue == "icon" {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyDown
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                imageView.image = NSWorkspace.shared.icon(forFile: appUrl.path)
            } else {
                imageView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            }
            return imageView
        }

        let appName = Self.appName(for: bundleId)
        let cell = NSStackView()
        cell.orientation = .horizontal
        cell.spacing = 8

        let nameLabel = NSTextField(labelWithString: appName ?? bundleId)
        nameLabel.font = .systemFont(ofSize: 12, weight: appName != nil ? .medium : .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        cell.addArrangedSubview(nameLabel)

        if appName != nil {
            let idLabel = NSTextField(labelWithString: bundleId)
            idLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            idLabel.textColor = .tertiaryLabelColor
            idLabel.lineBreakMode = .byTruncatingTail
            cell.addArrangedSubview(idLabel)
        }

        return cell
    }

    private func hookCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hook = configManager.config.hooks[row]

        if tableColumn?.identifier.rawValue == "enabled" {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(hookToggled(_:)))
            checkbox.state = hook.enabled ? .on : .off
            checkbox.tag = row
            return checkbox
        }

        let cell = NSStackView()
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 2

        let nameLabel = NSTextField(labelWithString: hook.name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)

        var subtitle = hook.command
        if let filter = hook.appFilter, !filter.isEmpty { subtitle += "  [\(filter)]" }
        let cmdLabel = NSTextField(labelWithString: subtitle)
        cmdLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        cmdLabel.textColor = .secondaryLabelColor
        cmdLabel.lineBreakMode = .byTruncatingTail

        cell.addArrangedSubview(nameLabel)
        cell.addArrangedSubview(cmdLabel)
        return cell
    }

    @objc private func hookToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < configManager.config.hooks.count else { return }
        configManager.update { $0.hooks[row].enabled = sender.state == .on }
    }

    private static func appName(for bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }
}

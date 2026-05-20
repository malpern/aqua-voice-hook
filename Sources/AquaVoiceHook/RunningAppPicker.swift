import AppKit

final class RunningAppPicker: NSView, NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate {
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private var allApps: [NSRunningApplication]
    private var filteredApps: [NSRunningApplication]
    private let onSelect: (String) -> Void

    init(apps: [NSRunningApplication], onSelect: @escaping (String) -> Void) {
        self.allApps = apps
        self.filteredApps = apps
        self.onSelect = onSelect
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        searchField.placeholderString = "Search apps..."
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self

        let iconCol = NSTableColumn(identifier: .init("icon"))
        iconCol.width = 24
        tableView.addTableColumn(iconCol)

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.width = 360
        tableView.addTableColumn(nameCol)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let selectButton = NSButton(title: "Add", target: self, action: #selector(selectClicked))
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.keyEquivalent = "\r"
        addSubview(selectButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: selectButton.topAnchor, constant: -8),
            selectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredApps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = filteredApps[row]

        if tableColumn?.identifier.rawValue == "icon" {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyDown
            imageView.image = app.icon
            return imageView
        }

        let cell = NSStackView()
        cell.orientation = .horizontal
        cell.spacing = 8

        let nameLabel = NSTextField(labelWithString: app.localizedName ?? "Unknown")
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let idLabel = NSTextField(labelWithString: app.bundleIdentifier ?? "")
        idLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        idLabel.textColor = .tertiaryLabelColor
        idLabel.lineBreakMode = .byTruncatingTail

        cell.addArrangedSubview(nameLabel)
        cell.addArrangedSubview(idLabel)
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            filteredApps = allApps
        } else {
            filteredApps = allApps.filter {
                ($0.localizedName ?? "").lowercased().contains(query) ||
                ($0.bundleIdentifier ?? "").lowercased().contains(query)
            }
        }
        tableView.reloadData()
    }

    @objc private func rowDoubleClicked() {
        selectCurrent()
    }

    @objc private func selectClicked() {
        selectCurrent()
    }

    private func selectCurrent() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredApps.count else { return }
        guard let bundleId = filteredApps[row].bundleIdentifier else { return }
        onSelect(bundleId)
    }
}

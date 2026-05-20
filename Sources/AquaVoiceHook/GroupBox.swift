import AppKit

final class GroupBox: NSView {
    private let titleLabel: NSTextField?
    private let contentStack: NSStackView

    init(title: String? = nil, content: [NSView]) {
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
            self.titleLabel = label
        } else {
            self.titleLabel = nil
        }

        contentStack = NSStackView(views: content)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10

        super.init(frame: .zero)
        wantsLayer = true

        if let titleLabel {
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)
        }

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        let contentTop = titleLabel?.bottomAnchor ?? topAnchor
        let topPad: CGFloat = titleLabel != nil ? 8 : 16

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentTop, constant: topPad),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        if let titleLabel {
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 10
    }
}

extension NSView {
    func wrappedInScroll() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = self
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }
}

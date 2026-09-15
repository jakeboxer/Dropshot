import AppKit

nonisolated struct DropZoneContent: Equatable, Sendable {
    enum SymbolTreatment: Equatable, Sendable {
        case orb
        case standalone
    }

    let symbolName: String
    let symbolTreatment: SymbolTreatment
    let title: String
    let subtitle: String
    let footer: String

    static func guidance(for format: OutputFormat) -> DropZoneContent {
        switch format {
        case .jpeg:
            DropZoneContent(
                symbolName: "arrow.down",
                symbolTreatment: .orb,
                title: "Drop HEIC here",
                subtitle: "Release to copy as JPEG",
                footer: "Hold ⌥ for PNG"
            )
        case .png:
            DropZoneContent(
                symbolName: "arrow.down",
                symbolTreatment: .orb,
                title: "Drop HEIC here",
                subtitle: "Release to copy as PNG",
                footer: "Release ⌥ for JPEG"
            )
        }
    }

    static func success(for format: OutputFormat) -> DropZoneContent {
        DropZoneContent(
            symbolName: "checkmark",
            symbolTreatment: .standalone,
            title: "Copied",
            subtitle: "Ready to paste",
            footer: format == .jpeg ? "Copied as JPEG" : "Copied as PNG"
        )
    }
}

@MainActor
final class DropZonePanelController: DropZonePresenting {
    let panel: DropZonePanel
    private(set) var content = DropZoneContent.guidance(for: .jpeg)

    private let dropView: DropZoneView
    private let onDestinationEntered: (Bool) -> Void
    private let onDestinationUpdated: (Bool) -> Void
    private let onDestinationExited: () -> Void
    private let onCancelled: () -> Void
    private let onAcceptedDrop: (AcceptedDrop) -> Void
    private let onRejectedDrop: () -> Void
    private weak var anchorView: NSView?

    init(
        onDestinationEntered: @escaping (Bool) -> Void = { _ in },
        onDestinationUpdated: @escaping (Bool) -> Void = { _ in },
        onDestinationExited: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onAcceptedDrop: @escaping (AcceptedDrop) -> Void = { _ in },
        onRejectedDrop: @escaping () -> Void = {}
    ) {
        self.onDestinationEntered = onDestinationEntered
        self.onDestinationUpdated = onDestinationUpdated
        self.onDestinationExited = onDestinationExited
        self.onCancelled = onCancelled
        self.onAcceptedDrop = onAcceptedDrop
        self.onRejectedDrop = onRejectedDrop
        dropView = DropZoneView(content: content)
        panel = DropZonePanel(contentView: dropView)
        dropView.onDestinationDrop = { [weak self] evidence in
            self?.acceptDestinationDrop(evidence) ?? false
        }
        dropView.onDestinationEntered = { [weak self] optionHeld in
            self?.onDestinationEntered(optionHeld)
        }
        dropView.onDestinationUpdated = { [weak self] optionHeld in
            self?.onDestinationUpdated(optionHeld)
        }
        dropView.onDestinationExited = { [weak self] in
            self?.onDestinationExited()
        }
        dropView.onCancelled = { [weak self] in
            self?.onCancelled()
        }
    }

    var registeredDraggedTypes: [NSPasteboard.PasteboardType] {
        dropView.registeredDraggedTypes
    }

    func anchor(to view: NSView?) {
        anchorView = view
    }

    func render(_ presentation: DropZonePresentation) {
        switch presentation {
        case .hidden:
            panel.orderOut(nil)
        case .guidance(let format):
            content = .guidance(for: format)
            dropView.render(content)
            positionBelowAnchor()
            panel.orderFrontRegardless()
        case .success(let format, _):
            content = .success(for: format)
            dropView.render(content)
            positionBelowAnchor()
            panel.orderFrontRegardless()
        }
    }

    @discardableResult
    func acceptDestinationDrop(_ evidence: DestinationDropEvidence) -> Bool {
        guard let input = evidence.input,
              let acceptedDrop = DragClassifier.acceptDrop(
                atDestination: evidence.descriptor,
                input: input,
                optionHeld: evidence.optionHeld
              ) else {
            onRejectedDrop()
            return false
        }
        onAcceptedDrop(acceptedDrop)
        return true
    }

    private func positionBelowAnchor() {
        guard let anchorView, let anchorWindow = anchorView.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(
            x: anchorFrame.midX - panel.frame.width / 2,
            y: anchorFrame.minY - 8 - panel.frame.height
        ))
    }
}

@MainActor
final class DropZonePanel: NSPanel {
    static let contentSize = NSSize(width: 202, height: 170)

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        self.contentView = contentView
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DropZoneView: NSVisualEffectView {
    var onDestinationEntered: (Bool) -> Void = { _ in }
    var onDestinationUpdated: (Bool) -> Void = { _ in }
    var onDestinationExited: () -> Void = {}
    var onCancelled: () -> Void = {}
    var onDestinationDrop: (DestinationDropEvidence) -> Bool = { _ in false }
    private let symbol = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let formatOrb = NSView()

    init(content: DropZoneContent) {
        super.init(frame: NSRect(origin: .zero, size: DropZonePanel.contentSize))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 30
        layer?.masksToBounds = true

        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType(rawValue: $0)
        }
        registerForDraggedTypes([.fileURL] + promiseTypes)
        installContent()
        render(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEligibleDestination(sender) else { return [] }
        onDestinationEntered(optionHeld)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEligibleDestination(sender) else { return [] }
        onDestinationUpdated(optionHeld)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDestinationExited()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onCancelled()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isEligibleDestination(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)
        let accepted = onDestinationDrop(DestinationDropEvidence(
            descriptor: descriptor,
            input: DragPasteboardSnapshot.singleFileInput(from: descriptor),
            optionHeld: optionHeld
        ))
        return accepted
    }

    private func isEligibleDestination(_ sender: any NSDraggingInfo) -> Bool {
        DragClassifier.classify(DragPasteboardSnapshot.descriptor(from: sender.draggingPasteboard)) == .eligible
    }

    private var optionHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    func render(_ content: DropZoneContent) {
        symbol.image = NSImage(
            systemSymbolName: content.symbolName,
            accessibilityDescription: content.title
        ) ?? NSImage()
        title.stringValue = content.title
        subtitle.stringValue = content.subtitle
        footer.stringValue = content.footer
        formatOrb.layer?.borderWidth = content.symbolTreatment == .orb ? 2 : 0
    }

    private func installContent() {
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .semibold)
        symbol.contentTintColor = .controlAccentColor

        formatOrb.wantsLayer = true
        formatOrb.layer?.cornerRadius = 31
        formatOrb.layer?.borderColor = NSColor.controlAccentColor.cgColor
        formatOrb.translatesAutoresizingMaskIntoConstraints = false
        symbol.translatesAutoresizingMaskIntoConstraints = false
        formatOrb.addSubview(symbol)

        NSLayoutConstraint.activate([
            formatOrb.widthAnchor.constraint(equalToConstant: 62),
            formatOrb.heightAnchor.constraint(equalToConstant: 62),
            symbol.centerXAnchor.constraint(equalTo: formatOrb.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: formatOrb.centerYAnchor)
        ])

        configureLabel(title, size: 15, weight: .semibold, color: .labelColor)
        configureLabel(subtitle, size: 12, weight: .medium, color: .secondaryLabelColor)
        configureLabel(footer, size: 11, weight: .regular, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [formatOrb, title, subtitle, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.setCustomSpacing(8, after: formatOrb)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12)
        ])
    }

    private func configureLabel(
        _ field: NSTextField,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
    }
}

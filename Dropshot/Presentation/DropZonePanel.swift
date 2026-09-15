import AppKit
import QuartzCore

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
    private static let transitionDuration: TimeInterval = 0.17
    private static let hiddenScale = 0.96

    let panel: DropZonePanel
    private(set) var content = DropZoneContent.guidance(for: .jpeg)

    private let dropView: DropZoneView
    private let onDestinationEntered: (Bool) -> Void
    private let onDestinationUpdated: (Bool) -> Void
    private let onDestinationExited: () -> Void
    private let onCancelled: () -> Void
    private let onAcceptedDrop: (AcceptedDrop) -> Void
    private let onRejectedDrop: () -> Void
    private let visibleFrameForAnchor: (NSWindow, NSRect) -> NSRect?
    private weak var anchorView: NSView?
    private var visibilityRevision: UInt = 0
    private var isVisibilityRequested = false

    init(
        onDestinationEntered: @escaping (Bool) -> Void = { _ in },
        onDestinationUpdated: @escaping (Bool) -> Void = { _ in },
        onDestinationExited: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onAcceptedDrop: @escaping (AcceptedDrop) -> Void = { _ in },
        onRejectedDrop: @escaping () -> Void = {},
        visibleFrameForAnchor: ((NSWindow, NSRect) -> NSRect?)? = nil
    ) {
        self.onDestinationEntered = onDestinationEntered
        self.onDestinationUpdated = onDestinationUpdated
        self.onDestinationExited = onDestinationExited
        self.onCancelled = onCancelled
        self.onAcceptedDrop = onAcceptedDrop
        self.onRejectedDrop = onRejectedDrop
        self.visibleFrameForAnchor = visibleFrameForAnchor ?? { anchorWindow, anchorFrame in
            anchorWindow.screen?.visibleFrame
                ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
        }
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
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        anchorView = view
        guard let view else { return }

        view.postsFrameChangedNotifications = true
        view.postsBoundsChangedNotifications = true
        observeAnchorGeometry(NSView.frameDidChangeNotification, object: view)
        observeAnchorGeometry(NSView.boundsDidChangeNotification, object: view)
        if let anchorWindow = view.window {
            observeAnchorGeometry(NSWindow.didMoveNotification, object: anchorWindow)
            observeAnchorGeometry(NSWindow.didResizeNotification, object: anchorWindow)
            observeAnchorGeometry(NSWindow.didChangeScreenNotification, object: anchorWindow)
        }
        observeAnchorGeometry(NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(anchorGeometryDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        if isVisibilityRequested {
            positionBelowAnchor()
        }
    }

    func render(_ presentation: DropZonePresentation) {
        switch presentation {
        case .hidden:
            dismiss()
        case .guidance(let format):
            content = .guidance(for: format)
            dropView.render(content)
            present()
        case .success(let format, _):
            content = .success(for: format)
            dropView.render(content)
            present()
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
        var panelFrame = NSRect(
            x: anchorFrame.midX - panel.frame.width / 2,
            y: anchorFrame.minY - 8 - panel.frame.height,
            width: panel.frame.width,
            height: panel.frame.height
        )
        if let visibleFrame = visibleFrameForAnchor(anchorWindow, anchorFrame) {
            panelFrame.origin.x = min(
                max(panelFrame.minX, visibleFrame.minX),
                visibleFrame.maxX - panelFrame.width
            )
            panelFrame.origin.y = min(
                max(panelFrame.minY, visibleFrame.minY),
                visibleFrame.maxY - panelFrame.height
            )
        }
        panel.setFrame(panelFrame, display: false)
    }

    private func observeAnchorGeometry(_ name: Notification.Name, object: Any?) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorGeometryDidChange),
            name: name,
            object: object
        )
    }

    @objc private func anchorGeometryDidChange() {
        guard isVisibilityRequested else { return }
        positionBelowAnchor()
    }

    private func present() {
        dropView.acceptsDestinationDrops = true
        positionBelowAnchor()
        guard !isVisibilityRequested else { return }

        isVisibilityRequested = true
        visibilityRevision &+= 1

        if !panel.isVisible {
            panel.alphaValue = 0
            setScale(Self.hiddenScale)
            panel.orderFrontRegardless()
        }

        animate(alpha: 1, scale: 1)
    }

    private func dismiss() {
        dropView.acceptsDestinationDrops = false
        guard isVisibilityRequested else { return }

        isVisibilityRequested = false
        visibilityRevision &+= 1
        let revision = visibilityRevision

        guard panel.isVisible else {
            panel.alphaValue = 0
            setScale(Self.hiddenScale)
            return
        }

        animate(alpha: 0, scale: Self.hiddenScale) { [weak self] in
            guard let self,
                  self.visibilityRevision == revision,
                  !self.isVisibilityRequested else { return }
            self.panel.orderOut(nil)
        }
    }

    private func animate(
        alpha: CGFloat,
        scale: CGFloat,
        completion: @escaping () -> Void = {}
    ) {
        animateScale(to: scale)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion()
        }
    }

    private func animateScale(to scale: CGFloat) {
        guard let layer = dropView.layer else { return }
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let targetTransform = topCenteredScale(scale, on: layer)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: currentTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        animation.duration = Self.transitionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "dropZoneVisibilityScale")
    }

    private func setScale(_ scale: CGFloat) {
        guard let layer = dropView.layer else { return }
        layer.removeAnimation(forKey: "dropZoneVisibilityScale")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = topCenteredScale(scale, on: layer)
        CATransaction.commit()
    }

    private func topCenteredScale(_ scale: CGFloat, on layer: CALayer) -> CATransform3D {
        // Keep the top center fixed without changing AppKit's layer anchor or view frame.
        let pivot = CGPoint(
            x: layer.bounds.midX,
            y: dropView.isFlipped ? layer.bounds.minY : layer.bounds.maxY
        )
        let anchor = CGPoint(
            x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
            y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y
        )
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform.m41 = (pivot.x - anchor.x) * (1 - scale)
        transform.m42 = (pivot.y - anchor.y) * (1 - scale)
        return transform
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
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .transient
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DropZoneView: NSVisualEffectView {
    var acceptsDestinationDrops = false
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
        guard acceptsDestinationDrops, isEligibleDestination(sender) else { return [] }
        onDestinationEntered(optionHeld)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard acceptsDestinationDrops, isEligibleDestination(sender) else { return [] }
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
        acceptsDestinationDrops && isEligibleDestination(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard acceptsDestinationDrops else { return false }
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

import AppKit
import CryptoKit
import UniformTypeIdentifiers

private enum DragKind: String {
    case fileURL = "File URL"
    case filePromise = "File Promise"
}

private final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let fixtureURL: URL
    private let lock = NSLock()
    private var deliveredDestinationURL: URL?

    init(fixtureURL: URL) {
        self.fixtureURL = fixtureURL
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        fixtureURL.lastPathComponent
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo destinationURL: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        print("Promise requested: \(destinationURL.path)")

        do {
            try FileManager.default.copyItem(at: fixtureURL, to: destinationURL)
            lock.lock()
            deliveredDestinationURL = destinationURL
            lock.unlock()
            print("Promise delivered: \(destinationURL.path)")
            completionHandler(nil)
        } catch {
            fputs("Promise delivery failed: \(error)\n", stderr)
            completionHandler(error)
        }
    }

    func lastDestinationURL() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return deliveredDestinationURL
    }
}

private final class DragSourceView: NSView, NSDraggingSource {
    private let kind: DragKind
    private let fixtureURL: URL
    private let promiseDelegate: PromiseDelegate
    private var initialMouseDownEvent: NSEvent?
    private var dragStarted = false

    init(kind: DragKind, fixtureURL: URL, promiseDelegate: PromiseDelegate) {
        self.kind = kind
        self.fixtureURL = fixtureURL
        self.promiseDelegate = promiseDelegate
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 12

        let title = NSTextField(labelWithString: kind.rawValue)
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center

        let detail = NSTextField(
            wrappingLabelWithString: kind == .fileURL
                ? "Drag the fixture as an ordinary file URL."
                : "Drag the fixture through NSFilePromiseProvider."
        )
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseDownEvent = event
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let initialMouseDownEvent else { return }
        dragStarted = true

        let pasteboardWriter: NSPasteboardWriting
        switch kind {
        case .fileURL:
            let item = NSPasteboardItem()
            item.setString(fixtureURL.absoluteString, forType: .fileURL)
            item.setData(Data(), forType: .init(UTType.heic.identifier))
            pasteboardWriter = item
        case .filePromise:
            pasteboardWriter = NSFilePromiseProvider(
                fileType: UTType.heic.identifier,
                delegate: promiseDelegate
            )
        }

        let item = NSDraggingItem(pasteboardWriter: pasteboardWriter)
        let image = NSWorkspace.shared.icon(forFile: fixtureURL.path)
        image.size = NSSize(width: 64, height: 64)
        let location = convert(initialMouseDownEvent.locationInWindow, from: nil)
        let frame = NSRect(
            x: location.x - 32,
            y: location.y - 32,
            width: 64,
            height: 64
        )
        item.setDraggingFrame(frame, contents: image)

        print("Starting \(kind.rawValue) drag for \(fixtureURL.path)")
        beginDraggingSession(with: [item], event: initialMouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseDownEvent = nil
        dragStarted = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        initialMouseDownEvent = nil
        dragStarted = false
        print("Drag ended with operation: \(operation.rawValue)")
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let fixtureURL: URL
    private let fixtureHash: String
    private var window: NSWindow?
    private var promiseDelegate: PromiseDelegate?
    private var evidenceLabel: NSTextField?

    init(fixtureURL: URL, fixtureHash: String) {
        self.fixtureURL = fixtureURL
        self.fixtureHash = fixtureHash
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let promiseDelegate = PromiseDelegate(fixtureURL: fixtureURL)
        self.promiseDelegate = promiseDelegate
        let fileURLSource = DragSourceView(
            kind: .fileURL,
            fixtureURL: fixtureURL,
            promiseDelegate: promiseDelegate
        )
        let promiseSource = DragSourceView(
            kind: .filePromise,
            fixtureURL: fixtureURL,
            promiseDelegate: promiseDelegate
        )
        fileURLSource.translatesAutoresizingMaskIntoConstraints = false
        promiseSource.translatesAutoresizingMaskIntoConstraints = false

        let fixtureLabel = NSTextField(
            wrappingLabelWithString: "Fixture: \(fixtureURL.lastPathComponent)\nDrag either card to Dropshot. Hold Option before releasing for PNG."
        )
        fixtureLabel.alignment = .center
        fixtureLabel.textColor = .secondaryLabelColor

        let sourceStack = NSStackView(views: [fileURLSource, promiseSource])
        sourceStack.orientation = .horizontal
        sourceStack.distribution = .fillEqually
        sourceStack.spacing = 16

        let inspectButton = NSButton(
            title: "Inspect Clipboard and Promise Cleanup",
            target: self,
            action: #selector(inspectEvidence)
        )
        inspectButton.bezelStyle = .rounded

        let evidenceLabel = NSTextField(
            wrappingLabelWithString: "After a drop, inspect the clipboard representations and last promised path."
        )
        evidenceLabel.alignment = .center
        evidenceLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        evidenceLabel.maximumNumberOfLines = 6
        self.evidenceLabel = evidenceLabel

        let contentStack = NSStackView(views: [fixtureLabel, sourceStack, inspectButton, evidenceLabel])
        contentStack.orientation = .vertical
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            fileURLSource.heightAnchor.constraint(equalToConstant: 150),
            promiseSource.heightAnchor.constraint(equalTo: fileURLSource.heightAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dropshot Drag Source"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }


    @objc private func inspectEvidence() {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems ?? []
        let types = items.flatMap(\.types)
        let hasJPEG = types.contains(.init("public.jpeg"))
        let hasPNG = types.contains(.init("public.png"))
        let hasTIFF = types.contains(.tiff)

        let promiseDescription: String
        if let destinationURL = promiseDelegate?.lastDestinationURL() {
            let operationDirectoryURL = destinationURL.deletingLastPathComponent()
            let inputExists = FileManager.default.fileExists(atPath: destinationURL.path)
            let operationDirectoryExists = FileManager.default.fileExists(
                atPath: operationDirectoryURL.path
            )
            promiseDescription = "Promise input exists: \(inputExists)\nOperation directory exists: \(operationDirectoryExists)\n\(operationDirectoryURL.path)"
        } else {
            promiseDescription = "Promise input: none delivered yet"
        }

        let currentFixtureHash = try? sha256(of: fixtureURL)
        let fixtureIsUnchanged = currentFixtureHash == fixtureHash
        let summary = "Items: \(items.count)  JPEG: \(hasJPEG)  PNG: \(hasPNG)  TIFF: \(hasTIFF)\nFixture unchanged: \(fixtureIsUnchanged)\n\(promiseDescription)"
        evidenceLabel?.stringValue = summary
        print("Clipboard types: \(types.map(\.rawValue))")
        print(summary)
    }
}

private func resolveFixtureURL(arguments: [String]) throws -> URL {
    let url: URL
    if let path = arguments.dropFirst().first {
        url = URL(fileURLWithPath: path).standardizedFileURL
    } else if let bundledFixture = Bundle.main.url(
        forResource: "oriented-metadata",
        withExtension: "heic"
    ) {
        url = bundledFixture
    } else {
        url = URL(fileURLWithPath: "DropshotTests/Fixtures/oriented-metadata.heic")
            .standardizedFileURL
    }

    guard url.pathExtension.lowercased() == "heic" else {
        throw NSError(
            domain: "DropshotDragSource",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Fixture must have a .heic extension: \(url.path)"]
        )
    }

    guard FileManager.default.isReadableFile(atPath: url.path) else {
        throw NSError(
            domain: "DropshotDragSource",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Fixture is not readable: \(url.path)"]
        )
    }

    return url
}

private func sha256(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url))
        .map { String(format: "%02x", $0) }
        .joined()
}

do {
    let fixtureURL = try resolveFixtureURL(arguments: CommandLine.arguments)
    let fixtureHash = try sha256(of: fixtureURL)
    print("Fixture: \(fixtureURL.path)")
    print("Fixture SHA-256: \(fixtureHash)")
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate(fixtureURL: fixtureURL, fixtureHash: fixtureHash)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
} catch {
    fputs("Dropshot Drag Source: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}

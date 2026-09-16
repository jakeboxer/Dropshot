import AppKit
import Testing
@testable import Dropshot

@MainActor
struct DropZonePanelTests {
    @Test
    func decorativeSymbolsDoNotInterceptDropZoneDrags() throws {
        let presentation = DropZonePanelController()
        defer { presentation.panel.orderOut(nil) }
        let root = try #require(presentation.panel.contentView)
        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        for state: DropZonePresentation in [.guidance(.jpeg), .guidance(.png), .success(.png, dropID: DropID(1))] {
            presentation.render(state)
            #expect(!root.registeredDraggedTypes.isEmpty)
            // AppKit can route an image drag to a registered child instead of its parent.
            for child in descendants(of: root) {
                #expect(child.registeredDraggedTypes.isEmpty)
            }
        }
    }

    @Test
    func dropZoneIsCenteredEightPointsBelowTheLiveAnchor() {
        let (anchorWindow, anchorView) = makeAnchor(frameInScreen: NSRect(
            x: 500,
            y: 850,
            width: 24,
            height: 24
        ))
        let presentation = DropZonePanelController(
            visibleFrameForAnchor: { _, _ in
                NSRect(x: 0, y: 0, width: 1_440, height: 900)
            }
        )
        defer {
            presentation.panel.orderOut(nil)
            anchorWindow.orderOut(nil)
        }

        presentation.anchor(to: anchorView)
        presentation.render(.guidance(.jpeg))

        #expect(presentation.panel.frame == NSRect(
            x: 411,
            y: 672,
            width: 202,
            height: 170
        ))
    }

    @Test
    func completeDropZoneFrameIsClampedToTheAnchorsDisplay() {
        let visibleFrame = NSRect(x: -1_920, y: -200, width: 1_920, height: 1_080)
        let examples: [(anchor: NSRect, expectedOrigin: NSPoint)] = [
            (NSRect(x: -1_915, y: 850, width: 24, height: 24), NSPoint(x: -1_920, y: 672)),
            (NSRect(x: -20, y: 850, width: 24, height: 24), NSPoint(x: -202, y: 672)),
            (NSRect(x: -1_000, y: -190, width: 24, height: 24), NSPoint(x: -1_089, y: -200)),
            (NSRect(x: -1_000, y: 1_100, width: 24, height: 24), NSPoint(x: -1_089, y: 710))
        ]

        for example in examples {
            let (anchorWindow, anchorView) = makeAnchor(frameInScreen: example.anchor)
            let presentation = DropZonePanelController(
                visibleFrameForAnchor: { _, _ in visibleFrame }
            )
            defer {
                presentation.panel.orderOut(nil)
                anchorWindow.orderOut(nil)
            }

            presentation.anchor(to: anchorView)
            presentation.render(.guidance(.jpeg))

            #expect(presentation.panel.frame.origin == example.expectedOrigin)
            #expect(visibleFrame.contains(presentation.panel.frame))
        }
    }

    @Test
    func visibleDropZoneFollowsTheLiveAnchor() {
        let (anchorWindow, anchorView) = makeAnchor(frameInScreen: NSRect(
            x: 300,
            y: 850,
            width: 24,
            height: 24
        ))
        let presentation = DropZonePanelController(
            visibleFrameForAnchor: { _, _ in
                NSRect(x: 0, y: 0, width: 1_440, height: 900)
            }
        )
        defer {
            presentation.panel.orderOut(nil)
            anchorWindow.orderOut(nil)
        }
        presentation.anchor(to: anchorView)
        presentation.render(.guidance(.jpeg))

        anchorWindow.setFrameOrigin(NSPoint(x: 600, y: 850))

        #expect(presentation.panel.frame.origin == NSPoint(x: 511, y: 672))
    }

    @Test
    func visibleDropZoneReclampsWhenTheDisplayContextChanges() {
        var visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let (anchorWindow, anchorView) = makeAnchor(frameInScreen: NSRect(
            x: 1_200,
            y: 850,
            width: 24,
            height: 24
        ))
        let presentation = DropZonePanelController(
            visibleFrameForAnchor: { _, _ in visibleFrame }
        )
        defer {
            presentation.panel.orderOut(nil)
            anchorWindow.orderOut(nil)
        }
        presentation.anchor(to: anchorView)
        presentation.render(.guidance(.jpeg))

        visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 900)
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        #expect(presentation.panel.frame.origin == NSPoint(x: 798, y: 672))

        visibleFrame = NSRect(x: -1_200, y: -200, width: 1_200, height: 1_080)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        #expect(presentation.panel.frame.origin == NSPoint(x: -202, y: 672))
        #expect(visibleFrame.contains(presentation.panel.frame))
    }

    @Test
    func dropZoneAnchorsToARealStatusItemOnTheCurrentScreen() async throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let button = try #require(statusItem.button)
        button.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)

        var liveContext: (window: NSWindow, screen: NSScreen, anchorFrame: NSRect)?
        for _ in 0..<20 {
            if let window = button.window, let screen = window.screen {
                let anchorFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                if screen.frame.contains(NSPoint(x: anchorFrame.midX, y: anchorFrame.midY)) {
                    liveContext = (window, screen, anchorFrame)
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let context = try #require(liveContext)
        let presentation = DropZonePanelController()
        defer { presentation.panel.orderOut(nil) }

        presentation.anchor(to: button)
        presentation.render(.guidance(.jpeg))

        #expect(context.screen.visibleFrame.contains(presentation.panel.frame))
        #expect(
            presentation.panel.frame.maxY == context.anchorFrame.minY - 8
                || presentation.panel.frame.minY == context.screen.visibleFrame.minY
                || presentation.panel.frame.maxY == context.screen.visibleFrame.maxY
        )
        #expect(
            presentation.panel.frame.midX == context.anchorFrame.midX
                || presentation.panel.frame.minX == context.screen.visibleFrame.minX
                || presentation.panel.frame.maxX == context.screen.visibleFrame.maxX
        )
    }

    @Test
    func staleDismissalCannotHideANewPresentation() async throws {
        let presentation = DropZonePanelController()
        defer { presentation.panel.orderOut(nil) }

        presentation.render(.guidance(.jpeg))
        try await Task.sleep(for: .milliseconds(250))
        presentation.render(.hidden)
        try await Task.sleep(for: .milliseconds(50))
        presentation.render(.guidance(.png))
        try await Task.sleep(for: .milliseconds(250))

        #expect(presentation.panel.isVisible)
        #expect(presentation.content == .guidance(for: .png))

        presentation.render(.hidden)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!presentation.panel.isVisible)
    }

    @Test
    func guidanceAndSuccessPresentationUseTheApprovedCopy() {
        let presentation = DropZonePanelController()

        presentation.render(.guidance(.png))
        #expect(presentation.content == DropZoneContent(
            symbolName: "arrow.down",
            symbolTreatment: .orb,
            title: "Drop HEIC here",
            subtitle: "Release to copy as PNG",
            footer: "Release ⌥ for JPEG"
        ))

        presentation.render(.success(.jpeg, dropID: DropID(1)))
        #expect(presentation.content == DropZoneContent(
            symbolName: "checkmark",
            symbolTreatment: .standalone,
            title: "Copied",
            subtitle: "Ready to paste",
            footer: "Copied as JPEG"
        ))
    }

    @Test
    func dropZoneRejectsIneligibleDestinationPayloadBeforeAcceptance() {
        var acceptedDrops: [AcceptedDrop] = []
        var rejectionCount = 0
        let presentation = DropZonePanelController(
            onAcceptedDrop: { acceptedDrops.append($0) },
            onRejectedDrop: { rejectionCount += 1 }
        )

        let wasAccepted = presentation.acceptDestinationDrop(DestinationDropEvidence(
            descriptor: DragDescriptor(items: [.other]),
            input: nil,
            optionHeld: false
        ))

        #expect(!wasAccepted)
        #expect(acceptedDrops.isEmpty)
        #expect(rejectionCount == 1)
    }

    @Test
    func dropZoneIsANonactivatingRegisteredPanelWithDefaultGuidance() {
        let presentation = DropZonePanelController()

        #expect(presentation.panel.styleMask.contains(.nonactivatingPanel))
        #expect(!presentation.panel.canBecomeKey)
        #expect(!presentation.panel.canBecomeMain)
        #expect(presentation.panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(presentation.panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(presentation.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(presentation.panel.contentRect(forFrameRect: presentation.panel.frame).size == CGSize(
            width: 202,
            height: 170
        ))
        #expect(presentation.content == DropZoneContent(
            symbolName: "arrow.down",
            symbolTreatment: .orb,
            title: "Drop HEIC here",
            subtitle: "Release to copy as JPEG",
            footer: "Hold ⌥ for PNG"
        ))

        let registeredTypes = Set(presentation.registeredDraggedTypes)
        #expect(registeredTypes.contains(.fileURL))
        for type in NSFilePromiseReceiver.readableDraggedTypes {
            #expect(registeredTypes.contains(NSPasteboard.PasteboardType(type)))
        }
    }

    private func makeAnchor(frameInScreen: NSRect) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(origin: frameInScreen.origin, size: frameInScreen.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(origin: .zero, size: frameInScreen.size))
        window.contentView = view
        return (window, view)
    }
}

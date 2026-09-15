import AppKit
import Testing
@testable import Dropshot

@MainActor
struct DropZonePanelTests {
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
}

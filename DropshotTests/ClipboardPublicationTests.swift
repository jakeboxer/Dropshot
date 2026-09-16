import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
struct ClipboardPublicationTests {
    private static let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)

    @Test
    func jpegHandoffPublishesOneItemWithExactJPEGAndTIFFRepresentations() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let jpeg = Data([0xFF, 0xD8, 0x11, 0xFF, 0xD9])
        let tiff = Data([0x49, 0x49, 0x2A, 0x00, 0x22])
        let firstOldItem = NSPasteboardItem()
        firstOldItem.setString("replace me", forType: .string)
        let secondOldItem = NSPasteboardItem()
        secondOldItem.setString("replace me too", forType: .string)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([firstOldItem, secondOldItem]))

        try ClipboardPublication(pasteboard: pasteboard).publish(handoff(
            format: .jpeg,
            requestedFormatData: jpeg,
            tiffData: tiff
        ))

        let item = try #require(pasteboard.pasteboardItems?.only)
        #expect(Set(item.types) == Set([Self.jpegType, .tiff]))
        #expect(item.data(forType: Self.jpegType) == jpeg)
        #expect(item.data(forType: .tiff) == tiff)
    }

    @Test
    func pngHandoffPublishesOneItemWithExactPNGAndTIFFRepresentations() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
        let tiff = Data([0x4D, 0x4D, 0x00, 0x2A, 0x33])

        try ClipboardPublication(pasteboard: pasteboard).publish(handoff(
            format: .png,
            requestedFormatData: png,
            tiffData: tiff
        ))

        let item = try #require(pasteboard.pasteboardItems?.only)
        #expect(Set(item.types) == Set([.png, .tiff]))
        #expect(item.data(forType: .png) == png)
        #expect(item.data(forType: .tiff) == tiff)
    }

    @Test(arguments: [
        ConvertedImage(requestedFormatData: Data(), tiffData: Data([2])),
        ConvertedImage(requestedFormatData: Data([1]), tiffData: Data()),
    ])
    func missingRepresentationLeavesExistingClipboardContentsUnchanged(
        convertedImage: ConvertedImage
    ) throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let existingItem = NSPasteboardItem()
        existingItem.setString("keep me", forType: .string)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([existingItem]))
        let changeCount = pasteboard.changeCount

        #expect(throws: ClipboardPublicationError.missingRepresentation) {
            try ClipboardPublication(pasteboard: pasteboard).publish(ClipboardHandoff(
                dropID: DropID(1),
                format: .jpeg,
                convertedImage: convertedImage
            ))
        }

        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.pasteboardItems?.only?.types == [.string])
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test
    func publicationFailureThrows() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let publication = ClipboardPublication(
            pasteboard: pasteboard,
            writeObjects: { _, _ in false }
        )

        #expect(throws: ClipboardPublicationError.publicationFailed) {
            try publication.publish(handoff(
                format: .jpeg,
                requestedFormatData: Data([1]),
                tiffData: Data([2])
            ))
        }
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("DropshotTests.ClipboardPublication.\(UUID().uuidString)"))
    }

    private func handoff(
        format: OutputFormat,
        requestedFormatData: Data,
        tiffData: Data
    ) -> ClipboardHandoff {
        ClipboardHandoff(
            dropID: DropID(1),
            format: format,
            convertedImage: ConvertedImage(
                requestedFormatData: requestedFormatData,
                tiffData: tiffData
            )
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

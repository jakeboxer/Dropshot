import AppKit
import UniformTypeIdentifiers

nonisolated enum ClipboardPublicationError: Error, Equatable, Sendable {
    case missingRepresentation
    case representationPreparationFailed
    case publicationFailed
}

@MainActor
final class ClipboardPublication: ClipboardPublishing {
    typealias ObjectWriter = (_ pasteboard: NSPasteboard, _ items: [NSPasteboardItem]) -> Bool

    private let pasteboard: NSPasteboard
    private let writeObjects: ObjectWriter

    init(
        pasteboard: NSPasteboard = .general,
        writeObjects: @escaping ObjectWriter = { pasteboard, items in
            pasteboard.writeObjects(items)
        }
    ) {
        self.pasteboard = pasteboard
        self.writeObjects = writeObjects
    }

    func publish(_ handoff: ClipboardHandoff) throws {
        let image = handoff.convertedImage
        guard !image.requestedFormatData.isEmpty,
              !image.tiffData.isEmpty else {
            throw ClipboardPublicationError.missingRepresentation
        }

        let item = NSPasteboardItem()
        guard item.setData(image.requestedFormatData, forType: pasteboardType(for: handoff.format)),
              item.setData(image.tiffData, forType: .tiff) else {
            throw ClipboardPublicationError.representationPreparationFailed
        }

        pasteboard.clearContents()
        guard writeObjects(pasteboard, [item]) else {
            throw ClipboardPublicationError.publicationFailed
        }
    }

    private func pasteboardType(for format: OutputFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .jpeg:
            NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        case .png:
            .png
        }
    }
}

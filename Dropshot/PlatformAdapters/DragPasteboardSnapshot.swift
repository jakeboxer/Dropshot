import AppKit
import UniformTypeIdentifiers

@MainActor
enum DragPasteboardSnapshot {
    private static let heicType = NSPasteboard.PasteboardType(UTType.heic.identifier)

    static func observation(
        from pasteboard: NSPasteboard,
        detectedFileContentType: UTType? = nil
    ) -> DragDescriptor {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return DragDescriptor(items: nil)
        }

        let promiseTypeNames = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let promiseReceivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
        var promiseIndex = 0

        let items = pasteboardItems.map { item -> DragDescriptor.Item in
            if item.types.contains(.fileURL) {
                let advertisedType = contentType(advertisedBy: item)
                let detectedType = pasteboardItems.count == 1
                    ? detectedFileContentType.map { contentType($0.identifier) } ?? .unknown
                    : .unknown
                return .fileReference(contentType: advertisedType == .unknown ? detectedType : advertisedType)
            }

            if item.types.contains(where: { promiseTypeNames.contains($0.rawValue) }) {
                defer { promiseIndex += 1 }
                guard promiseReceivers.indices.contains(promiseIndex) else {
                    return .filePromise(contentTypes: [])
                }
                return .filePromise(contentTypes: promiseReceivers[promiseIndex].fileTypes.map(contentType))
            }

            return .other
        }
        return DragDescriptor(items: items)
    }

    // Destination-only: reading file URL objects here establishes AppKit's
    // user-selected access grant and must never be used for drag observation.
    static func descriptor(from pasteboard: NSPasteboard) -> DragDescriptor {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let promiseReceivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self], options: nil
        ) as? [NSFilePromiseReceiver] ?? []
        return destinationDescriptor(
            from: pasteboard,
            fileURLs: urls,
            promiseReceivers: promiseReceivers
        )
    }

    static func destinationEvidence(
        from pasteboard: NSPasteboard,
        optionHeld: Bool
    ) -> DestinationDropEvidence {
        // Materialize scoped URLs before any other destination-time reads.
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let promiseReceivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self], options: nil
        ) as? [NSFilePromiseReceiver] ?? []
        let descriptor = destinationDescriptor(
            from: pasteboard,
            fileURLs: urls,
            promiseReceivers: promiseReceivers
        )
        let input: DroppedInput?
        if urls.count == 1,
           descriptor.items?.count == 1,
           case .fileURL(let url, _) = descriptor.items?.first,
           url == urls[0] {
            input = DroppedInput(fileURL: urls[0])
        } else if promiseReceivers.count == 1,
                  descriptor.items == [.filePromise(contentTypes: [.heic])],
                  promiseReceivers[0].fileTypes.map(contentType) == [.heic] {
            let receipt = FilePromiseReceipt(receiver: promiseReceivers[0])
            input = DroppedInput(receivePromisedFile: receipt.receive)
        } else {
            input = nil
        }
        return DestinationDropEvidence(
            descriptor: descriptor,
            input: input,
            optionHeld: optionHeld
        )
    }

    static func destinationInput(
        from pasteboard: NSPasteboard,
        descriptor: DragDescriptor
    ) -> DroppedInput? {
        guard descriptor.items?.count == 1,
              let item = descriptor.items?.first else {
            return nil
        }

        switch item {
        case .fileURL(let url, _):
            // Preserve AppKit's sandbox access instead of rebuilding the resource
            // URL from the descriptor's string-only observation.
            guard let urls = pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], urls.count == 1, urls[0] == url else { return nil }
            return DroppedInput(fileURL: urls[0])
        case .fileReference:
            return nil
        case .filePromise(let contentTypes):
            guard contentTypes == [.heic] else { return nil }
            let receivers = pasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self],
                options: nil
            ) as? [NSFilePromiseReceiver] ?? []
            guard receivers.count == 1,
                  receivers[0].fileTypes.map(contentType) == [.heic] else {
                return nil
            }
            let receipt = FilePromiseReceipt(receiver: receivers[0])
            return DroppedInput(receivePromisedFile: receipt.receive)
        case .other:
            return nil
        }
    }

    private static func destinationDescriptor(
        from pasteboard: NSPasteboard,
        fileURLs: [URL],
        promiseReceivers: [NSFilePromiseReceiver]
    ) -> DragDescriptor {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return DragDescriptor(items: nil)
        }
        let promiseTypeNames = Set(NSFilePromiseReceiver.readableDraggedTypes)
        var urlIndex = 0
        var promiseIndex = 0
        return DragDescriptor(items: pasteboardItems.map { item in
            if item.types.contains(.fileURL) {
                defer { urlIndex += 1 }
                guard fileURLs.indices.contains(urlIndex) else { return .other }
                return .fileURL(fileURLs[urlIndex], contentType: contentType(advertisedBy: item))
            }
            if item.types.contains(where: { promiseTypeNames.contains($0.rawValue) }) {
                defer { promiseIndex += 1 }
                guard promiseReceivers.indices.contains(promiseIndex) else {
                    return .filePromise(contentTypes: [])
                }
                return .filePromise(contentTypes: promiseReceivers[promiseIndex].fileTypes.map(contentType))
            }
            return .other
        })
    }

    private static func contentType(advertisedBy item: NSPasteboardItem) -> DragDescriptor.ContentType {
        if item.types.contains(heicType) {
            return .heic
        }
        for pasteboardType in item.types {
            guard let type = UTType(pasteboardType.rawValue), type.conforms(to: .image) else {
                continue
            }
            if type == .image {
                return .unknown
            }
            return .other
        }
        return .unknown
    }

    private static func contentType(_ identifier: String) -> DragDescriptor.ContentType {
        guard identifier == UTType.heic.identifier else {
            return identifier == UTType.image.identifier ? .unknown : .other
        }
        return .heic
    }
}

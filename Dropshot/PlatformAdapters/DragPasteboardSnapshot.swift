import AppKit
import UniformTypeIdentifiers

@MainActor
enum DragPasteboardSnapshot {
    private static let heicType = NSPasteboard.PasteboardType(UTType.heic.identifier)

    static func descriptor(from pasteboard: NSPasteboard) -> DragDescriptor {
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
            if let url = fileURL(from: item) {
                return .fileURL(url, contentType: contentType(advertisedBy: item))
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
            return DroppedInput(fileURL: url)
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

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let value = item.string(forType: .fileURL),
              let url = URL(string: value),
              url.isFileURL else {
            return nil
        }
        return url
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
